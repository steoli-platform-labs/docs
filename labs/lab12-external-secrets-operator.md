# Lab 12 - External Secrets Operator

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Security |
| **Lab** | 12 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-60 minutes |
| **Primary Tools** | AWS CLI, Terraform, Helm, kubectl, Argo CD, External Secrets Operator |

## Introduction

This lab introduces External Secrets Operator for synchronizing secrets from AWS Secrets Manager into Kubernetes.

This lab creates AWS Secrets Manager test secrets. They are small lab values, but Secrets Manager charges per stored secret until they are deleted or scheduled for deletion in the final cleanup lab.

The goal is to keep real secret values outside Git while still managing the secret synchronization configuration declaratively through the platform GitOps repository.

Concepts introduced in this lab include External Secrets Operator, ExternalSecrets, ClusterSecretStores, AWS Secrets Manager, Kubernetes Secrets and secret synchronization. See the [Concepts Reference](../concepts/README.md) for how secret values stay outside Git.

## Outcome
Validate External Secrets Operator in the complete platform reference implementation and confirm it syncs a test AWS Secrets Manager value into Kubernetes.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 11 completed
- AWS CLI, Terraform, kubectl and Helm installed
- Repository URLs configured

## Files to Review
Review these files before validation:

- `platform-config/clusters/dev/external-secrets.yaml`: Argo CD Application for the External Secrets Operator Helm chart.
- `platform-config/clusters/dev/external-secrets-config.yaml`: Argo CD Application that applies the External Secrets configuration under `addons/external-secrets`.
- `platform-config/addons/external-secrets/cluster-secret-store.yaml`: `ClusterSecretStore` for AWS Secrets Manager.
- `platform-modules/modules/eks/external-secrets.tf`: IAM role, policy and EKS Pod Identity association for External Secrets Operator.
- `platform-live/environments/shared/outputs.tf`: exposes the External Secrets IAM role ARN for validation.
- `helm-charts/charts/sample-api/templates/externalsecret.yaml`: optional workload-level ExternalSecret template.
- `platform-config/clusters/dev/sample-api-dev.yaml`: values that enable or disable the dev sample API ExternalSecret.

## Step-by-Step Implementation

1. Review the External Secrets Operator Application:

   ```bash
   cd "$WORKSPACE/platform-config"
   printf '\n===== External Secrets Application source =====\n'
   yq '.spec.source' clusters/dev/external-secrets.yaml
   printf '\n===== External Secrets Application destination =====\n'
   yq '.spec.destination' clusters/dev/external-secrets.yaml
   ```

   Confirm the chart repository is `https://charts.external-secrets.io`, the chart is `external-secrets`, `targetRevision` is pinned to the tested chart version and the destination namespace is `external-secrets`. The Application should use `ServerSideApply=true` because some External Secrets Operator CRDs are too large for Kubernetes client-side apply annotations.

   Compare the configured chart version with the latest available chart version:

   ```bash
   printf '\n===== Configured External Secrets chart =====\n'
   yq -r '.spec.source.targetRevision' clusters/dev/external-secrets.yaml
   printf '\n===== Latest available External Secrets chart =====\n'
   helm show chart external-secrets --repo https://charts.external-secrets.io | yq '.version'
   ```

   The pinned version in `clusters/dev/external-secrets.yaml` is the version tested by this lab. Newer chart versions may exist by the time you run the lab. Do not change the pinned version just because a newer version is available; Helm charts can change required values between releases.

2. Check whether the SecretStore desired state and GitOps wiring exist:

   ```bash
   printf '\n===== External Secrets config Application source =====\n'
   yq '.spec.source' clusters/dev/external-secrets-config.yaml
   printf '\n===== SecretStore manifests =====\n'
   grep -R "kind: ClusterSecretStore\|kind: SecretStore" -n . || true
   ```

   The operator can be healthy without any store configured. A `ClusterSecretStore` or `SecretStore` is required before an `ExternalSecret` can read from AWS Secrets Manager. The root Application points at `clusters/dev`, so `external-secrets-config.yaml` is the child Application that tells Argo CD to reconcile the store manifests under `addons/external-secrets`.

3. Review the sample API ExternalSecret template and values:

   ```bash
   cd "$WORKSPACE"
   printf '\n===== sample-api chart secret values =====\n'
   yq '.secret' helm-charts/charts/sample-api/values.yaml
   printf '\n===== sample-api-dev Helm values =====\n'
   yq '.spec.source.helm.values' platform-config/clusters/dev/sample-api-dev.yaml
   ```

   Confirm the sample API chart creates an `ExternalSecret` and references the same remote key used in the AWS test secret step. Do not commit real secret values. Only commit references such as secret names, remote keys and property names.

4. Create or confirm the AWS test secret without printing its value:

   ```bash
   export AWS_PAGER=""
   export AWS_REGION="$(yq -r '.spec.provider.aws.region' "$WORKSPACE/platform-config/addons/external-secrets/cluster-secret-store.yaml")"

   CHART_SECRET_ID="$(yq -r '.secret.remoteKey // ""' "$WORKSPACE/helm-charts/charts/sample-api/values.yaml")"
   APP_SECRET_ID="$(yq -r '.spec.source.helm.values | from_yaml | .secret.remoteKey // ""' "$WORKSPACE/platform-config/clusters/dev/sample-api-dev.yaml")"
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

   The remote key is the name of the secret in AWS Secrets Manager. The `ExternalSecret` points at that remote key, and External Secrets Operator creates or updates a normal Kubernetes Secret inside the application namespace.

5. Confirm the External Secrets IAM and Pod Identity prerequisites from the earlier Terraform labs:

   ```bash
   cd "$WORKSPACE"
   CLUSTER_NAME="$(terraform -chdir=platform-live/environments/shared output -raw cluster_name)"

   printf '\n===== External Secrets role ARN =====\n'
   terraform -chdir=platform-live/environments/shared output external_secrets_role_arn

   printf '\n===== External Secrets Pod Identity association =====\n'
   aws eks list-pod-identity-associations \
     --cluster-name "$CLUSTER_NAME" \
     --namespace external-secrets \
     --service-account external-secrets
   ```

   These Terraform-managed resources were created when you applied the current shared AWS infrastructure in the earlier Terraform labs. The role output should exist and the EKS Pod Identity association should target the `external-secrets/external-secrets` Kubernetes service account. If either check is missing, stop and reconcile `platform-live/environments/shared` before continuing; otherwise the `ClusterSecretStore` can exist but will report `Ready=False` because the operator cannot create an AWS Secrets Manager client.

   The Pod Identity association output should include the `external-secrets` namespace and `external-secrets` service account. An empty `associations` list is a stop condition.

6. Render the relevant charts before relying on Argo CD:

   ```bash
   printf '\n===== Render External Secrets chart =====\n'
   helm template external-secrets external-secrets \
     --repo https://charts.external-secrets.io \
     --version "$(yq -r '.spec.source.targetRevision' platform-config/clusters/dev/external-secrets.yaml)" \
     --namespace external-secrets \
     >/dev/null

   printf '\n===== sample-api Helm lint =====\n'
   helm lint helm-charts/charts/sample-api
   printf '\n===== Render sample-api chart =====\n'
   helm template sample-api helm-charts/charts/sample-api \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/dev/sample-api-dev.yaml) \
     >/dev/null
   ```

   A render failure here means Argo CD will also fail to generate manifests.

   `helm lint` should end with `1 chart(s) linted, 0 chart(s) failed`. The render commands redirect output to `/dev/null`, so no output means success.

7. Refresh the root Argo CD Application, then reconcile `external-secrets`, `external-secrets-config` and `sample-api-dev`:

   ```bash
   printf '\n===== Refresh dev root =====\n'
   kubectl -n argocd annotate application platform-root-dev argocd.argoproj.io/refresh=hard --overwrite
   printf '\n===== Applications before child refresh =====\n'
   kubectl -n argocd get application external-secrets external-secrets-config sample-api-dev -o wide
   printf '\n===== Refresh external-secrets Application =====\n'
   kubectl -n argocd annotate application external-secrets argocd.argoproj.io/refresh=hard --overwrite
   printf '\n===== Refresh external-secrets-config Application =====\n'
   kubectl -n argocd annotate application external-secrets-config argocd.argoproj.io/refresh=hard --overwrite
   printf '\n===== Refresh sample-api-dev Application =====\n'
   kubectl -n argocd annotate application sample-api-dev argocd.argoproj.io/refresh=hard --overwrite
   printf '\n===== Applications after child refresh =====\n'
   kubectl -n argocd get application external-secrets external-secrets-config sample-api-dev -o wide
   ```

   Expected behavior: after the current `platform-config` revision is reconciled, `external-secrets`, `external-secrets-config` and `sample-api-dev` should move toward `Synced / Healthy`. If any Application shows `OutOfSync / Degraded`, describe that Application and check for sync errors before continuing.

8. Validate the operator, store readiness and test `ExternalSecret` reconciliation:

   ```bash
   printf '\n===== external-secrets Application =====\n'
   kubectl -n argocd get application external-secrets -o wide
   printf '\n===== External Secrets config and sample API Applications =====\n'
   kubectl -n argocd get application external-secrets-config sample-api-dev -o wide
   printf '\n===== External Secrets workloads =====\n'
   kubectl -n external-secrets get pods,serviceaccounts
   printf '\n===== ClusterSecretStore manifest =====\n'
   kubectl get clustersecretstore aws-secrets-manager -o yaml
   printf '\n===== ClusterSecretStore details =====\n'
   kubectl describe clustersecretstore aws-secrets-manager
   printf '\n===== sample-api secrets =====\n'
   kubectl -n sample-api-dev get externalsecret,secret
   printf '\n===== sample-api ExternalSecret details =====\n'
   kubectl -n sample-api-dev describe externalsecret sample-api
   printf '\n===== External Secrets logs =====\n'
   kubectl -n external-secrets logs deployment/external-secrets --since=10m --tail=200
   ```

   Expected behavior: operator pods are ready, the store reports `Ready=True` and the `ExternalSecret` reports `Ready=True` after it syncs.

   In the describe output, stop on `Ready=False`, `AccessDenied`, missing remote key, missing Pod Identity credentials or AWS client errors. The target Kubernetes Secret should exist, but you should only inspect metadata and key names, not decoded values.

   Create or identify a non-sensitive test secret in AWS Secrets Manager, enable the chart's ExternalSecret configuration, sync Argo CD and verify the Kubernetes Secret metadata and key names without printing values:

   ```bash
   printf '\n===== sample-api secret name =====\n'
   kubectl -n sample-api-dev get secret sample-api -o jsonpath='{.metadata.name}{"\n"}'
   printf '\n===== sample-api secret keys =====\n'
   kubectl -n sample-api-dev get secret sample-api -o go-template='{{range $key, $_ := .data}}{{printf "%s\n" $key}}{{end}}'
   ```

   Expected output:

   ```text
   sample-api
   EXAMPLE_CONFIG
   ```

   This is the expected successful ending for the secret synchronization path. It proves that External Secrets Operator read the `platform-labs/sample-api-dev` test secret from AWS Secrets Manager and created the `sample-api-dev/sample-api` Kubernetes Secret with the expected key. The sample application does not consume `EXAMPLE_CONFIG` yet; this lab validates the platform secret-management capability without introducing a real application credential.

   Checking the Secret name and key list is safe because it proves synchronization happened without exposing the actual value. Decoding or printing the value would turn a secret-management lab into a secret-leak risk.

   Do not decode, print or screenshot real secret values in terminals, issue comments, pull requests or CI logs.

## Expected Results
The `external-secrets` and `external-secrets-config` Argo CD Applications reconcile successfully, the operator can read from the configured AWS Secrets Manager store and the sample API namespace contains a Kubernetes Secret named `sample-api` with the key `EXAMPLE_CONFIG`.

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
printf '\n===== External Secrets Application details =====\n'
kubectl -n argocd describe application external-secrets
printf '\n===== External Secrets pods =====\n'
kubectl -n external-secrets get pods -o wide
printf '\n===== ClusterSecretStore details =====\n'
kubectl describe clustersecretstore aws-secrets-manager
printf '\n===== External Secrets logs =====\n'
kubectl -n external-secrets logs deployment/external-secrets --since=10m --tail=200
```

If the operator is healthy but no Kubernetes Secret appears:

- Confirm a `ClusterSecretStore` or `SecretStore` exists and is ready.
- Confirm the `ExternalSecret` exists in the workload namespace.
- Confirm the remote AWS secret exists and the remote key/property names match.
- Check operator logs for authentication or `AccessDenied` errors.
- Do not troubleshoot by printing decoded secret values.

If the Application is `OutOfSync / Degraded` and the sync error mentions `metadata.annotations: Too long`, Argo CD tried to apply large CRDs using client-side apply. Confirm `platform-config/clusters/dev/external-secrets.yaml` includes `ServerSideApply=true`. If it does not, stop and reconcile the desired state before refreshing `platform-root-dev` and `external-secrets` again.

If the Application becomes `Synced` but the main `external-secrets` pod remains in `CrashLoopBackOff` with log messages such as `no matches for kind "ClusterSecretStore"`, the controller may have started before the CRDs were fully available. After confirming the CRDs exist, restart the controller deployment:

```bash
printf '\n===== External Secrets CRDs =====\n'
kubectl get crd clustersecretstores.external-secrets.io secretstores.external-secrets.io externalsecrets.external-secrets.io
printf '\n===== Restart External Secrets deployment =====\n'
kubectl -n external-secrets rollout restart deployment/external-secrets
printf '\n===== External Secrets rollout status =====\n'
kubectl -n external-secrets rollout status deployment/external-secrets --timeout=180s
printf '\n===== External Secrets Application =====\n'
kubectl -n argocd get application external-secrets -o wide
```

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Keep External Secrets Operator installed for later security and application labs. Remove only temporary non-sensitive test secrets created during validation.

## Next Steps
Continue with [Lab 13 - Workload Identity](./lab13-iam-roles-for-service-accounts.md). Later labs keep this secret-management foundation in place: Lab 13 validates workload identity patterns, Lab 15 checks that environment-specific workloads include `ExternalSecret` resources where configured and future application changes can replace the non-sensitive test key with real configuration references without committing secret values to Git.
