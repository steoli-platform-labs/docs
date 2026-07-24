# Lab 15 - Multi-Environment Platform

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Operations |
| **Lab** | 15 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-45 minutes |
| **Estimated Cost** | Low |
| **Terraform** | No |
| **Kubernetes** | Yes |
| **GitOps** | Yes |

## Introduction

This lab introduces a multi-environment GitOps layout for the platform.

The platform starts separating environment-specific desired state so development, staging and production-style environments can evolve without mixing namespace, policy or application configuration.

Concepts introduced in this lab include environment separation, namespace boundaries, promotion, environment-specific desired state and Git history as an audit trail. See the [Concepts Reference](../concepts/README.md) for how multi-environment GitOps fits into the platform.

## Outcome
Implement and validate Multi-Environment Platform in the complete platform reference implementation.

## Prerequisites
Complete Lab 01 - Lab 14. AWS CLI, Terraform, kubectl and Helm must be installed, with repository URLs configured.

## Repository Changes
Primary implementation: `platform-config/environments/namespaces.yaml` plus environment-specific GitOps Applications and values as they are introduced.

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

   A file sitting outside the root Application path is not applied automatically. If `environments/namespaces.yaml` is not referenced by a root or child Application, add the GitOps wiring before expecting Argo CD to create namespaces.

3. Review current environment-specific application state:

   ```bash
   kubectl -n argocd get applications.argoproj.io -o wide
   grep -R "sample-api-staging\|sample-api-production\|environment:" -n clusters environments || true
   ```

   A multi-environment platform needs more than namespaces. It should have clear desired state for each environment or a documented promotion path from dev to staging to production.

4. Run local checks before committing changes:

   ```bash
   cd "$WORKSPACE"
   kubectl apply --dry-run=client -f platform-config/environments/namespaces.yaml
   helm lint helm-charts/charts/sample-api
   helm template sample-api helm-charts/charts/sample-api >/dev/null
   ```

   The namespace dry-run confirms Kubernetes can parse the manifests. Helm lint and render confirm the reusable chart still works before multiple environments consume it.

5. Commit and push environment configuration changes if you made any:

   ```bash
   git -C platform-config status --short
   git -C helm-charts status --short
   ```

   Commit changed files in the repository that owns them. Namespace and Argo CD Application changes belong in `platform-config`; chart changes belong in `helm-charts`.

6. Refresh Argo CD after the relevant changes are pushed:

   ```bash
   kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get applications.argoproj.io -o wide
   ```

   Confirm the root Application revision matches the pushed `platform-config` commit before validating child resources.

7. Validate that each namespace has isolated workloads, policies and configuration:

   ```bash
   kubectl get namespaces -L environment
   kubectl get applications.argoproj.io -n argocd
   for ns in sample-api-dev sample-api-staging sample-api-production; do
     echo "===== $ns ====="
     kubectl -n "$ns" get deploy,rollout,svc,pod,externalsecret,networkpolicy,pdb
     kubectl -n "$ns" get resourcequota,limitrange
   done
   ```

   Some environments may initially contain only namespaces until their workload Applications are added. Treat missing staging or production workload desired state as implementation work, not as a successful multi-environment deployment.

8. Query each environment's API if workloads exist:

   ```bash
   for ns in sample-api-dev sample-api-staging sample-api-production; do
     if kubectl -n "$ns" get svc sample-api >/dev/null 2>&1; then
       echo "===== $ns ====="
       kubectl -n "$ns" port-forward svc/sample-api 8080:80 >/tmp/$ns-port-forward.log 2>&1 &
       PF_PID=$!
       sleep 2
       curl -fsS http://localhost:8080/health || true
       kill "$PF_PID"
     fi
   done
   ```

   Confirm responses, image tags and environment variables match the environment being tested.

## Expected Results
The environment namespaces exist and each environment is represented by explicit GitOps desired state rather than ad hoc manual deployment.

## Validation
- Dev, staging and production namespaces exist with correct labels.
- Each environment has an independently managed Argo CD application or equivalent GitOps source.
- Environment-specific values are visible in workload configuration.
- A dev change does not automatically alter staging or production.
- Secrets, service accounts and NetworkPolicies are namespace-scoped as intended.
- Resource requests, quotas and disruption policies are appropriate for each environment.
- Promotion is traceable to Git history.
- Namespaces alone do not constitute a multi-environment platform; workloads and environment-specific desired state must also be present.

## Troubleshooting
Start with namespace labels and Argo CD Applications:

```bash
kubectl get namespaces -L environment
kubectl -n argocd get applications.argoproj.io -o wide
kubectl get events -A --sort-by=.lastTimestamp
```

If namespaces exist but workloads do not:

- Confirm Argo CD has an Application for that environment.
- Confirm the Application path is under a reconciled root Application.
- Confirm environment-specific values exist and point to the intended namespace.

If a dev change affects staging or production unexpectedly:

- Confirm environments do not share the same mutable values file.
- Confirm promotion is a Git change, not an implicit side effect of `latest` or shared mutable tags.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
No cleanup is required. Later labs depend on the environment namespaces and GitOps structure.

## Next Steps
Continue with [Lab 16 - Progressive Delivery](./lab16-progressive-delivery.md).
