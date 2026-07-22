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

## Outcome
Implement and validate High Availability and Resilience in the complete platform reference implementation.

## Prerequisites
Complete Lab 01 - Lab 16, configure AWS CLI, Terraform, kubectl, Helm and repository URLs.

## Repository Changes
Primary implementation: `sample-api probes, PDB, anti-affinity and topology spread`.

## Files to Review
Review the high-availability and resilience configuration files and update any environment-specific values before validation.

## Step-by-Step Implementation

1. Review the sample API chart templates for probes, PDB, anti-affinity and topology spread constraints.
2. Render the chart locally and confirm the HA settings are present:

   ```bash
   cd "$WORKSPACE"
   helm lint helm-charts/charts/sample-api
   helm template sample-api helm-charts/charts/sample-api --set rollout.enabled=false > /tmp/sample-api-ha.yaml
   grep -nE 'readinessProbe|livenessProbe|startupProbe|PodDisruptionBudget|topologySpreadConstraints|podAntiAffinity' /tmp/sample-api-ha.yaml
   ```

3. Commit and push any chart changes.
4. Let Argo CD reconcile `sample-api` from Git:

   ```bash
   kubectl -n argocd get application sample-api -o wide
   ```

5. Run controlled pod deletion and optional node-drain tests to measure recovery.

## Expected Results
The sample API has health probes, disruption protection and scheduling rules that keep it available during controlled failures.

## Validation
### high-availability and resilience verification

```bash
kubectl -n sample-api-dev get rollout,pod,pdb -o wide
kubectl -n sample-api-dev describe pdb sample-api
kubectl -n sample-api-dev get pods   -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,READY:.status.containerStatuses[0].ready
kubectl get nodes -L topology.kubernetes.io/zone
```

Controlled tests:

```bash
POD=$(kubectl -n sample-api-dev get pod -l app.kubernetes.io/name=sample-api -o jsonpath='{.items[0].metadata.name}')
kubectl -n sample-api-dev delete pod "$POD"
kubectl -n sample-api-dev get pods -w
```

Drain one worker only when the lab environment has enough spare capacity:

```bash
kubectl drain <test-node> --ignore-daemonsets --delete-emptydir-data
kubectl -n sample-api-dev get pods -w
kubectl uncordon <test-node>
```

Pass criteria:

- At least the documented number of replicas are available.
- Pods are spread across more than one node and, when capacity exists, more than one zone.
- Readiness, liveness and startup probes behave as intended.
- Deleting a pod causes automatic replacement without sustained service failure.
- PDB blocks voluntary disruption that would violate `minAvailable`.
- Graceful termination completes within the configured grace period.
- HPA and scheduling constraints do not conflict with the PDB or available capacity.

Run repeated requests during each test and record error rate and recovery time.

## Troubleshooting
Start with workload status, events and scheduling placement:

```bash
kubectl -n sample-api-dev describe pdb sample-api
kubectl -n sample-api-dev get pods -o wide
kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
kubectl get nodes -L topology.kubernetes.io/zone
```

## Commit and Push
Use a focused conventional commit such as `feat: complete lab 17`.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Uncordon any node drained during validation and remove temporary rendered files such as `/tmp/sample-api-ha.yaml`.

## Next Steps
Continue with [Lab 18 - Chaos Engineering](./lab18-chaos-engineering.md).
