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

In a real GitOps platform, promoting from one release image tag to another would be a reviewed change to the environment's desired state in `platform-config`. This public lab series treats the reference repositories as read-only templates, so this lab demonstrates the same Argo Rollouts behavior with an isolated temporary Rollout instead of asking learners to push changes to shared repositories.

Concepts introduced in this lab include progressive delivery, Argo Rollouts, Rollouts, canary releases, ReplicaSets, image promotion and rollback. See the [Concepts Reference](../concepts/README.md) for how these concepts reduce release risk.

## Outcome
Validate progressive delivery for the sample API in the complete platform reference implementation.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 15 completed
- AWS CLI, Terraform, kubectl and Helm installed
- `sample-api:1.0.2` and `sample-api:1.0.3` published to GHCR

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

   Confirm the chart has rollout support, Argo Rollouts is managed by Argo CD and `sample-api-dev` uses the release tag published in Lab 06. Progressive delivery should move from one readable, immutable release tag to another, such as `1.0.2` to `1.0.3`.

   Compare the configured chart version with the latest available chart version:

   ```bash
   printf '\n===== Configured Argo Rollouts chart =====\n'
   yq -r '.spec.source.targetRevision' platform-config/clusters/dev/argo-rollouts.yaml
   printf '\n===== Latest available Argo Rollouts chart =====\n'
   helm show chart argo-rollouts --repo https://argoproj.github.io/argo-helm | yq '.version'
   ```

   The pinned version in `platform-config/clusters/dev/argo-rollouts.yaml` is the version tested by this lab. Newer chart versions may exist by the time you run the lab. Do not change the pinned version just because a newer version is available; Helm charts can change required values between releases.

2. Render the chart locally with Rollout enabled:

   ```bash
   printf '\n===== Helm chart lint =====\n'
   helm lint helm-charts/charts/sample-api

   printf '\n===== Render sample-api Rollout =====\n'
   helm template sample-api helm-charts/charts/sample-api \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/dev/sample-api-dev.yaml) \
     --set rollout.enabled=true \
     > /tmp/sample-api-rollout.yaml

   printf '\n===== Rendered Rollout manifest =====\n'
   grep -A60 '^kind: Rollout' /tmp/sample-api-rollout.yaml
   ```

   Confirm the rendered output contains a `Rollout` and not only a `Deployment`. Rendering locally catches chart mistakes before you change the deployed image tag.

3. Confirm the current deployed rollout state:

   ```bash
   printf '\n===== Refresh dev root =====\n'
   kubectl -n argocd annotate application platform-root-dev argocd.argoproj.io/refresh=hard --overwrite

   printf '\n===== Argo CD Applications =====\n'
   kubectl -n argocd get application argo-rollouts sample-api-dev -o wide

   printf '\n===== Argo Rollouts controller pods =====\n'
   kubectl -n argo-rollouts get pods

   printf '\n===== sample-api Rollout summary =====\n'
   kubectl -n sample-api-dev get rollout sample-api

   printf '\n===== sample-api workload resources =====\n'
   kubectl -n sample-api-dev get rollout,replicaset,pod

   printf '\n===== sample-api Rollout details =====\n'
   kubectl -n sample-api-dev describe rollout sample-api
   ```

   This confirms the controller and current `sample-api` Rollout are healthy before you run the isolated demo. Record the current image tag and ReplicaSet names so you can compare the GitOps-managed workload with the temporary demo workload.

4. Create an isolated temporary rollout demo from the same chart:

   ```bash
   cd "$WORKSPACE"

   printf '\n===== Create demo namespace =====\n'
   kubectl create namespace sample-api-rollout-demo --dry-run=client -o yaml | kubectl apply -f -

   printf '\n===== Render demo Rollout =====\n'
   helm template sample-api-rollout-demo helm-charts/charts/sample-api \
     --namespace sample-api-rollout-demo \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/dev/sample-api-dev.yaml) \
     --set image.tag=1.0.2 \
     --set environment=rollout-demo \
     --set replicaCount=2 \
     --set autoscaling.enabled=false \
     --set secret.enabled=false \
     > /tmp/sample-api-rollout-demo.yaml

   printf '\n===== Apply demo Rollout =====\n'
   kubectl -n sample-api-rollout-demo apply -f /tmp/sample-api-rollout-demo.yaml

   printf '\n===== Demo rollout resources =====\n'
   kubectl -n sample-api-rollout-demo get rollout,replicaset,pod

   printf '\n===== Demo image before rollout =====\n'
   kubectl -n sample-api-rollout-demo get rollout sample-api-rollout-demo \
     -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

   printf '\n===== Demo application version before rollout =====\n'
   kubectl -n sample-api-rollout-demo port-forward svc/sample-api-rollout-demo 8080:80 >/tmp/sample-api-rollout-demo-port-forward.log 2>&1 &
   PF_PID=$!
   sleep 2
   curl -fsS http://localhost:8080/version | python3 -m json.tool
   kill "$PF_PID"
   ```

   The demo uses the same chart and Argo Rollouts controller as the GitOps-managed workload, but it is not managed by Argo CD. This keeps the reference repositories unchanged while still giving you a real rollout object to test.

   The `-n sample-api-rollout-demo` flag on `kubectl apply` is required because these chart templates do not set `metadata.namespace` in every rendered manifest. `helm template --namespace` sets the Helm release namespace, but it does not automatically add `metadata.namespace` to templates that omit it.

   The image check should print `ghcr.io/steoli-platform-labs/sample-api:1.0.2`, and the `/version` endpoint should return `{"version":"1.0.2"}`. The chart passes the image tag to the application as `APP_VERSION`, so the HTTP response shows the application version that the running pod received at deploy time.

5. Patch the temporary demo Rollout from `1.0.2` to `1.0.3` and watch the canary:

   ```bash
   printf '\n===== Patch demo Rollout to 1.0.3 =====\n'
   kubectl -n sample-api-rollout-demo patch rollout sample-api-rollout-demo \
     --type='json' \
     -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"ghcr.io/steoli-platform-labs/sample-api:1.0.3"},{"op":"replace","path":"/spec/template/spec/containers/0/env/1/value","value":"1.0.3"}]'

   printf '\n===== Watch demo Rollout =====\n'
   kubectl -n sample-api-rollout-demo get rollout sample-api-rollout-demo -w
   ```

   The Rollout should create a new ReplicaSet and progress through the canary steps. Press `Ctrl-C` after you have observed the status change. If the image tag and `APP_VERSION` value do not change together, the pod image and application-reported version can drift.

6. Inspect the rollout result:

   ```bash
   printf '\n===== Demo workload resources =====\n'
   kubectl -n sample-api-rollout-demo get rollout,replicaset,pod -o wide

   printf '\n===== Wait for demo Rollout to become healthy =====\n'
   kubectl -n sample-api-rollout-demo wait --for=jsonpath='{.status.phase}'=Healthy rollout/sample-api-rollout-demo --timeout=5m

   printf '\n===== Demo image after rollout =====\n'
   kubectl -n sample-api-rollout-demo get rollout sample-api-rollout-demo \
     -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

   printf '\n===== Running pod images =====\n'
   kubectl -n sample-api-rollout-demo get pods \
     -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,IMAGE:.spec.containers[0].image

   printf '\n===== Demo application version after rollout =====\n'
   kubectl -n sample-api-rollout-demo port-forward svc/sample-api-rollout-demo 8080:80 >/tmp/sample-api-rollout-demo-port-forward.log 2>&1 &
   PF_PID=$!
   sleep 2
   curl -fsS http://localhost:8080/version | python3 -m json.tool
   kill "$PF_PID"

   printf '\n===== Demo Rollout details =====\n'
   kubectl -n sample-api-rollout-demo describe rollout sample-api-rollout-demo
   ```

   The current Rollout status and pod image list should show `ghcr.io/steoli-platform-labs/sample-api:1.0.3`, and the `/version` endpoint should return `{"version":"1.0.3"}`. In a production GitOps flow, the same version change would be a reviewed Git change in `platform-config`; this lab uses a temporary resource so multiple learners can run the demo without pushing to shared reference repositories.

## Expected Results
Argo Rollouts is installed and the sample API is managed as a Rollout when progressive delivery is enabled.

## Validation
- The temporary demo Rollout starts on `1.0.2`.
- Argo Rollouts creates a new ReplicaSet.
- Canary traffic/replica weight progresses through the documented steps.
- Pause durations are observed.
- Readiness failures stop progression.
- Rollback is described as a Git revert or image-tag change back to the previous known-good version in a production GitOps flow.
- The stable service remains available during progression.
- Metrics-based analysis is present if the lab claims automated health-based promotion.
- The demo uses `1.0.2` and `1.0.3` release tags. An unchanged image tag or application-reported version does not provide traceable progressive delivery.

## Troubleshooting
Start with the Rollout object and controller status:

```bash
printf '\n===== Argo Rollouts Application details =====\n'
kubectl -n argocd describe application argo-rollouts
printf '\n===== sample-api-dev Application details =====\n'
kubectl -n argocd describe application sample-api-dev
printf '\n===== GitOps sample-api Rollout details =====\n'
kubectl -n sample-api-dev describe rollout sample-api
printf '\n===== Demo Rollout details =====\n'
kubectl -n sample-api-rollout-demo describe rollout sample-api-rollout-demo
printf '\n===== Argo Rollouts controller pods =====\n'
kubectl -n argo-rollouts get pods -o wide
```

If no canary happens:

- Confirm the rendered chart creates a `Rollout`, not a `Deployment`.
- Confirm the temporary demo Rollout image and `APP_VERSION` value changed from `1.0.2` to `1.0.3`.
- Confirm the Rollout controller is healthy.
- If `kubectl -n sample-api-rollout-demo get rollout,replicaset,pod` prints `No resources found` after `kubectl apply` reported created resources, check the `default` namespace. Re-apply the manifest with `kubectl -n sample-api-rollout-demo apply -f /tmp/sample-api-rollout-demo.yaml` and remove any accidentally created default-namespace demo resources.

If rollout pauses unexpectedly:

- Inspect `kubectl -n sample-api-dev describe rollout sample-api`.
- Check pod readiness and image pull errors.
- Confirm pause steps are part of the configured canary strategy.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Delete the temporary demo namespace before moving on. Keep Argo Rollouts installed for later resilience validation.

```bash
kubectl -n default delete rollout,service,serviceaccount,networkpolicy,pdb sample-api-rollout-demo --ignore-not-found
kubectl delete namespace sample-api-rollout-demo --ignore-not-found
rm -f /tmp/sample-api-rollout-demo.yaml
```

## Next Steps
Continue with [Lab 17 - High Availability and Resilience](./lab17-high-availability-and-resilience.md).
