# Istio VirtualService sourceNamespace Routing Test

This test environment validates Istio VirtualService routing based on sourceNamespace matching.

## Quick Start

Run the automated test script to set up everything and run the tests:

```bash
./run-test.sh
```

The script will:
- ✓ Check and install prerequisites (kind, kubectl, istioctl)
- ✓ Create a local Kind cluster
- ✓ Install Istio
- ✓ Deploy mock services
- ✓ Apply VirtualService configuration
- ✓ Run routing tests
- ✓ Display results

## Setup Summary

The test environment includes:
- **service-a-ns**: Contains service-a (represents stage environment)
- **service-b-ns**: Contains service-b (represents sandbox environment)
- **client-readonly-ns**: Client namespace representing read-only webscripts
- **client-write-ns**: Client namespace representing write webscripts

## VirtualService Configuration

The VirtualService at `service-a.service-a-ns.svc.cluster.local` implements:
1. Traffic from `client-readonly-ns` → routed to `service-b` (sandbox)
2. Traffic from other namespaces → routed to `service-a` (default)

## Test Results

### Test 1: Read-only namespace routing
```bash
kubectl exec -n client-readonly-ns test-client-readonly -- curl -s http://service-a.service-a-ns.svc.cluster.local
```
**Result**: `Response from SERVICE-B` ✅

Confirms that traffic from read-only namespace is correctly routed to service-b.

### Test 2: Default namespace routing
```bash
kubectl exec -n client-write-ns test-client-write -- curl -s http://service-a.service-a-ns.svc.cluster.local
```
**Result**: `Response from SERVICE-A` ✅

Confirms that traffic from other namespaces follows the default route to service-a.

## Cleanup

To delete the test cluster:
```bash
kind delete cluster --name istio-routing-test
```

## Manual Setup

If you prefer to run the steps manually instead of using the automated script:

### Prerequisites
- kind
- kubectl
- istioctl

### Steps
1. Create the cluster: `kind create cluster --config kind-config.yaml`
2. Install Istio: `istioctl install --set profile=demo -y`
3. Deploy services: `kubectl apply -f mock-services.yaml`
4. Apply VirtualService: `kubectl apply -f virtualservice.yaml`
5. Deploy test pods: `kubectl apply -f test-pods.yaml`
6. Run tests (see Test Results section below)

## Files

- `run-test.sh` - Automated test script (recommended)
- `kind-config.yaml` - Kind cluster configuration
- `mock-services.yaml` - Namespaces and mock services
- `virtualservice.yaml` - Istio VirtualService with sourceNamespace routing
- `test-pods.yaml` - Test client pods

## Verification

The test confirms that Istio VirtualService with sourceNamespace matching works correctly for routing traffic from specific namespaces to different backend services. This validates the configuration being deployed to production in PR #74409 and PR #74438.
