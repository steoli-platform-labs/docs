# Lab 16 - Progressive Delivery

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Operations |
| **Lab** | 16 |
| **Difficulty** | Advanced |
| **Estimated Time** | 45-75 minutes |
| **Estimated Cost** | Free |
| **Primary Tools** | Helm, kubectl, Argo CD, Argo Rollouts |

## Introduction

This lab introduces progressive delivery for the sample application.

Progressive delivery makes releases safer by shifting traffic gradually and keeping image updates explicit, reviewable and traceable.

In a real GitOps platform, promoting from `1.0.0` to `1.0.1` would be a reviewed change to the environment's desired state in `platform-config`. This public lab series treats the reference repositories as read-only templates, so this lab demonstrates the same Argo Rollouts behavior with an isolated temporary Rollout instead of asking learners to push changes to shared repositories.

Concepts introduced in this lab include progressive delivery, Argo Rollouts, Rollouts, canary releases, ReplicaSets, image promotion and rollback. See the [Concepts Reference](../concepts/README.md) for how these concepts reduce release risk.

## Outcome
Validate progressive delivery for the sample API in the complete platform reference implementation.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 15 completed
- AWS CLI, Terraform, kubectl and Helm installed
- `sample-api:1.0.0` and `sample-api:1.0.1` published to GHCR

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

   printf '\n===== Chart rollout defaults =====\n'
   yq '.rollout' helm-charts/charts/sample-api/values.yaml

   printf '\n===== Argo Rollouts Application source =====\n'
   yq '.spec.source' platform-config/clusters/dev/argo-rollouts.yaml

   printf '\n===== sample-api-dev Helm values =====\n'
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

   This confirms the controller and current `sample-api` Rollout are healthy before you run the isolated demo. Record the current image tag and ReplicaSet names so you can compare the GitOps-managed workload with the temporary demo workload.

4. Create an isolated temporary rollout demo from the same chart:

   ```bash
   cd "$WORKSPACE"

   kubectl create namespace sample-api-rollout-demo --dry-run=client -o yaml | kubectl apply -f -

   helm template sample-api-rollout-demo helm-charts/charts/sample-api \
     --namespace sample-api-rollout-demo \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/dev/sample-api-dev.yaml) \
     --set image.tag=1.0.0 \
     --set environment=rollout-demo \
     --set replicaCount=2 \
     --set autoscaling.enabled=false \
     --set secret.enabled=false \
     > /tmp/sample-api-rollout-demo.yaml

   kubectl apply -f /tmp/sample-api-rollout-demo.yaml
   kubectl -n sample-api-rollout-demo get rollout,replicaset,pod
   ```

   The demo uses the same chart and Argo Rollouts controller as the GitOps-managed workload, but it is not managed by Argo CD. This keeps the reference repositories unchanged while still giving you a real rollout object to test.

5. Patch the temporary demo Rollout from `1.0.0` to `1.0.1` and watch the canary:

   ```bash
   kubectl -n sample-api-rollout-demo patch rollout sample-api-rollout-demo \
     --type='json' \
     -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"ghcr.io/steoli-platform-labs/sample-api:1.0.1"}]'

   kubectl -n sample-api-rollout-demo get rollout sample-api-rollout-demo -w
   ```

   The Rollout should create a new ReplicaSet and progress through the canary steps. Press `Ctrl-C` after you have observed the status change. If the image tag does not change, no meaningful progressive delivery event occurs.

6. Inspect the rollout result:

   ```bash
   kubectl -n sample-api-rollout-demo get rollout,replicaset,pod -o wide
   kubectl -n sample-api-rollout-demo describe rollout sample-api-rollout-demo
   ```

   The current Rollout status should show the new image tag and a healthy ReplicaSet. In a production GitOps flow, the same version change would be a reviewed Git change in `platform-config`; this lab uses a temporary resource so multiple learners can run the demo without pushing to shared reference repositories.

## Expected Results
Argo Rollouts is installed and the sample API is managed as a Rollout when progressive delivery is enabled.

## Validation
- The temporary demo Rollout starts on `1.0.0`.
- Argo Rollouts creates a new ReplicaSet.
- Canary traffic/replica weight progresses through the documented steps.
- Pause durations are observed.
- Readiness failures stop progression.
- Rollback is described as a Git revert or image-tag change back to the previous known-good version in a production GitOps flow.
- The stable service remains available during progression.
- Metrics-based analysis is present if the lab claims automated health-based promotion.
- The demo uses `1.0.0` and `1.0.1` release tags. An unchanged image tag does not provide traceable progressive delivery.

## Troubleshooting
Start with the Rollout object and controller status:

```bash
kubectl -n argocd describe application argo-rollouts
kubectl -n argocd describe application sample-api-dev
kubectl -n sample-api-dev describe rollout sample-api
kubectl -n sample-api-rollout-demo describe rollout sample-api-rollout-demo
kubectl -n argo-rollouts get pods -o wide
```

If no canary happens:

- Confirm the rendered chart creates a `Rollout`, not a `Deployment`.
- Confirm the temporary demo Rollout image changed from `1.0.0` to `1.0.1`.
- Confirm the Rollout controller is healthy.

If rollout pauses unexpectedly:

- Inspect `kubectl -n sample-api-dev describe rollout sample-api`.
- Check pod readiness and image pull errors.
- Confirm pause steps are part of the configured canary strategy.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Delete the temporary demo namespace before moving on. Keep Argo Rollouts installed for later resilience validation.

```bash
kubectl delete namespace sample-api-rollout-demo --ignore-not-found
rm -f /tmp/sample-api-rollout-demo.yaml
```

## Next Steps
Continue with [Lab 17 - High Availability and Resilience](./lab17-high-availability-and-resilience.md).
