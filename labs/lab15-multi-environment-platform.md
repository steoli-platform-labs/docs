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

## Outcome
Implement and validate Multi-Environment Platform in the complete platform reference implementation.

## Prerequisites
Complete Lab 01 - Lab 14, configure AWS CLI, Terraform, kubectl, Helm and repository URLs.

## Repository Changes
Primary implementation: `platform-config/environments/namespaces.yaml`.

## Files to Review
Review the multi-environment configuration files and update any environment-specific values before validation.

## Step-by-Step Implementation

1. Review `platform-config/environments/namespaces.yaml` and the environment-specific sample API desired state.
2. Confirm dev, staging and production have explicit namespace, values and promotion boundaries.
3. Commit and push any environment configuration changes.
4. Let Argo CD reconcile the environment Applications from Git after running local checks:

   ```bash
   cd "$WORKSPACE"
   helm lint helm-charts/charts/sample-api
   kubectl apply --dry-run=client -f platform-config/environments/namespaces.yaml
   kubectl -n argocd get applications.argoproj.io -o wide
   ```

5. Validate that each namespace has isolated workloads, policies and configuration:

   ```bash
   kubectl get namespaces -L environment
   kubectl get applications.argoproj.io -n argocd
   for ns in sample-api-dev sample-api-staging sample-api-production; do
     echo "===== $ns ====="
     kubectl -n "$ns" get deploy,rollout,svc,pod,externalsecret,networkpolicy,pdb
     kubectl -n "$ns" get resourcequota,limitrange
   done
   ```

   Query each environment's API and confirm the response identifies the correct environment and image version.

## Expected Results
The environment namespaces exist and each environment is represented by explicit GitOps desired state rather than ad hoc manual deployment.

## Validation
Pass criteria:

- Dev, staging and production namespaces exist with correct labels.
- Each environment has an independently managed Argo CD application or equivalent GitOps source.
- Environment-specific values are visible in workload configuration.
- A dev change does not automatically alter staging or production.
- Secrets, service accounts and NetworkPolicies are namespace-scoped as intended.
- Resource requests, quotas and disruption policies are appropriate for each environment.
- Promotion is traceable to Git history.

Namespaces alone do not constitute a multi-environment platform; workloads and environment-specific desired state must also be present.

## Troubleshooting
Start with namespace labels and Argo CD Applications:

```bash
kubectl get namespaces -L environment
kubectl -n argocd get applications.argoproj.io -o wide
kubectl get events -A --sort-by=.lastTimestamp
```

## Commit and Push
Use a focused conventional commit such as `feat: complete lab 15`.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
No cleanup is required. Later labs depend on the environment namespaces and GitOps structure.

## Next Steps
Continue with [Lab 16 - Progressive Delivery](./lab16-progressive-delivery.md).
