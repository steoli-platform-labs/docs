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

## Outcome
Implement and validate External Secrets Operator in the complete platform reference implementation.

## Prerequisites
Complete Lab 01 - Lab 11, configure AWS CLI, Terraform, kubectl, Helm and repository URLs.

## Repository Changes
Primary implementation: `platform-config/addons/external-secrets`.

## Files to Review
Review the External Secrets desired-state files and update any environment-specific values before validation.

## Step-by-Step Implementation
1. Review `platform-config/clusters/dev/external-secrets.yaml` and `platform-config/addons/external-secrets/cluster-secret-store.yaml`.
2. Confirm the SecretStore settings match the AWS region and authentication model from the lab environment.
3. Commit and push any required `platform-config` changes.
4. Let Argo CD reconcile the `external-secrets` Application from Git.
5. Validate the operator, `ClusterSecretStore` readiness and a test `ExternalSecret` reconciliation.

## Commands
```bash
cd "$WORKSPACE"
kubectl -n argocd get application external-secrets -o wide
kubectl -n argocd annotate application external-secrets argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd get application external-secrets -o wide
```

## Expected Results
The `external-secrets` Argo CD Application reconciles successfully and the operator can read from the configured AWS Secrets Manager store.

## Validation
### External Secrets Operator verification

```bash
kubectl -n argocd get application external-secrets -o wide
kubectl -n external-secrets get pods,serviceaccounts
kubectl get clustersecretstore aws-secrets-manager -o yaml
kubectl describe clustersecretstore aws-secrets-manager
kubectl -n sample-api-dev get externalsecret,secret
kubectl -n sample-api-dev describe externalsecret sample-api
kubectl -n external-secrets logs deployment/external-secrets --since=10m --tail=200
```

Create or identify a non-sensitive test secret in AWS Secrets Manager, enable the chart's ExternalSecret configuration, sync Argo CD and verify the Kubernetes Secret metadata and key names without printing values:

```bash
kubectl -n sample-api-dev get secret sample-api -o jsonpath='{.metadata.name}{"\n"}'
kubectl -n sample-api-dev get secret sample-api -o go-template='{{range $key, $_ := .data}}{{printf "%s\n" $key}}{{end}}'
```

Do not decode, print or screenshot real secret values in terminals, issue comments, pull requests or CI logs.

Pass criteria:

- The operator application is `Synced / Healthy`.
- Operator pods are ready.
- `ClusterSecretStore` has a `Ready=True` condition.
- `ExternalSecret` has a `Ready=True` condition and a recent refresh time.
- The target Kubernetes Secret exists with the expected key names.
- Updating the AWS test secret is reflected after the refresh interval or a forced refresh.
- Removing AWS access causes a controlled reconciliation error, not silent success.

The current repository must include both the `ClusterSecretStore` resource and a GitOps path that actually applies it; merely storing the file outside the root application's path is not sufficient.

## Troubleshooting
Start with the Argo CD Application, operator pods and store status:

```bash
kubectl -n argocd describe application external-secrets
kubectl -n external-secrets get pods -o wide
kubectl describe clustersecretstore aws-secrets-manager
kubectl -n external-secrets logs deployment/external-secrets --since=10m --tail=200
```

## Commit and Push
Use a focused conventional commit such as `feat: complete lab 12`.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Keep External Secrets Operator installed for later security and application labs. Remove only temporary non-sensitive test secrets created during validation.

## Next Steps
Continue with [Lab 13 - IRSA](./lab13-iam-roles-for-service-accounts.md).
