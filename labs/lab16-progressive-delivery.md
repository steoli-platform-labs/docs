# Lab 16 - Progressive Delivery

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Operations |
| **Lab** | 16 |
| **Difficulty** | Advanced |
| **Estimated Time** | 45-75 minutes |
| **Estimated Cost** | Free |
| **Terraform** | No |
| **Kubernetes** | Yes |
| **GitOps** | Yes |

## Outcome
Implement and validate Progressive Delivery in the complete platform reference implementation.

## Before You Begin
Complete Lab 01 - Lab 15, configure AWS CLI, Terraform, kubectl, Helm and repository URLs.

## Repository Changes
Primary implementation: `sample-api Rollout chart template`.

## Files to Review
Review the progressive delivery desired-state files and update any environment-specific values before validation.

## Step-by-Step Implementation
1. Review the `sample-api` Rollout template and the `rollout.enabled` chart value.
2. Review `platform-config/clusters/dev/argo-rollouts.yaml` and `sample-api.yaml`.
3. Commit and push any chart or GitOps value changes.
4. Let Argo CD reconcile Argo Rollouts and the sample API from Git.
5. Change the sample API image tag through Git and observe the canary rollout.

## Commands
```bash
cd "$WORKSPACE"
helm lint helm-charts/charts/sample-api
helm template sample-api helm-charts/charts/sample-api --set rollout.enabled=true | grep -A30 '^kind: Rollout'
kubectl -n argocd get application argo-rollouts sample-api -o wide
```

## Expected Results
Argo Rollouts is installed and the sample API is managed as a Rollout when progressive delivery is enabled.

## Validation
### Progressive delivery verification

```bash
kubectl -n argocd get application argo-rollouts sample-api -o wide
kubectl -n argo-rollouts get pods
kubectl -n sample-api-dev get rollout,replicaset,pod
kubectl -n sample-api-dev describe rollout sample-api
kubectl argo rollouts get rollout sample-api -n sample-api-dev --watch
```

Change the image tag in Git to a known new immutable tag, merge it and observe the rollout steps.

Pass criteria:

- Argo CD detects and syncs the Git change.
- Argo Rollouts creates a new ReplicaSet.
- Canary traffic/replica weight progresses through the documented steps.
- Pause durations are observed.
- Readiness failures stop progression.
- A deliberately bad image can be aborted and rolled back to the stable ReplicaSet.
- The stable service remains available during progression.
- Metrics-based analysis is present if the lab claims automated health-based promotion.

Also verify the CI-to-GitOps handoff: publishing a GHCR image must result in an explicit, reviewable Git update. A chart fixed at `latest` or an unchanged tag does not provide traceable progressive delivery.

## Troubleshooting
Start with the Rollout object and controller status:

```bash
kubectl -n argocd describe application argo-rollouts
kubectl -n argocd describe application sample-api
kubectl -n sample-api-dev describe rollout sample-api
kubectl -n argo-rollouts get pods -o wide
```

## Commit and Push
Use a focused conventional commit such as `feat: complete lab 16`.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Abort or complete any test rollout before moving on. Keep Argo Rollouts installed for later resilience validation.

## Next Steps
Continue with [Lab 17 - High Availability and Resilience](./lab17-high-availability-and-resilience.md).
