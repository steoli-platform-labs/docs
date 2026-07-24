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

Concepts introduced in this lab include NetworkPolicies, pod selectors, namespace selectors, ingress rules, egress rules, DNS egress and CNI enforcement. See the [Concepts Reference](../concepts/README.md) for the security model behind Kubernetes network isolation.

## Outcome
Implement and validate Network Policies in the complete platform reference implementation.

## Prerequisites
Complete Lab 01 - Lab 13. AWS CLI, Terraform, kubectl and Helm must be installed, with repository URLs configured.

## Repository Changes
Primary implementation: `helm-charts/charts/sample-api/templates/networkpolicy.yaml` and the sample API chart values that enable or tune policy behavior.

## Files to Review
Review these files before validation:

- `helm-charts/charts/sample-api/templates/networkpolicy.yaml`: rendered Kubernetes NetworkPolicy.
- `helm-charts/charts/sample-api/values.yaml`: chart values that control service ports, rollout mode and policy-related behavior.
- `platform-config/clusters/dev/sample-api.yaml`: environment-specific values deployed by Argo CD.

## Step-by-Step Implementation

1. Review the NetworkPolicy template:

   ```bash
   cd "$WORKSPACE"
   sed -n '1,160p' helm-charts/charts/sample-api/templates/networkpolicy.yaml
   ```

   Confirm the policy selects only `sample-api` pods, includes both `Ingress` and `Egress` policy types and allows only the intended ingress and egress paths.

2. Confirm whether the cluster CNI enforces Kubernetes NetworkPolicy:

   ```bash
   kubectl -n kube-system get pods -l k8s-app=aws-node
   kubectl -n kube-system get daemonset aws-node -o yaml | grep -i network
   ```

   A NetworkPolicy object can exist without being enforced if the CNI is not configured for policy enforcement. Treat that as a failed validation, not as a successful deny test.

3. Run `helm lint` and render the chart:

   ```bash
   helm lint helm-charts/charts/sample-api
   helm template sample-api helm-charts/charts/sample-api \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/dev/sample-api.yaml) \
     > /tmp/sample-api-networkpolicy.yaml
   grep -A30 '^kind: NetworkPolicy' /tmp/sample-api-networkpolicy.yaml
   ```

   Confirm the rendered policy uses the expected namespace selectors and ports. Rendering locally catches template mistakes before Argo CD deploys them.

4. Commit and push any chart or value changes if you changed them:

   ```bash
   git -C helm-charts status --short
   git -C platform-config status --short
   ```

   Commit in the repository that owns the changed file. Chart template changes belong in `helm-charts`; environment values belong in `platform-config`.

5. Refresh Argo CD and verify `sample-api` is synced:

   ```bash
   kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application sample-api -o wide
   ```

6. Confirm that the deployed NetworkPolicy and pods match the rendered intent:

   ```bash
   kubectl -n sample-api-dev get networkpolicy -o yaml
   kubectl -n sample-api-dev get pods -l app.kubernetes.io/name=sample-api -o wide
   ```

7. Run a positive connectivity test from the allowed namespace or expected source:

   ```bash
   kubectl -n sample-api-dev run allowed-client --rm -it --restart=Never \
      --image=curlimages/curl -- curl -fsS http://sample-api/
   ```

   This should succeed. If it fails, inspect the Service, endpoints and NetworkPolicy before running deny tests.

8. Run a negative test from an unintended namespace:

   ```bash
   kubectl create namespace network-denied-test
   kubectl -n network-denied-test run denied-client --rm -it --restart=Never \
      --image=curlimages/curl --max-time=5 -- curl -fsS http://sample-api.sample-api-dev.svc.cluster.local/
   ```

   This should fail or time out only if NetworkPolicy enforcement is enabled. If it succeeds, either the policy is too permissive or the CNI is not enforcing NetworkPolicy.

9. Validate DNS and required HTTPS egress from an application pod:

   ```bash
   SAMPLE_API_POD=$(kubectl -n sample-api-dev get pod -l app.kubernetes.io/name=sample-api -o jsonpath='{.items[0].metadata.name}')
   kubectl -n sample-api-dev exec "$SAMPLE_API_POD" -- nslookup kubernetes.default.svc.cluster.local
   ```

   DNS must keep working after egress policy is applied. If the application needs outbound HTTPS, validate that path with a non-sensitive endpoint used by the lab.

10. Delete the temporary namespace after validation:

   ```bash
   kubectl delete namespace network-denied-test
   ```

## Expected Results
The `sample-api` chart renders a NetworkPolicy and the deployed application still passes health checks while unintended traffic is denied.

## Validation
- The intended ingress source can reach the API.
- An unintended namespace cannot reach the API.
- DNS resolution still works.
- Only documented outbound destinations/ports work.
- Existing probes and monitoring traffic continue to function.
- Denials are reproducible and disappear when the policy is removed in a controlled test.
- If the installed AWS VPC CNI configuration does not have NetworkPolicy enforcement enabled, the manifest may exist while traffic remains unrestricted; that is a failed validation.

## Troubleshooting
Start with the rendered policy and namespace events:

```bash
kubectl -n sample-api-dev describe networkpolicy sample-api
kubectl -n sample-api-dev get pods,svc,endpoints -o wide
kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
```

If the deny test succeeds unexpectedly:

- Confirm the CNI enforces Kubernetes NetworkPolicy.
- Confirm the policy selects the sample-api pods.
- Confirm the source namespace does not match an allowed namespace selector.
- Confirm there is no additional policy allowing the traffic.

If the allowed test fails:

- Confirm the Service has endpoints.
- Confirm the allowed source matches the policy selectors.
- Confirm the policy port matches the pod container port, not only the Service port.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Delete only temporary test pods and namespaces created during validation. Keep the Git-managed NetworkPolicy in place.

## Next Steps
Continue with [Lab 15 - Multi-Environment Platform](./lab15-multi-environment-platform.md).
