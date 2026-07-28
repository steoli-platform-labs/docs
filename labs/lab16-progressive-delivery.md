# Lab 16 - Progressive Delivery

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Operations |
| **Lab** | 16 |
| **Difficulty** | Advanced |
| **Estimated Time** | 45-75 minutes |
| **Estimated Cost** | Free |
| **Primary Tools** | Git, Helm, kubectl, Argo CD, Argo Rollouts |

## Introduction

This lab introduces progressive delivery for the sample application.

Progressive delivery makes releases safer by shifting traffic gradually and keeping image updates explicit, reviewable and traceable through GitOps.

Concepts introduced in this lab include progressive delivery, Argo Rollouts, Rollouts, canary releases, ReplicaSets, image promotion and rollback. See the [Concepts Reference](../concepts/README.md) for how these concepts reduce release risk.

## Outcome
Validate progressive delivery for the sample API in the complete platform reference implementation.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 15 completed
- AWS CLI, Terraform, kubectl and Helm installed
- Repository URLs configured

## Files to Review
Review these files before validation:

- `helm-charts/charts/sample-api/templates/rollout.yaml`: Argo Rollouts `Rollout` resource.
- `helm-charts/charts/sample-api/values.yaml`: rollout and image defaults.
- `platform-config/clusters/dev/argo-rollouts.yaml`: Argo Rollouts controller Application.
- `platform-config/clusters/dev/sample-api-dev.yaml`: deployed dev sample API image values.

## Step-by-Step Implementation

1. Review the rollout configuration that is already in Git:

   ```bash
   cd "$WORKSPACE"
   yq '.rollout' helm-charts/charts/sample-api/values.yaml
   yq '.spec.source' platform-config/clusters/dev/argo-rollouts.yaml
   yq '.spec.source.helm.values' platform-config/clusters/dev/sample-api-dev.yaml
   ```

   Confirm the chart has rollout support, Argo Rollouts is managed by Argo CD and `sample-api-dev` uses the release tag published in Lab 06. Progressive delivery should move from one readable, immutable release tag to another, such as `1.0.0` to `1.0.1`.

   Compare the configured chart version with the latest available chart version:

   ```bash
   echo "Configured Argo Rollouts chart: $(yq -r '.spec.source.targetRevision' platform-config/clusters/dev/argo-rollouts.yaml)"
   helm show chart argo-rollouts --repo https://argoproj.github.io/argo-helm | yq '.version'
   ```

   The pinned version in `platform-config/clusters/dev/argo-rollouts.yaml` is the version tested by this lab. Newer chart versions may exist by the time you run the lab. Do not change the pinned version just because a newer version is available; Helm charts can change required values between releases.

2. Render the chart locally with Rollout enabled:

   ```bash
   helm lint helm-charts/charts/sample-api
   helm template sample-api helm-charts/charts/sample-api \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/dev/sample-api-dev.yaml) \
     --set rollout.enabled=true \
     > /tmp/sample-api-rollout.yaml
   grep -A60 '^kind: Rollout' /tmp/sample-api-rollout.yaml
   ```

   Confirm the rendered output contains a `Rollout` and not only a `Deployment`. Rendering locally catches chart mistakes before you change the deployed image tag.

3. Confirm the current deployed rollout state:

   ```bash
   kubectl -n argocd annotate application platform-root-dev argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application argo-rollouts sample-api-dev -o wide
   kubectl -n argo-rollouts get pods
   kubectl -n sample-api-dev get rollout sample-api
   kubectl -n sample-api-dev get rollout,replicaset,pod
   kubectl -n sample-api-dev describe rollout sample-api
   ```

   This confirms the controller and current `sample-api` Rollout are healthy before you make the GitOps image change. Record the current image tag and ReplicaSet names so you can recognize the new ReplicaSet during the rollout.

4. Change the sample API image tag through Git and observe the canary rollout:

   ```bash
   cd "$WORKSPACE/platform-config"
   yq '.spec.source.helm.values' clusters/dev/sample-api-dev.yaml

   printf 'New image tag: '
   read -r NEW_IMAGE_TAG
   export NEW_IMAGE_TAG
   yq -i '.spec.source.helm.values = ((.spec.source.helm.values | from_yaml | .image.tag = strenv(NEW_IMAGE_TAG)) | to_yaml)' clusters/dev/sample-api-dev.yaml

   git status --short
   git diff -- clusters/dev/sample-api-dev.yaml
   ```

   Enter a newer immutable release tag, such as `1.0.1`, published by the `sample-api` CI workflow from a Git tag like `v1.0.1`. If the diff is correct, commit and push the GitOps change, then watch the rollout:

   ```bash
   git add clusters/dev/sample-api-dev.yaml
   git commit -m "chore: update sample api image"
   git push

   kubectl -n argocd annotate application platform-root-dev argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application sample-api-dev -o wide
   kubectl -n sample-api-dev get rollout sample-api -w
   ```

   The Rollout should create a new ReplicaSet and progress through the canary steps. Press `Ctrl-C` after you have observed the status change. If the image tag does not change, no meaningful progressive delivery event occurs.

5. Inspect the rollout result:

   ```bash
   kubectl -n sample-api-dev get rollout,replicaset,pod -o wide
   kubectl -n sample-api-dev describe rollout sample-api
   ```

   The current Rollout status should show the new image tag and a healthy ReplicaSet. Rollback in this GitOps model is another reviewed Git change that restores the previous known-good image tag, followed by an Argo CD refresh.

## Expected Results
Argo Rollouts is installed and the sample API is managed as a Rollout when progressive delivery is enabled.

## Validation
- Argo CD detects and syncs the Git change.
- Argo Rollouts creates a new ReplicaSet.
- Canary traffic/replica weight progresses through the documented steps.
- Pause durations are observed.
- Readiness failures stop progression.
- Rollback is described as a Git revert or image-tag change back to the previous known-good version.
- The stable service remains available during progression.
- Metrics-based analysis is present if the lab claims automated health-based promotion.
- The CI-to-GitOps handoff is explicit: publishing a GHCR image must result in a reviewable Git update. An unchanged image tag does not provide traceable progressive delivery.

## Troubleshooting
Start with the Rollout object and controller status:

```bash
kubectl -n argocd describe application argo-rollouts
kubectl -n argocd describe application sample-api-dev
kubectl -n sample-api-dev describe rollout sample-api
kubectl -n argo-rollouts get pods -o wide
```

If no canary happens:

- Confirm the rendered chart creates a `Rollout`, not a `Deployment`.
- Confirm the image tag changed in Git.
- Confirm Argo CD synced the changed values.
- Confirm the Rollout controller is healthy.

If rollout pauses unexpectedly:

- Inspect `kubectl -n sample-api-dev describe rollout sample-api`.
- Check pod readiness and image pull errors.
- Confirm pause steps are part of the configured canary strategy.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Complete or roll back any test image change through Git before moving on. Keep Argo Rollouts installed for later resilience validation.

## Next Steps
Continue with [Lab 17 - High Availability and Resilience](./lab17-high-availability-and-resilience.md).
