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

## Introduction

This lab introduces progressive delivery for the sample application.

Progressive delivery makes releases safer by shifting traffic gradually and keeping image updates explicit, reviewable and traceable through GitOps.

Concepts introduced in this lab include progressive delivery, Argo Rollouts, Rollouts, canary releases, ReplicaSets, image promotion and rollback. See the [Concepts Reference](../concepts/README.md) for how these concepts reduce release risk.

## Outcome
Implement and validate Progressive Delivery in the complete platform reference implementation.

## Prerequisites
Complete Lab 01 - Lab 15. AWS CLI, Terraform, kubectl and Helm must be installed, with repository URLs configured.

## Repository Changes
Primary implementation: the sample API Rollout chart template, Argo Rollouts controller Application and environment-specific image values.

## Files to Review
Review these files before validation:

- `helm-charts/charts/sample-api/templates/rollout.yaml`: Argo Rollouts `Rollout` resource.
- `helm-charts/charts/sample-api/values.yaml`: rollout and image defaults.
- `platform-config/clusters/dev/argo-rollouts.yaml`: Argo Rollouts controller Application.
- `platform-config/clusters/dev/sample-api.yaml`: deployed sample API image values.

## Step-by-Step Implementation

1. Review the Rollout template and rollout values:

   ```bash
   cd "$WORKSPACE"
   yq '.rollout' helm-charts/charts/sample-api/values.yaml
   sed -n '1,180p' helm-charts/charts/sample-api/templates/rollout.yaml
   ```

   Confirm the Rollout has a selector, pod template, readiness probes and canary steps. Progressive delivery only works if new ReplicaSets can become ready and the controller can manage them.

2. Review the controller and application GitOps state:

   ```bash
   yq '.spec.source' platform-config/clusters/dev/argo-rollouts.yaml
   yq '.spec.source.helm.values' platform-config/clusters/dev/sample-api.yaml
   ```

   Confirm Argo Rollouts is installed before relying on `Rollout` resources, and confirm `sample-api` uses an image tag that can be changed through Git.

3. Render the chart locally with Rollout enabled before committing changes:

   ```bash
   helm lint helm-charts/charts/sample-api
   helm template sample-api helm-charts/charts/sample-api \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/dev/sample-api.yaml) \
     --set rollout.enabled=true \
     > /tmp/sample-api-rollout.yaml
   grep -A60 '^kind: Rollout' /tmp/sample-api-rollout.yaml
   ```

   Confirm the rendered output contains a `Rollout` and not only a `Deployment`.

4. Commit and push any chart or GitOps value changes if you made any:

   ```bash
   git -C helm-charts status --short
   git -C platform-config status --short
   ```

   Chart template changes belong in `helm-charts`. Image tag or environment-specific values belong in `platform-config`.

5. Refresh Argo CD and confirm Argo Rollouts and sample API are healthy:

   ```bash
   kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application argo-rollouts sample-api -o wide
   kubectl -n argo-rollouts get pods
   kubectl -n sample-api-dev get rollout sample-api
   ```

6. Observe the current stable state before changing the image:

   ```bash
   kubectl -n sample-api-dev get rollout,replicaset,pod
   kubectl -n sample-api-dev describe rollout sample-api
   kubectl argo rollouts get rollout sample-api -n sample-api-dev
   ```

   Record the stable ReplicaSet and current image tag. You need a baseline before validating canary behavior.

7. Change the sample API image tag through Git and observe the canary rollout:

   ```bash
   yq '.spec.source.helm.values' platform-config/clusters/dev/sample-api.yaml
   ```

   Change the image tag to a known new immutable tag, commit and push the GitOps change, then watch the rollout:

   ```bash
   kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application sample-api -o wide
   kubectl argo rollouts get rollout sample-api -n sample-api-dev --watch
   ```

   The Rollout should create a new ReplicaSet and progress through the canary steps. If the image tag does not change, no meaningful progressive delivery event occurs.

8. Test abort and rollback with a deliberately bad image only in the dev environment:

   ```bash
   kubectl argo rollouts abort sample-api -n sample-api-dev
   kubectl argo rollouts undo sample-api -n sample-api-dev
   kubectl argo rollouts get rollout sample-api -n sample-api-dev
   ```

   Use this only for controlled validation. Return Git to the intended image tag after the test so Argo CD does not continuously fight the live rollback.

## Expected Results
Argo Rollouts is installed and the sample API is managed as a Rollout when progressive delivery is enabled.

## Validation
- Argo CD detects and syncs the Git change.
- Argo Rollouts creates a new ReplicaSet.
- Canary traffic/replica weight progresses through the documented steps.
- Pause durations are observed.
- Readiness failures stop progression.
- A deliberately bad image can be aborted and rolled back to the stable ReplicaSet.
- The stable service remains available during progression.
- Metrics-based analysis is present if the lab claims automated health-based promotion.
- The CI-to-GitOps handoff is explicit: publishing a GHCR image must result in a reviewable Git update. A chart fixed at `latest` or an unchanged tag does not provide traceable progressive delivery.

## Troubleshooting
Start with the Rollout object and controller status:

```bash
kubectl -n argocd describe application argo-rollouts
kubectl -n argocd describe application sample-api
kubectl -n sample-api-dev describe rollout sample-api
kubectl -n argo-rollouts get pods -o wide
```

If no canary happens:

- Confirm the rendered chart creates a `Rollout`, not a `Deployment`.
- Confirm the image tag changed in Git.
- Confirm Argo CD synced the changed values.
- Confirm the Rollout controller is healthy.

If rollout pauses unexpectedly:

- Inspect `kubectl argo rollouts get rollout sample-api -n sample-api-dev`.
- Check pod readiness and image pull errors.
- Confirm pause steps are part of the configured canary strategy.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Abort or complete any test rollout before moving on. Keep Argo Rollouts installed for later resilience validation.

## Next Steps
Continue with [Lab 17 - High Availability and Resilience](./lab17-high-availability-and-resilience.md).
