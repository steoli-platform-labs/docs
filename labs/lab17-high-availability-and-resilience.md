# Lab 17 - High Availability and Resilience

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Operations |
| **Lab** | 17 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-60 minutes |
| **Estimated Cost** | Free |
| **Terraform** | No |
| **Kubernetes** | Yes |
| **GitOps** | Yes |

## Introduction

This lab improves the sample application's availability and resilience configuration.

The lab validates probes, disruption handling and scheduling rules so the workload behaves predictably during node maintenance, pod restarts and normal cluster changes.

Concepts introduced in this lab include high availability, resilience, readiness probes, liveness probes, startup probes, PodDisruptionBudgets, anti-affinity and topology spread constraints. See the [Concepts Reference](../concepts/README.md) for why each setting matters.

## Outcome
Implement and validate High Availability and Resilience in the complete platform reference implementation.

## Prerequisites
Complete Lab 01 - Lab 16. AWS CLI, Terraform, kubectl and Helm must be installed, with repository URLs configured.

## Repository Changes
Primary implementation: sample API probes, PodDisruptionBudget, replica settings and scheduling constraints in the Helm chart and environment values.

## Files to Review
Review these files before validation:

- `helm-charts/charts/sample-api/templates/rollout.yaml` and `deployment.yaml`: probes, resources and pod template settings.
- `helm-charts/charts/sample-api/templates/pdb.yaml`: disruption protection.
- `helm-charts/charts/sample-api/values.yaml`: replica count, autoscaling and resource defaults.
- `platform-config/clusters/dev/sample-api.yaml`: dev-specific replica and autoscaling values.

## Step-by-Step Implementation

1. Review the currently configured replica and autoscaling values:

   ```bash
   cd "$WORKSPACE"
   yq '.replicaCount, .autoscaling' helm-charts/charts/sample-api/values.yaml
   yq '.spec.source.helm.values' platform-config/clusters/dev/sample-api.yaml
   ```

   Confirm the dev environment has enough replicas for disruption tests. A `PodDisruptionBudget` with `minAvailable: 2` requires at least two healthy pods before voluntary disruptions can succeed.

2. Review the sample API chart templates for probes and disruption protection:

   ```bash
   sed -n '1,200p' helm-charts/charts/sample-api/templates/rollout.yaml
   sed -n '1,120p' helm-charts/charts/sample-api/templates/deployment.yaml
   sed -n '1,120p' helm-charts/charts/sample-api/templates/pdb.yaml
   ```

   Confirm readiness probes protect traffic, liveness probes restart broken containers and the PDB protects against voluntary disruption.

3. Render the chart locally and confirm the HA settings are present:

   ```bash
   helm lint helm-charts/charts/sample-api
   helm template sample-api helm-charts/charts/sample-api \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/dev/sample-api.yaml) \
     --set rollout.enabled=false \
     > /tmp/sample-api-ha.yaml
   grep -nE 'readinessProbe|livenessProbe|startupProbe|PodDisruptionBudget|topologySpreadConstraints|podAntiAffinity' /tmp/sample-api-ha.yaml
   ```

   If `topologySpreadConstraints` or `podAntiAffinity` are not present, either the chart does not implement them yet or the values do not enable them. Do not claim that the lab validates a setting that is not rendered.

4. Commit and push any chart or value changes if you changed them:

   ```bash
   git -C helm-charts status --short
   git -C platform-config status --short
   ```

   Commit chart changes in `helm-charts` and environment value changes in `platform-config`.

5. Refresh Argo CD and confirm `sample-api` is healthy:

   ```bash
   kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application sample-api -o wide
   ```

6. Inspect the deployed workload before testing recovery:

   ```bash
   kubectl -n sample-api-dev get rollout,pod,pdb -o wide
   kubectl -n sample-api-dev describe pdb sample-api
   kubectl -n sample-api-dev get pods \
     -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,READY:.status.containerStatuses[0].ready
   kubectl get nodes -L topology.kubernetes.io/zone
   ```

   Confirm pods are ready and note which nodes they run on. If all replicas are on one node, pod deletion can still be tested, but node failure and zone-spread claims cannot be fully validated.

7. Run continuous traffic while testing recovery:

   ```bash
   kubectl -n sample-api-dev port-forward svc/sample-api 8080:80
   ```

   In another terminal:

   ```bash
   while true; do date -u; curl -fsS http://localhost:8080/health || echo "request failed"; sleep 2; done
   ```

   This gives you a simple signal for whether the service remains available during disruption.

8. Run controlled pod deletion and measure recovery:

   ```bash
   POD=$(kubectl -n sample-api-dev get pod -l app.kubernetes.io/name=sample-api -o jsonpath='{.items[0].metadata.name}')
   kubectl -n sample-api-dev delete pod "$POD"
   kubectl -n sample-api-dev get pods -w
   ```

   Expected behavior: Kubernetes creates a replacement pod, the Service keeps at least one ready endpoint and the repeated health requests do not fail for a sustained period.

9. Drain one worker only when the lab environment has enough spare capacity:

   ```bash
   kubectl drain <test-node> --ignore-daemonsets --delete-emptydir-data
   kubectl -n sample-api-dev get pods -w
   kubectl uncordon <test-node>
   ```

   Run repeated requests during each test and record error rate and recovery time.

## Expected Results
The sample API has health probes, disruption protection and scheduling rules that keep it available during controlled failures.

## Validation
- At least the documented number of replicas are available.
- Pods are spread across more than one node and, when capacity exists, more than one zone.
- Readiness, liveness and startup probes behave as intended.
- Deleting a pod causes automatic replacement without sustained service failure.
- PDB blocks voluntary disruption that would violate `minAvailable`.
- Graceful termination completes within the configured grace period.
- HPA and scheduling constraints do not conflict with the PDB or available capacity.

## Troubleshooting
Start with workload status, events and scheduling placement:

```bash
kubectl -n sample-api-dev describe pdb sample-api
kubectl -n sample-api-dev get pods -o wide
kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
kubectl get nodes -L topology.kubernetes.io/zone
```

If the PDB blocks a drain:

- Confirm the current replica count and ready pod count.
- Confirm `minAvailable` is not higher than the environment can satisfy.
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
