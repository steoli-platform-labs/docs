# Lab 05 - Helm

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Kubernetes Platform |
| **Lab** | 05 |
| **Difficulty** | Beginner |
| **Estimated Time** | 15-25 minutes |
| **Estimated Cost** | Free |
| **Terraform** | No |
| **Kubernetes** | Yes |
| **GitOps** | No |

## Introduction

This lab validates the reusable `sample-api` Helm chart.

Application deployment remains GitOps-driven in later labs. This lab only lints and renders the chart locally.

## Outcome

After this lab, the reusable `sample-api` Helm chart has been linted and rendered locally without deploying any workload to the cluster.

## Prerequisites

- Lab 01 - Lab 04 completed.
- Helm and kubectl installed for local rendering and client-side schema validation.
- This lab uses local Helm rendering only and does not install the chart into Kubernetes.

## Repository Changes

| Repository | Responsibility |
|------------|----------------|
| `helm-charts` | Owns the reusable `sample-api` Helm chart |
| `docs` | Documents the lab workflow |

## Files to Review

| File | Why it matters |
|------|----------------|
| `helm-charts/charts/sample-api/Chart.yaml` | Defines chart metadata |
| `helm-charts/charts/sample-api/values.yaml` | Defines configurable chart defaults |
| `helm-charts/charts/sample-api/templates/deployment.yaml` | Renders the default workload |
| `helm-charts/charts/sample-api/templates/service.yaml` | Exposes the workload internally |
| `helm-charts/charts/sample-api/templates/_helpers.tpl` | Centralizes common labels and names |

## Step-by-Step Implementation

Lint the chart, render manifests with validation values and run a Kubernetes client-side dry run.

1. Open the Helm charts repository:

   ```bash
   cd "$WORKSPACE/helm-charts"
   ```

2. Lint and render the chart:

   ```bash
   helm lint charts/sample-api
   helm template sample-api charts/sample-api \
     --namespace sample-api-dev \
     --set image.repository=example.invalid/sample-api \
     --set image.tag=validation \
     --set rollout.enabled=false \
     > /tmp/sample-api-rendered.yaml
   ```

3. Validate the rendered manifests client-side:

   ```bash
   kubectl apply --dry-run=client -f /tmp/sample-api-rendered.yaml
   ```

   This is a dry run only. Do not deploy the application with `helm install`, `helm upgrade`, or `kubectl apply`.

   The chart can render an Argo Rollout when `rollout.enabled=true`, but the Argo Rollouts CRD is introduced later. This lab disables Rollout rendering during client-side schema validation so only built-in Kubernetes APIs are checked.

4. Inspect the rendered resources:

   ```bash
   grep '^kind:' /tmp/sample-api-rendered.yaml
   grep -nE 'readinessProbe|livenessProbe|startupProbe|resources:|NetworkPolicy|PodDisruptionBudget' /tmp/sample-api-rendered.yaml
   ```

5. Commit the Helm chart changes only. Do not commit temporary rendered manifests.

   In `helm-charts`:

   ```bash
   cd "$WORKSPACE/helm-charts"
   git status
   git diff --check
   git add charts/sample-api/
   git commit -m "add sample api helm chart"
   git push
   ```

## Expected Results

`helm lint` succeeds, rendered manifests include the expected built-in Kubernetes resources, and the client-side dry run validates without deploying anything.

## Validation

- `helm lint` succeeds.
- Rendering produces either a Deployment or Rollout, never both.
- Service selectors match workload pod labels.
- Probes point to endpoints implemented by the application.
- CPU and memory requests are present.
- Optional ExternalSecret resources render only when enabled.
- Rendered resources pass Kubernetes client-side schema validation.

## Troubleshooting

If rendering fails, inspect `charts/sample-api/values.yaml` and the relevant template under `charts/sample-api/templates/`.

## Final Repository State

At completion, `helm-charts` contains the reusable `sample-api` chart and no workload has been deployed outside GitOps.

## Cleanup

Remove the temporary rendered manifest when finished:

```bash
rm -f /tmp/sample-api-rendered.yaml
```

## Next Steps

Continue with [Lab 06 - GitHub Actions](./lab06-github-actions.md).
