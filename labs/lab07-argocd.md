# Lab 07 - Argo CD

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Kubernetes Platform |
| **Lab** | 07 |
| **Difficulty** | Advanced |
| **Estimated Time** | 45–75 minutes |
| **Estimated Cost** | Free |
| **Terraform** | No |
| **Kubernetes** | Yes |
| **GitOps** | Yes |

## Summary

This lab introduces ArgoCD as the GitOps deployment platform for Kubernetes.

ArgoCD continuously monitors Git repositories and automatically synchronizes the desired platform state with the Amazon EKS cluster. From this point onward, Git becomes the single source of truth for Kubernetes deployments.

## Purpose

The purpose of this lab is to implement a GitOps workflow where Kubernetes deployments are managed declaratively through Git repositories instead of manual commands.

By introducing ArgoCD, deployments become automated, auditable, repeatable and consistent across environments.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 06 completed
- Amazon EKS operational
- GitHub Actions operational
- Helm operational
- GitHub Container Registry operational
- `kubectl` points at the Development EKS cluster created in Lab 04

## Architecture

```text
                Developer
                     │
                 Git Push
                     │
             GitHub Repository
                     │
             GitHub Actions (CI)
                     │
       Docker Image Published (GHCR)
                     │
            Git Repository Updated
                     │
                 ArgoCD Server
                     │
            Desired State Reconciliation
                     │
              Amazon EKS Cluster
                     │
         Kubernetes Platform Services
```

## AWS Resources

No new AWS infrastructure is provisioned during this lab.

ArgoCD is deployed as a Kubernetes application inside the existing Amazon EKS cluster.

## Design Decisions

The platform follows modern GitOps best practices.

### Git as the Source of Truth

Git repositories define the desired state of the platform.

Manual changes to the Kubernetes cluster are not considered permanent.

### Declarative Deployments

Applications are deployed declaratively using Kubernetes manifests and Helm charts stored in Git.

### Continuous Reconciliation

ArgoCD continuously compares the desired state in Git with the actual state running inside Kubernetes.

### Self-Healing

When cluster resources drift from the desired state, ArgoCD automatically restores the correct configuration.

### Drift Detection

Configuration drift is detected automatically without requiring manual validation.

### Automatic Synchronization

Application changes are deployed automatically after they have been validated by the Continuous Integration pipeline.

### Helm Integration

ArgoCD uses Helm as the deployment engine for Kubernetes applications.

Helm remains the packaging solution while ArgoCD becomes the deployment orchestrator.

### Separation of Responsibilities

GitHub Actions is responsible for:

- Validation
- Testing
- Building artifacts

ArgoCD is responsible for:

- Deployment
- Synchronization
- Drift detection
- Self-healing

## Implementation Overview

This lab consists of the following high-level tasks.

1. Install ArgoCD using Helm
2. Configure ArgoCD
3. Expose the ArgoCD Web UI
4. Connect ArgoCD to GitHub
5. Create an ArgoCD Application
6. Configure automatic synchronization
7. Deploy the sample application
8. Verify synchronization
9. Test self-healing
10. Verify drift detection

## Outcome

Bootstrap Argo CD on the existing EKS cluster and let it reconcile the platform GitOps root application.

## Repository Changes

Primary implementation: `platform-config/bootstrap and platform-config/clusters/dev`.

## Files to Review

Review the GitOps bootstrap and cluster desired-state files. Update repository URLs and environment-specific values before validation.

Key files:

| File | Purpose |
|------|---------|
| `platform-config/bootstrap/root-application.yaml` | Root Argo CD Application that points at `platform-config/clusters/dev` |
| `platform-config/clusters/dev/argocd.yaml` | Child Application that lets Argo CD manage itself after bootstrap |
| `platform-config/clusters/dev/sample-api.yaml` | Child Application that deploys the sample API from `helm-charts` |
| `platform-config/clusters/dev/*.yaml` | Desired state for platform services introduced across later labs |

## Step-by-Step Implementation

1. Review `platform-config/bootstrap/root-application.yaml` and confirm the `repoURL`, `targetRevision` and `path` match your repositories and branch.
2. Review the current child Applications in `platform-config/clusters/dev` so you understand what Argo CD will reconcile.
3. Commit and push any required `platform-config` changes before bootstrapping Argo CD.
4. Install Argo CD into the existing EKS cluster.
5. Bootstrap the root Application from `platform-config/bootstrap/root-application.yaml`.
6. Verify that Argo CD creates child Applications and reports them as synced or progressing.
7. Use Argo CD status and controller logs to troubleshoot any repository or manifest errors.

The direct install/bootstrap commands below are only for bringing up Argo CD itself. After Argo CD is running, application and platform changes should flow through GitOps rather than manual `kubectl apply`, `helm install` or `helm upgrade` commands.

## Commands

```bash
cd "$WORKSPACE"

kubectl config current-context
kubectl get nodes

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --wait

kubectl -n argocd wait --for=condition=available deployment/argocd-server --timeout=300s
kubectl apply -f platform-config/bootstrap/root-application.yaml
```

## Expected Results

Argo CD is installed in the `argocd` namespace, the `platform-root` Application exists, and Argo CD begins reconciling the child Applications from `platform-config/clusters/dev`.

## Validation

### Argo CD verification

```bash
kubectl -n argocd get pods
kubectl -n argocd get applications.argoproj.io
kubectl -n argocd describe application platform-root
kubectl -n argocd get application platform-root \
  -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}{"\n"}'
kubectl -n argocd logs deployment/argocd-application-controller --since=10m
kubectl get events -A --sort-by=.lastTimestamp | tail -50
```

Pass criteria:

- Argo CD controller, repo-server and API server pods are ready.
- `platform-root` exists and can read the `platform-config` repository.
- Child Applications are created from `platform-config/clusters/dev`.
- Applications are either `Synced / Healthy` or clearly progressing toward the components introduced in later labs.
- Changing a harmless Git-managed annotation is reconciled into the cluster.
- Manually changing that annotation in-cluster is reverted by self-heal.
- Removing a Git-managed test resource removes it from the cluster when pruning is enabled.
- Controller logs contain no repository authentication, manifest-generation or comparison errors.

Do not test self-heal or pruning on production workloads; use a temporary test object.

## Troubleshooting

Start with Argo CD status:

```bash
kubectl -n argocd get pods
kubectl -n argocd get applications.argoproj.io -o wide
kubectl -n argocd describe application platform-root
kubectl -n argocd logs deployment/argocd-application-controller --since=10m
```

Common issues:

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `applications.argoproj.io` is unknown | Argo CD CRDs are not installed yet | Recheck the Helm install step and wait for Argo CD pods |
| `platform-root` cannot fetch manifests | Wrong `repoURL`, branch or repository visibility | Correct `platform-config/bootstrap/root-application.yaml`, commit and reapply the root Application |
| Child Applications are missing | Root Application did not sync or points at the wrong path | Confirm `path: clusters/dev` and inspect `platform-root` events |
| Application is `OutOfSync` | Desired state differs from cluster state | Review the diff in Argo CD or describe the Application |
| Application is `Degraded` | Rendered manifests failed or workloads are unhealthy | Inspect the Application events and affected Kubernetes resources |

## Commit and Push

Use a focused conventional commit such as `feat: complete lab 07`.

## Final Repository State

The implementation remains GitOps-driven and mergeable to `main`.

## Success Criteria

This lab is complete when:

- ArgoCD is operational.
- Git repositories are connected.
- Applications deploy automatically.
- Drift detection functions correctly.
- Self-healing restores modified resources.
- Git becomes the single source of truth for Kubernetes deployments.

## Best Practices

This lab follows GitOps best practices.

- Never modify production resources manually.
- Store all Kubernetes configuration in Git.
- Enable automatic synchronization.
- Enable self-healing.
- Review changes through Pull Requests.
- Keep applications declarative.
- Use Helm for packaging.

## Cleanup

No cleanup is required.

ArgoCD becomes the primary deployment platform for all remaining Kubernetes workloads.

## Lessons Learned

GitOps provides a declarative deployment model where Git defines the desired state of the platform.

By combining GitHub Actions, Helm and ArgoCD, the platform now has a modern deployment pipeline that separates validation from deployment while ensuring consistent, automated and auditable application delivery.

This establishes the operational foundation for the remaining platform services.

## References

- ArgoCD Documentation
- GitOps Principles
- Helm Documentation
- Kubernetes Documentation
- CNCF Argo Project

## Next Steps

Continue with [Lab 08 - Prometheus and Grafana](./lab08-prometheus-grafana.md).
