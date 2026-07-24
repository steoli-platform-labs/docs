# Lab 12 - External Secrets Operator

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Security |
| **Lab** | 12 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-60 minutes |
| **Estimated Cost** | Low |
| **Terraform** | No |
| **Kubernetes** | Yes |
| **GitOps** | Yes |

## Introduction

This lab introduces External Secrets Operator for synchronizing secrets from AWS Secrets Manager into Kubernetes.

The goal is to keep real secret values outside Git while still managing the secret synchronization configuration declaratively through the platform GitOps repository.

Concepts introduced in this lab include External Secrets Operator, ExternalSecrets, ClusterSecretStores, AWS Secrets Manager, Kubernetes Secrets and secret synchronization. See the [Concepts Reference](../concepts/README.md) for how secret values stay outside Git.

## Outcome
Implement and validate External Secrets Operator in the complete platform reference implementation.

## Prerequisites
Complete Lab 01 - Lab 11. AWS CLI, Terraform, kubectl and Helm must be installed, with repository URLs configured.

## Repository Changes
Primary implementation: `platform-config/clusters/dev/external-secrets.yaml` plus the SecretStore and ExternalSecret resources used by workloads.

## Files to Review
Review these files before validation:

- `platform-config/clusters/dev/external-secrets.yaml`: Argo CD Application for the External Secrets Operator Helm chart.
- `platform-config/addons/external-secrets/cluster-secret-store.yaml`: `ClusterSecretStore` for AWS Secrets Manager. This file must be wired into GitOps before Argo CD can apply it.
- `helm-charts/charts/sample-api/templates/externalsecret.yaml`: optional workload-level ExternalSecret template.
- `platform-config/clusters/dev/sample-api.yaml`: values that enable or disable the sample API ExternalSecret.

## Step-by-Step Implementation

1. Review the External Secrets Operator Application:

   ```bash
   cd "$WORKSPACE/platform-config"
   yq '.spec.source' clusters/dev/external-secrets.yaml
   yq '.spec.destination' clusters/dev/external-secrets.yaml
   ```

   Confirm the chart repository is `https://charts.external-secrets.io`, the chart is `external-secrets` and the destination namespace is `external-secrets`.

2. Check whether the SecretStore desired state exists:

   ```bash
   grep -R "kind: ClusterSecretStore\|kind: SecretStore" -n . || true
   ```

   The operator can be healthy without any store configured. A `ClusterSecretStore` or `SecretStore` is required before an `ExternalSecret` can read from AWS Secrets Manager. Because the root Application currently points at `clusters/dev`, files under `addons/external-secrets` also need an Argo CD Application or other GitOps wiring before they are reconciled.

3. Review the sample API ExternalSecret template and values:

   ```bash
   cd "$WORKSPACE"
   yq '.secret' helm-charts/charts/sample-api/values.yaml
   yq '.spec.source.helm.values' platform-config/clusters/dev/sample-api.yaml
   ```

   Confirm whether the sample API chart should create an `ExternalSecret`. Do not commit real secret values. Only commit references such as secret names, remote keys and property names.

4. Confirm the AWS test secret exists without printing its value:

   ```bash
   aws secretsmanager describe-secret --secret-id <test-secret-name-or-arn>
   ```

   This confirms the secret metadata exists. Do not run commands that print secret values during the lab.

5. Render the relevant charts before relying on Argo CD:

   ```bash
   helm template external-secrets external-secrets \
     --repo https://charts.external-secrets.io \
     --version "$(yq -r '.spec.source.targetRevision' platform-config/clusters/dev/external-secrets.yaml)" \
     --namespace external-secrets \
     >/dev/null

   helm lint helm-charts/charts/sample-api
   helm template sample-api helm-charts/charts/sample-api \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/dev/sample-api.yaml) \
     >/dev/null
   ```

   A render failure here means Argo CD will also fail to generate manifests.

6. Commit and push the desired state if you changed it:

   ```bash
   cd "$WORKSPACE/platform-config"
   git status --short
   git add clusters/dev/external-secrets.yaml clusters/dev/sample-api.yaml addons/external-secrets/cluster-secret-store.yaml
   git commit -m "feat: configure external secrets"
   git push
   ```

   If you added different SecretStore manifests or Argo CD wiring files, stage those actual paths too. If there are no changed files, skip the commit.

7. Refresh the root Argo CD Application, then reconcile `external-secrets`:

   ```bash
   kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application external-secrets -o wide
   kubectl -n argocd annotate application external-secrets argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application external-secrets -o wide
   ```

8. Validate the operator, store readiness and test `ExternalSecret` reconciliation:

   ```bash
   kubectl -n argocd get application external-secrets -o wide
   kubectl -n external-secrets get pods,serviceaccounts
   kubectl get clustersecretstore aws-secrets-manager -o yaml
   kubectl describe clustersecretstore aws-secrets-manager
   kubectl -n sample-api-dev get externalsecret,secret
   kubectl -n sample-api-dev describe externalsecret sample-api
   kubectl -n external-secrets logs deployment/external-secrets --since=10m --tail=200
   ```

   Expected behavior: operator pods are ready, the store reports `Ready=True` and the `ExternalSecret` reports `Ready=True` after it syncs.

   Create or identify a non-sensitive test secret in AWS Secrets Manager, enable the chart's ExternalSecret configuration, sync Argo CD and verify the Kubernetes Secret metadata and key names without printing values:

   ```bash
   kubectl -n sample-api-dev get secret sample-api -o jsonpath='{.metadata.name}{"\n"}'
   kubectl -n sample-api-dev get secret sample-api -o go-template='{{range $key, $_ := .data}}{{printf "%s\n" $key}}{{end}}'
   ```

   Do not decode, print or screenshot real secret values in terminals, issue comments, pull requests or CI logs.

## Expected Results
The `external-secrets` Argo CD Application reconciles successfully and the operator can read from the configured AWS Secrets Manager store.

## Validation
- The operator application is `Synced / Healthy`.
- Operator pods are ready.
- `ClusterSecretStore` has a `Ready=True` condition.
- `ExternalSecret` has a `Ready=True` condition and a recent refresh time.
- The target Kubernetes Secret exists with the expected key names.
- Updating the AWS test secret is reflected after the refresh interval or a forced refresh.
- Removing AWS access causes a controlled reconciliation error, not silent success.
- The current repository must include both the `ClusterSecretStore` resource and a GitOps path that actually applies it; merely storing the file outside the root application's path is not sufficient.

## Troubleshooting
Start with the Argo CD Application, operator pods and store status:

```bash
kubectl -n argocd describe application external-secrets
kubectl -n external-secrets get pods -o wide
kubectl describe clustersecretstore aws-secrets-manager
kubectl -n external-secrets logs deployment/external-secrets --since=10m --tail=200
```

If the operator is healthy but no Kubernetes Secret appears:

- Confirm a `ClusterSecretStore` or `SecretStore` exists and is ready.
- Confirm the `ExternalSecret` exists in the workload namespace.
- Confirm the remote AWS secret exists and the remote key/property names match.
- Check operator logs for authentication or `AccessDenied` errors.
- Do not troubleshoot by printing decoded secret values.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Keep External Secrets Operator installed for later security and application labs. Remove only temporary non-sensitive test secrets created during validation.

## Next Steps
Continue with [Lab 13 - IRSA](./lab13-iam-roles-for-service-accounts.md).
