# Lab 14 - Network Policies

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Security |
| **Lab** | 14 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-45 minutes |
| **Estimated Cost** | Free |
| **Terraform** | No |
| **Kubernetes** | Yes |
| **GitOps** | Yes |

## Introduction

This lab introduces Kubernetes NetworkPolicies for controlling pod-to-pod and pod-to-platform traffic.

Network policies provide workload isolation inside the cluster and make application connectivity explicit instead of relying on default open namespace networking.

## Outcome
Implement and validate Network Policies in the complete platform reference implementation.

## Prerequisites
Complete Lab 01 - Lab 13. AWS CLI, Terraform, kubectl and Helm must be installed, with repository URLs configured.

## Repository Changes
Primary implementation: `helm-charts/charts/sample-api/templates/networkpolicy.yaml`.

## Files to Review
Review the NetworkPolicy desired-state files and update any environment-specific values before validation.

## Step-by-Step Implementation

1. Review `helm-charts/charts/sample-api/templates/networkpolicy.yaml` and the chart values controlling NetworkPolicy rendering.
2. Confirm the cluster CNI enforces Kubernetes NetworkPolicy before relying on traffic-denial results.
3. Run `helm lint` and render the chart with NetworkPolicy enabled:

   ```bash
   cd "$WORKSPACE"
   helm lint helm-charts/charts/sample-api
   helm template sample-api helm-charts/charts/sample-api --set rollout.enabled=false | grep -A20 '^kind: NetworkPolicy'
   ```

4. Commit and push any chart or value changes.
5. Let Argo CD reconcile `sample-api`, then run positive and negative connectivity tests:

   ```bash
   kubectl -n argocd get application sample-api -o wide
   ```

6. Confirm that the cluster networking implementation enforces Kubernetes NetworkPolicy before interpreting results:

   ```bash
   kubectl -n sample-api-dev get networkpolicy -o yaml
   kubectl -n sample-api-dev get pods -l app.kubernetes.io/name=sample-api -o wide
   ```

7. Run positive and negative tests using temporary pods:

   ```bash
   kubectl -n sample-api-dev run allowed-client --rm -it --restart=Never \
     --image=curlimages/curl -- curl -fsS http://sample-api/
   kubectl create namespace network-denied-test
   kubectl -n network-denied-test run denied-client --rm -it --restart=Never \
     --image=curlimages/curl --max-time=5 -- curl -fsS http://sample-api.sample-api-dev.svc.cluster.local/
   ```

8. Validate DNS and required HTTPS egress from the application pod.
9. Delete the temporary namespace after validation:

   ```bash
   kubectl delete namespace network-denied-test
   ```

## Expected Results
The `sample-api` chart renders a NetworkPolicy and the deployed application still passes health checks while unintended traffic is denied.

## Validation
Pass criteria:

- The intended ingress source can reach the API.
- An unintended namespace cannot reach the API.
- DNS resolution still works.
- Only documented outbound destinations/ports work.
- Existing probes and monitoring traffic continue to function.
- Denials are reproducible and disappear when the policy is removed in a controlled test.

If the installed AWS VPC CNI configuration does not have NetworkPolicy enforcement enabled, the manifest may exist while traffic remains unrestricted; that is a failed validation.

## Troubleshooting
Start with the rendered policy and namespace events:

```bash
kubectl -n sample-api-dev describe networkpolicy sample-api
kubectl -n sample-api-dev get pods,svc,endpoints -o wide
kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
```

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Delete only temporary test pods and namespaces created during validation. Keep the Git-managed NetworkPolicy in place.

## Next Steps
Continue with [Lab 15 - Multi-Environment Platform](./lab15-multi-environment-platform.md).
