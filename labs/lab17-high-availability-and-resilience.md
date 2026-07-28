# Lab 17 - High Availability and Resilience

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Operations |
| **Lab** | 17 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-60 minutes |
| **Estimated Cost** | Free |
| **Primary Tools** | Helm, kubectl, Argo CD |

## Introduction

This lab improves the sample application's availability and resilience configuration.

The lab validates probes, disruption handling and scheduling rules so the workload behaves predictably during node maintenance, pod restarts and normal cluster changes.

Concepts introduced in this lab include high availability, resilience, readiness probes, liveness probes, startup probes, PodDisruptionBudgets, anti-affinity and topology spread constraints. See the [Concepts Reference](../concepts/README.md) for why each setting matters.

## Outcome
Validate the sample API's availability and resilience controls in the complete platform reference implementation.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 16 completed
- AWS CLI, Terraform, kubectl and Helm installed
- Repository URLs configured

## Files to Review
Review these files before validation:

- `helm-charts/charts/sample-api/templates/rollout.yaml` and `deployment.yaml`: probes, resources and pod template settings.
- `helm-charts/charts/sample-api/templates/pdb.yaml`: disruption protection.
- `helm-charts/charts/sample-api/values.yaml`: replica count, autoscaling and resource defaults.
- `platform-config/clusters/dev/sample-api-dev.yaml`: dev-specific replica and autoscaling values.

## Step-by-Step Implementation

1. Review the currently configured replica and autoscaling values:

   ```bash
   cd "$WORKSPACE"
   yq '.replicaCount, .autoscaling' helm-charts/charts/sample-api/values.yaml
   yq '.spec.source.helm.values' platform-config/clusters/dev/sample-api-dev.yaml
   ```

   Confirm the dev environment keeps a small steady-state replica count while still allowing controlled maintenance. The chart uses a `PodDisruptionBudget` with `maxUnavailable: 1`, which protects the service from losing both replicas during voluntary disruption without requiring an extra baseline pod.

2. Review the sample API chart templates for probes and disruption protection:

   ```bash
   sed -n '1,200p' helm-charts/charts/sample-api/templates/rollout.yaml
   sed -n '1,120p' helm-charts/charts/sample-api/templates/deployment.yaml
   sed -n '1,120p' helm-charts/charts/sample-api/templates/pdb.yaml
   ```

   Confirm readiness probes protect traffic, liveness probes restart broken containers and the PDB protects against voluntary disruption.

3. Render the chart locally and confirm the HA settings are present:

   ```bash
   printf '\n===== sample-api Helm lint =====\n'
   helm lint helm-charts/charts/sample-api
   printf '\n===== Render sample-api chart =====\n'
   helm template sample-api helm-charts/charts/sample-api \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/dev/sample-api-dev.yaml) \
     --set rollout.enabled=false \
     > /tmp/sample-api-ha.yaml
   printf '\n===== Rendered HA settings =====\n'
   grep -nE 'readinessProbe|livenessProbe|startupProbe|PodDisruptionBudget|topologySpreadConstraints|podAntiAffinity' /tmp/sample-api-ha.yaml
   ```

   If `topologySpreadConstraints` or `podAntiAffinity` are not present, either the chart does not implement them yet or the values do not enable them. Do not claim that the lab validates a setting that is not rendered.

4. Refresh Argo CD and confirm `sample-api` is healthy:

   ```bash
   printf '\n===== Refresh dev root =====\n'
   kubectl -n argocd annotate application platform-root-dev argocd.argoproj.io/refresh=hard --overwrite
   printf '\n===== sample-api-dev Application =====\n'
   kubectl -n argocd get application sample-api-dev -o wide
   ```

5. Inspect the deployed workload before testing recovery:

   ```bash
   printf '\n===== sample-api workload resources =====\n'
   kubectl -n sample-api-dev get rollout,pod,pdb -o wide
   printf '\n===== sample-api PDB details =====\n'
   kubectl -n sample-api-dev describe pdb sample-api
   printf '\n===== sample-api pod placement =====\n'
   kubectl -n sample-api-dev get pods \
     -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,READY:.status.containerStatuses[0].ready
   printf '\n===== Node zones =====\n'
   kubectl get nodes -L topology.kubernetes.io/zone
   ```

   Confirm pods are ready and note which nodes they run on. If all replicas are on one node, pod deletion can still be tested, but node failure and zone-spread claims cannot be fully validated.

6. Run continuous traffic while testing recovery:

   ```bash
   kubectl -n sample-api-dev port-forward svc/sample-api 8080:80
   ```

   In another terminal:

   ```bash
   while true; do date -u; curl -fsS http://localhost:8080/health || echo "request failed"; sleep 2; done
   ```

   This gives you a simple signal for whether the service remains available during disruption.

7. Run controlled pod deletion and measure recovery:

   ```bash
   POD=$(kubectl -n sample-api-dev get pod -l app.kubernetes.io/name=sample-api -o jsonpath='{.items[0].metadata.name}')
   printf '\n===== Delete pod %s =====\n' "$POD"
   kubectl -n sample-api-dev delete pod "$POD"
   printf '\n===== Watch replacement pods =====\n'
   kubectl -n sample-api-dev get pods -w
   ```

   Expected behavior: Kubernetes creates a replacement pod, the Service keeps at least one ready endpoint and the repeated health requests do not fail for a sustained period.

8. Drain one worker only when the lab environment has enough spare capacity:

   ```bash
   SAMPLE_POD=$(kubectl -n sample-api-dev get pod -l app.kubernetes.io/name=sample-api -o jsonpath='{.items[0].metadata.name}')
   TEST_NODE=$(kubectl -n sample-api-dev get pod "$SAMPLE_POD" -o jsonpath='{.spec.nodeName}')

   printf '\n===== Drain node %s =====\n' "$TEST_NODE"
   kubectl drain "$TEST_NODE" --ignore-daemonsets --delete-emptydir-data
   printf '\n===== Wait for sample-api readiness =====\n'
   kubectl -n sample-api-dev wait --for=condition=Ready pod \
     -l app.kubernetes.io/name=sample-api \
     --timeout=5m
   printf '\n===== sample-api pods after drain =====\n'
   kubectl -n sample-api-dev get pods -o wide
   printf '\n===== Uncordon node %s =====\n' "$TEST_NODE"
   kubectl uncordon "$TEST_NODE"
   ```

   Run repeated requests during each test and record error rate and recovery time.

## Expected Results
The sample API has health probes, disruption protection and scheduling rules that keep it available during controlled failures.

## Validation
- At least the documented number of replicas are available.
- Pods are spread across more than one node and, when capacity exists, more than one zone.
- Readiness, liveness and startup probes behave as intended.
- Deleting a pod causes automatic replacement without sustained service failure.
- PDB allows one voluntary disruption at a time and blocks disruption beyond `maxUnavailable`.
- Graceful termination completes within the configured grace period.
- HPA and scheduling constraints do not conflict with the PDB or available capacity.

## Troubleshooting
Start with workload status, events and scheduling placement:

```bash
printf '\n===== sample-api PDB details =====\n'
kubectl -n sample-api-dev describe pdb sample-api
printf '\n===== sample-api pods =====\n'
kubectl -n sample-api-dev get pods -o wide
printf '\n===== sample-api events =====\n'
kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
printf '\n===== Node zones =====\n'
kubectl get nodes -L topology.kubernetes.io/zone
```

If the PDB blocks a drain:

- Confirm the current replica count and ready pod count.
- Confirm `maxUnavailable` still allows the intended maintenance action.
- This may be correct behavior; a PDB should block voluntary disruption that would reduce availability too far.

If all pods schedule on one node:

- Confirm anti-affinity or topology spread constraints are actually rendered.
- Confirm the cluster has enough nodes and zones to satisfy the constraints.
- Confirm Karpenter or existing node capacity can place additional pods.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Uncordon any node drained during validation and remove temporary rendered files such as `/tmp/sample-api-ha.yaml`.

## Next Steps
Continue with [Lab 18 - Chaos Engineering](./lab18-chaos-engineering.md).
