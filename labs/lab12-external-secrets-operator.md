# Lab 12 - External Secrets Operator

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Security |
| **Lab** | 12 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-60 minutes |
| **Estimated Cost** | Low |
| **Terraform** | Yes |
| **Kubernetes** | Yes |
| **GitOps** | Yes |

## Introduction

This lab introduces External Secrets Operator for synchronizing secrets from AWS Secrets Manager into Kubernetes.

The goal is to keep real secret values outside Git while still managing the secret synchronization configuration declaratively through the platform GitOps repository.

Concepts introduced in this lab include External Secrets Operator, ExternalSecrets, ClusterSecretStores, AWS Secrets Manager, Kubernetes Secrets and secret synchronization. See the [Concepts Reference](../concepts/README.md) for how secret values stay outside Git.

## Outcome
Implement and validate External Secrets Operator in the complete platform reference implementation.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 11 completed
- AWS CLI, Terraform, kubectl and Helm installed
- Repository URLs configured

## Repository Changes
Primary implementation: External Secrets IAM/Pod Identity resources in Terraform, `platform-config/clusters/dev/external-secrets.yaml`, `platform-config/clusters/dev/external-secrets-config.yaml`, the SecretStore manifests and the ExternalSecret resources used by workloads.

## Files to Review
Review these files before validation:

- `platform-config/clusters/dev/external-secrets.yaml`: Argo CD Application for the External Secrets Operator Helm chart.
- `platform-config/clusters/dev/external-secrets-config.yaml`: Argo CD Application that applies the External Secrets configuration under `addons/external-secrets`.
- `platform-config/addons/external-secrets/cluster-secret-store.yaml`: `ClusterSecretStore` for AWS Secrets Manager.
- `platform-modules/modules/eks/external-secrets.tf`: IAM role, policy and EKS Pod Identity association for External Secrets Operator.
- `platform-live/environments/dev/outputs.tf`: exposes the External Secrets IAM role ARN for validation.
- `helm-charts/charts/sample-api/templates/externalsecret.yaml`: optional workload-level ExternalSecret template.
- `platform-config/clusters/dev/sample-api.yaml`: values that enable or disable the sample API ExternalSecret.

## Step-by-Step Implementation

1. Review the External Secrets Operator Application:

   ```bash
   cd "$WORKSPACE/platform-config"
   yq '.spec.source' clusters/dev/external-secrets.yaml
   yq '.spec.destination' clusters/dev/external-secrets.yaml
   ```

   Confirm the chart repository is `https://charts.external-secrets.io`, the chart is `external-secrets`, `targetRevision` is pinned to the tested chart version and the destination namespace is `external-secrets`. The Application should use `ServerSideApply=true` because some External Secrets Operator CRDs are too large for Kubernetes client-side apply annotations.

   Compare the configured chart version with the latest available chart version:

   ```bash
   echo "Configured External Secrets chart: $(yq -r '.spec.source.targetRevision' clusters/dev/external-secrets.yaml)"
   helm show chart external-secrets --repo https://charts.external-secrets.io | yq '.version'
   ```

   The pinned version in `clusters/dev/external-secrets.yaml` is the version tested by this lab. Newer chart versions may exist by the time you run the lab. Do not change the pinned version just because a newer version is available; Helm charts can change required values between releases.

2. Check whether the SecretStore desired state and GitOps wiring exist:

   ```bash
   yq '.spec.source' clusters/dev/external-secrets-config.yaml
   grep -R "kind: ClusterSecretStore\|kind: SecretStore" -n . || true
   ```

   The operator can be healthy without any store configured. A `ClusterSecretStore` or `SecretStore` is required before an `ExternalSecret` can read from AWS Secrets Manager. The root Application points at `clusters/dev`, so `external-secrets-config.yaml` is the child Application that tells Argo CD to reconcile the store manifests under `addons/external-secrets`.

3. Review the sample API ExternalSecret template and values:

   ```bash
   cd "$WORKSPACE"
   yq '.secret' helm-charts/charts/sample-api/values.yaml
   yq '.spec.source.helm.values' platform-config/clusters/dev/sample-api.yaml
   ```

   Confirm the sample API chart creates an `ExternalSecret` and references the same remote key used in the AWS test secret step. Do not commit real secret values. Only commit references such as secret names, remote keys and property names.

4. Create or confirm the AWS test secret without printing its value:

   ```bash
   export AWS_PAGER=""
   export AWS_REGION="$(yq -r '.spec.provider.aws.region' "$WORKSPACE/platform-config/addons/external-secrets/cluster-secret-store.yaml")"

   CHART_SECRET_ID="$(yq -r '.secret.remoteKey // ""' "$WORKSPACE/helm-charts/charts/sample-api/values.yaml")"
   APP_SECRET_ID="$(yq -r '.spec.source.helm.values | from_yaml | .secret.remoteKey // ""' "$WORKSPACE/platform-config/clusters/dev/sample-api.yaml")"
   SECRET_ID="${APP_SECRET_ID:-$CHART_SECRET_ID}"

   printf 'Using AWS Secrets Manager secret id: %s\n' "$SECRET_ID"

   if aws secretsmanager describe-secret --secret-id "$SECRET_ID" >/dev/null 2>&1; then
     printf 'Secret already exists.\n'
   else
     aws secretsmanager create-secret \
       --name "$SECRET_ID" \
       --description "Non-sensitive test secret for the External Secrets Operator lab" \
       --secret-string '{"EXAMPLE_CONFIG":"external-secrets-lab"}' \
       >/dev/null
     printf 'Created non-sensitive lab secret.\n'
   fi

   aws secretsmanager describe-secret --secret-id "$SECRET_ID"
   ```

   `SECRET_ID` is the AWS Secrets Manager name or ARN referenced by the sample API `ExternalSecret`. By default, it comes from the sample API chart's `secret.remoteKey` value. The command creates a deliberately non-sensitive JSON test value if the secret does not exist, then confirms only the secret metadata. Do not run commands that print secret values during the lab.

5. Verify the External Secrets IAM and Pod Identity prerequisites:

   ```bash
   cd "$WORKSPACE"
   terraform -chdir=platform-live/environments/dev validate

   CLUSTER_NAME="$(terraform -chdir=platform-live/environments/dev output -raw cluster_name)"
   terraform -chdir=platform-live/environments/dev output external_secrets_role_arn

   aws eks list-pod-identity-associations \
     --cluster-name "$CLUSTER_NAME" \
     --namespace external-secrets \
     --service-account external-secrets
   ```

   These resources are Terraform-managed platform prerequisites. A fresh run of the earlier infrastructure labs may already have created them from the current repository state. The role should be present and the EKS Pod Identity association should target the `external-secrets/external-secrets` Kubernetes service account.

   If the output or association is missing, reconcile the Terraform live environment before continuing:

   ```bash
   terraform -chdir=platform-modules fmt -recursive
   terraform -chdir=platform-live fmt -recursive
   terraform -chdir=platform-live/environments/dev plan
   terraform -chdir=platform-live/environments/dev apply
   ```

   Without this prerequisite, the `ClusterSecretStore` can exist but will report `Ready=False` because the operator cannot create an AWS Secrets Manager client.

6. Render the relevant charts before relying on Argo CD:

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

7. Commit and push the desired state if you changed it:

   ```bash
   cd "$WORKSPACE/platform-config"
   git status --short
   git add clusters/dev/external-secrets.yaml clusters/dev/external-secrets-config.yaml clusters/dev/sample-api.yaml addons/external-secrets/cluster-secret-store.yaml
   git commit -m "feat: configure external secrets"
   git push
   ```

   If you added different SecretStore manifests or Argo CD wiring files, stage those actual paths too. If there are no changed files, skip the commit.

8. Refresh the root Argo CD Application, then reconcile `external-secrets`, `external-secrets-config` and `sample-api`:

   ```bash
   kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application external-secrets external-secrets-config sample-api -o wide
   kubectl -n argocd annotate application external-secrets argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd annotate application external-secrets-config argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd annotate application sample-api argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application external-secrets external-secrets-config sample-api -o wide
   ```

   Expected behavior: after the latest `platform-config` commit is reconciled, `external-secrets`, `external-secrets-config` and `sample-api` should move toward `Synced / Healthy`. If any Application shows `OutOfSync / Degraded`, describe that Application and check for sync errors before continuing.

9. Validate the operator, store readiness and test `ExternalSecret` reconciliation:

   ```bash
   kubectl -n argocd get application external-secrets -o wide
   kubectl -n argocd get application external-secrets-config sample-api -o wide
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

If the Application is `OutOfSync / Degraded` and the sync error mentions `metadata.annotations: Too long`, Argo CD tried to apply large CRDs using client-side apply. Confirm `platform-config/clusters/dev/external-secrets.yaml` includes `ServerSideApply=true`, commit and push the change, refresh `platform-root`, then refresh `external-secrets` again.

If the Application becomes `Synced` but the main `external-secrets` pod remains in `CrashLoopBackOff` with log messages such as `no matches for kind "ClusterSecretStore"`, the controller may have started before the CRDs were fully available. After confirming the CRDs exist, restart the controller deployment:

```bash
kubectl get crd clustersecretstores.external-secrets.io secretstores.external-secrets.io externalsecrets.external-secrets.io
kubectl -n external-secrets rollout restart deployment/external-secrets
kubectl -n external-secrets rollout status deployment/external-secrets --timeout=180s
kubectl -n argocd get application external-secrets -o wide
```

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Keep External Secrets Operator installed for later security and application labs. Remove only temporary non-sensitive test secrets created during validation.

## Next Steps
Continue with [Lab 13 - IRSA](./lab13-iam-roles-for-service-accounts.md).
