#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CLUSTER_NAME="istio-routing-test"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Print colored output
print_info() {
    echo -e "${BLUE}ℹ ${1}${NC}"
}

print_success() {
    echo -e "${GREEN}✓ ${1}${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ ${1}${NC}"
}

print_error() {
    echo -e "${RED}✗ ${1}${NC}"
}

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}${1}${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        print_error "Unsupported OS: $OSTYPE"
        exit 1
    fi
    print_info "Detected OS: $OS"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install kubectl
install_kubectl() {
    print_info "Installing kubectl..."
    if [[ "$OS" == "macos" ]]; then
        if command_exists brew; then
            brew install kubectl
        else
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl"
            chmod +x kubectl
            sudo mv kubectl /usr/local/bin/
        fi
    elif [[ "$OS" == "linux" ]]; then
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
    fi
    print_success "kubectl installed"
}

# Install kind
install_kind() {
    print_info "Installing kind..."
    if [[ "$OS" == "macos" ]]; then
        if command_exists brew; then
            brew install kind
        else
            curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-darwin-arm64
            chmod +x kind
            sudo mv kind /usr/local/bin/
        fi
    elif [[ "$OS" == "linux" ]]; then
        curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
        chmod +x kind
        sudo mv kind /usr/local/bin/
    fi
    print_success "kind installed"
}

# Install istioctl
install_istioctl() {
    print_info "Installing istioctl..."
    cd "$SCRIPT_DIR"
    curl -L https://istio.io/downloadIstio | sh -

    # Find the istio directory
    ISTIO_DIR=$(find . -maxdepth 1 -type d -name "istio-*" | head -n 1)
    if [[ -z "$ISTIO_DIR" ]]; then
        print_error "Failed to find Istio directory"
        exit 1
    fi

    export PATH="$SCRIPT_DIR/$ISTIO_DIR/bin:$PATH"
    print_success "istioctl installed at $SCRIPT_DIR/$ISTIO_DIR/bin"
}

# Check and install prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    detect_os

    # Check kubectl
    if command_exists kubectl; then
        print_success "kubectl is already installed ($(kubectl version --client --short 2>/dev/null || kubectl version --client))"
    else
        install_kubectl
    fi

    # Check kind
    if command_exists kind; then
        print_success "kind is already installed ($(kind version))"
    else
        install_kind
    fi

    # Check istioctl
    if command_exists istioctl; then
        print_success "istioctl is already installed ($(istioctl version --remote=false 2>/dev/null))"
    else
        install_istioctl
    fi
}

# Create kind cluster
create_cluster() {
    print_header "Creating Kind Cluster"

    # Check if cluster already exists
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        print_warning "Cluster '${CLUSTER_NAME}' already exists"
        read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Deleting existing cluster..."
            kind delete cluster --name "$CLUSTER_NAME"
        else
            print_info "Using existing cluster"
            return
        fi
    fi

    print_info "Creating cluster '${CLUSTER_NAME}'..."
    kind create cluster --config "$SCRIPT_DIR/kind-config.yaml"
    print_success "Cluster created successfully"
}

# Install Istio
install_istio() {
    print_header "Installing Istio"

    # Make sure istioctl is in PATH
    if ! command_exists istioctl; then
        ISTIO_DIR=$(find "$SCRIPT_DIR" -maxdepth 1 -type d -name "istio-*" | head -n 1)
        if [[ -n "$ISTIO_DIR" ]]; then
            export PATH="$ISTIO_DIR/bin:$PATH"
        fi
    fi

    print_info "Installing Istio with demo profile..."
    istioctl install --set profile=demo -y
    print_success "Istio installed successfully"
}

# Deploy services
deploy_services() {
    print_header "Deploying Mock Services"

    print_info "Applying mock services..."
    kubectl apply -f "$SCRIPT_DIR/mock-services.yaml"

    print_info "Waiting for deployments to be ready..."
    kubectl wait --for=condition=ready pod -l app=service-a -n service-a-ns --timeout=120s
    kubectl wait --for=condition=ready pod -l app=service-b -n service-b-ns --timeout=120s

    print_success "Services deployed and ready"
}

# Apply VirtualService
apply_virtualservice() {
    print_header "Applying VirtualService"

    print_info "Applying VirtualService configuration..."
    kubectl apply -f "$SCRIPT_DIR/virtualservice.yaml"

    # Give Istio a moment to process the config
    sleep 2

    print_success "VirtualService applied"
}

# Deploy test pods
deploy_test_pods() {
    print_header "Deploying Test Pods"

    print_info "Applying test pods..."
    kubectl apply -f "$SCRIPT_DIR/test-pods.yaml"

    print_info "Waiting for test pods to be ready..."
    kubectl wait --for=condition=ready pod test-client-readonly -n client-readonly-ns --timeout=120s
    kubectl wait --for=condition=ready pod test-client-write -n client-write-ns --timeout=120s

    print_success "Test pods deployed and ready"
}

# Run tests
run_tests() {
    print_header "Running Tests"

    print_info "Test 1: Request from read-only namespace (should route to SERVICE-B)"
    RESULT1=$(kubectl exec -n client-readonly-ns test-client-readonly -- curl -s http://service-a.service-a-ns.svc.cluster.local)
    echo "Response: $RESULT1"

    if [[ "$RESULT1" == "Response from SERVICE-B" ]]; then
        print_success "✓ Test 1 PASSED: Read-only namespace correctly routed to SERVICE-B"
    else
        print_error "✗ Test 1 FAILED: Expected 'Response from SERVICE-B', got '$RESULT1'"
        exit 1
    fi

    echo ""

    print_info "Test 2: Request from write namespace (should route to SERVICE-A)"
    RESULT2=$(kubectl exec -n client-write-ns test-client-write -- curl -s http://service-a.service-a-ns.svc.cluster.local)
    echo "Response: $RESULT2"

    if [[ "$RESULT2" == "Response from SERVICE-A" ]]; then
        print_success "✓ Test 2 PASSED: Write namespace correctly routed to SERVICE-A (default)"
    else
        print_error "✗ Test 2 FAILED: Expected 'Response from SERVICE-A', got '$RESULT2'"
        exit 1
    fi
}

# Print summary
print_summary() {
    print_header "Test Summary"

    echo -e "${GREEN}All tests passed successfully! ✅${NC}"
    echo ""
    echo "What was tested:"
    echo "  • VirtualService routing based on sourceNamespace"
    echo "  • Traffic from client-readonly-ns → service-b"
    echo "  • Traffic from client-write-ns → service-a (default)"
    echo ""
    echo "This validates that Istio VirtualService with sourceNamespace matching"
    echo "works correctly for routing traffic from specific namespaces to different"
    echo "backend services."
    echo ""
    echo "Cluster info:"
    echo "  • Cluster name: $CLUSTER_NAME"
    echo "  • Context: kind-$CLUSTER_NAME"
    echo ""
    echo "To interact with the cluster:"
    echo "  kubectl config use-context kind-$CLUSTER_NAME"
    echo ""
    echo "To delete the cluster:"
    echo "  kind delete cluster --name $CLUSTER_NAME"
}

# Cleanup function
cleanup() {
    print_header "Cleanup"
    read -p "Do you want to delete the cluster? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deleting cluster..."
        kind delete cluster --name "$CLUSTER_NAME"
        print_success "Cluster deleted"
    else
        print_info "Cluster preserved for manual inspection"
    fi
}

# Main execution
main() {
    cd "$SCRIPT_DIR"

    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Istio VirtualService sourceNamespace Routing Test        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_prerequisites
    create_cluster
    install_istio
    deploy_services
    apply_virtualservice
    deploy_test_pods
    run_tests
    print_summary

    echo ""
    cleanup
}

# Run main function
main
