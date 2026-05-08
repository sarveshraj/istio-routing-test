# Istio VirtualService sourceNamespace Routing Test

This test environment validates Istio VirtualService routing based on sourceNamespace matching.

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

## Files

- `kind-config.yaml` - Kind cluster configuration
- `mock-services.yaml` - Namespaces and mock services
- `virtualservice.yaml` - Istio VirtualService with sourceNamespace routing
- `test-pods.yaml` - Test client pods

## Verification

The test confirms that Istio VirtualService with sourceNamespace matching works correctly for routing traffic from specific namespaces to different backend services. This validates the configuration being deployed to production in PR #74409 and PR #74438.
