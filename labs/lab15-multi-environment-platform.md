# Lab 15 - Multi-Environment Platform

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Operations |
| **Lab** | 15 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-45 minutes |
| **Estimated Cost** | Low |
| **Primary Tools** | Helm, kubectl, Argo CD |

## Introduction

This lab introduces the checks used to evaluate a multi-environment GitOps layout for the platform.

The current platform has only the development workload reconciled. This lab treats that as a gap assessment: you are checking whether staging and production are represented in GitOps desired state, not manually creating them during validation.

Concepts introduced in this lab include environment separation, namespace boundaries, promotion, environment-specific desired state and Git history as an audit trail. See the [Concepts Reference](../concepts/README.md) for how multi-environment GitOps fits into the platform.

## Outcome
Validate the current multi-environment GitOps readiness and identify whether staging and production desired state are actually reconciled.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 14 completed
- AWS CLI, Terraform, kubectl and Helm installed
- Repository URLs configured

## Files to Review
Review these files before validation:

- `platform-config/environments/namespaces.yaml`: namespace boundaries and environment labels.
- `platform-config/clusters/dev/*.yaml`: current single-cluster GitOps Applications that may need environment-specific variants.
- `platform-config/bootstrap/root-application.yaml`: root Application path, which determines whether environment manifests are reconciled.
- `helm-charts/charts/sample-api/values.yaml`: default chart values that environment-specific overrides build on.

## Step-by-Step Implementation

1. Review the namespace desired state:

   ```bash
   cd "$WORKSPACE/platform-config"
   yq '.' environments/namespaces.yaml
   ```

   Confirm each namespace has a clear `environment` label such as `dev`, `staging` or `production`. The label is used by humans, policies and validation commands to distinguish environments.

2. Confirm whether the environment namespace file is reconciled by Argo CD:

   ```bash
   yq '.spec.source.path' bootstrap/root-application.yaml
   grep -R "environments/namespaces.yaml\|path: environments" -n . || true
   ```

   The first command prints the directory watched by the root Argo CD Application. In this lab series it is usually `clusters/dev`, which means Argo CD automatically reads child Applications from `platform-config/clusters/dev`.

   The second command checks whether anything under the current GitOps tree references `environments/namespaces.yaml` directly, or points an Argo CD Application at the `environments` directory. No output means the namespace file exists in Git, but Argo CD is not currently told to apply it.

   A file sitting outside the root Application path is not applied automatically. For this lab, treat missing wiring as an important finding: namespaces alone are not a multi-environment platform until they are connected to GitOps desired state. Do not manually apply the file to make the check pass; either the GitOps wiring must exist already, or adding that wiring becomes follow-up implementation work.

3. Review current environment-specific application state:

   ```bash
   kubectl -n argocd get applications.argoproj.io -o wide
   grep -R "sample-api-staging\|sample-api-production\|environment:" -n clusters environments || true
   ```

   A multi-environment platform needs more than namespaces. It should have clear desired state for each environment or a documented promotion path from dev to staging to production.

4. Run local checks before refreshing Argo CD:

   ```bash
   cd "$WORKSPACE"
   kubectl apply --dry-run=client -f platform-config/environments/namespaces.yaml
   helm lint helm-charts/charts/sample-api
   helm template sample-api helm-charts/charts/sample-api >/dev/null
   ```

   The namespace dry-run confirms Kubernetes can parse the manifests. Helm lint and render confirm the reusable chart still works before multiple environments consume it.

5. Refresh Argo CD and inspect the environment Applications:

   ```bash
   kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get applications.argoproj.io -o wide
   ```

   This refresh does not create new environments by itself. It only asks Argo CD to re-read the Git paths it already knows about. If `platform-root` still points at `clusters/dev` and no child Application points at `environments`, Argo CD will continue reconciling the existing dev Applications only.

   Expected result in the current slim platform: the existing Applications remain `Synced / Healthy`, and you may still see only the dev workload Application. That means the platform is healthy, but staging and production have not yet been wired into GitOps.

6. Validate that each namespace has isolated workloads, policies and configuration:

   ```bash
   kubectl get namespaces -L environment
   kubectl get applications.argoproj.io -n argocd
   for ns in sample-api-dev sample-api-staging sample-api-production; do
     echo "===== $ns ====="
     if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
       echo "namespace missing"
       continue
     fi
     kubectl -n "$ns" get deploy,rollout,svc,pod,externalsecret,networkpolicy,pdb
     kubectl -n "$ns" get resourcequota,limitrange
   done
   ```

   If `sample-api-dev` contains resources and `sample-api-staging` or `sample-api-production` contain no resources, your cluster is still dev-only from an application perspective. That is the key finding for this lab. It means the namespace file or future environment layout may exist in Git, but staging and production workload Applications are not currently reconciled by Argo CD.

   Also compare this output with `kubectl get namespaces -L environment`. If staging and production namespaces do not appear there, even the namespace desired state is not currently applied. If they appear but contain no workload resources, only the namespace layer exists.

7. Query each environment's API if workloads exist:

   ```bash
   for ns in sample-api-dev sample-api-staging sample-api-production; do
     if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
       echo "===== $ns ====="
       echo "namespace missing; skipping API check"
       continue
     fi
     if kubectl -n "$ns" get svc sample-api >/dev/null 2>&1; then
       echo "===== $ns ====="
       kubectl -n "$ns" port-forward svc/sample-api 8080:80 >/tmp/$ns-port-forward.log 2>&1 &
       PF_PID=$!
       sleep 2
       curl -fsS http://localhost:8080/health || true
       kill "$PF_PID"
     else
       echo "===== $ns ====="
       echo "sample-api service missing; skipping API check"
     fi
   done
   ```

   In a dev-only cluster, this loop will query only `sample-api-dev` and skip staging and production because their `sample-api` Services do not exist. That is expected when those environments are not wired yet. In a completed multi-environment setup, each environment should return its own response, image tag and environment-specific values.

8. Understand what is required to activate multiple environments:

   This lab does not create staging or production. To turn the current dev-only platform into an active multi-environment setup, the platform needs additional GitOps desired state.

   At minimum, a complete multi-environment setup needs:

   - A reconciled namespace source, such as an Argo CD Application that applies `platform-config/environments/namespaces.yaml`.
   - One workload Application per environment, for example `sample-api-dev`, `sample-api-staging` and `sample-api-production`, each targeting the correct namespace.
   - Environment-specific Helm values for each workload, such as replica counts, image tags, secret remote keys, resource settings and rollout settings.
   - A promotion process that moves a tested image tag from dev to staging to production through Git changes, not by reusing mutable state across environments.
   - Environment-scoped security and operations settings, such as NetworkPolicies, ExternalSecrets, quotas, disruption budgets and service accounts.

   A common layout is to keep shared chart logic in `helm-charts`, environment-specific desired state in `platform-config`, and promotion history in Git commits or pull requests. The important rule is that Argo CD must be told about every environment path that should be reconciled; files that exist in Git but are not under an Argo CD Application path are only documentation until they are wired into GitOps.

## Expected Results
The lab identifies whether the platform is still dev-only or whether each environment is represented by explicit GitOps desired state rather than ad hoc manual deployment.

## Validation
- Current dev resources remain `Synced / Healthy` after the Argo CD refresh.
- The lab output clearly shows whether staging and production namespaces exist.
- The lab output clearly shows whether staging and production workload Applications exist.
- If only dev resources exist, that is recorded as a multi-environment gap rather than treated as a successful deployment.
- Namespaces alone do not constitute a multi-environment platform; workloads and environment-specific desired state must also be present.
- In a completed multi-environment setup, dev, staging and production each have namespace labels, GitOps Applications, environment-specific values and traceable promotion history.

## Troubleshooting
Start by confirming what Argo CD is actually configured to read:

```bash
cd "$WORKSPACE/platform-config"
yq '.spec.source.path' bootstrap/root-application.yaml
grep -R "environments/namespaces.yaml\|path: environments\|sample-api-staging\|sample-api-production" -n . || true
kubectl get namespaces -L environment
kubectl -n argocd get applications.argoproj.io -o wide
```

If staging or production namespaces are missing:

- Confirm `environments/namespaces.yaml` defines those namespaces.
- Confirm an Argo CD Application references that file or its parent directory.
- Do not manually apply the namespace file as a workaround; that bypasses the GitOps check this lab is validating.

If staging or production namespaces exist but have no workloads:

- Confirm Argo CD has workload Applications for those environments.
- Confirm each Application points at the intended chart and target namespace.
- Confirm each environment has its own Helm values instead of accidentally reusing the dev values unchanged.

If only dev exists, the lab has still produced a useful result: the current platform is healthy but not yet an active multi-environment deployment.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
No cleanup is required. Do not delete existing dev resources. If staging or production namespaces exist, keep them only if they are part of the GitOps-managed desired state.

## Next Steps
Continue with [Lab 16 - Progressive Delivery](./lab16-progressive-delivery.md).
