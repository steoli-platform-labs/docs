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

## Introduction

This lab introduces ArgoCD as the GitOps deployment platform for Kubernetes.

ArgoCD continuously monitors Git repositories and automatically synchronizes the desired platform state with the Amazon EKS cluster. From this point onward, Git becomes the single source of truth for Kubernetes deployments.

## Outcome

Bootstrap Argo CD on the existing EKS cluster and let it reconcile the platform GitOps root application.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 06 completed
- Amazon EKS operational
- GitHub Actions operational
- Helm installed and operational
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

- **Git as the source of truth:** Git repositories define the desired state of the platform. Manual changes to the Kubernetes cluster are not considered permanent.

- **Declarative deployments:** Applications are deployed declaratively using Kubernetes manifests and Helm charts stored in Git.

- **Continuous reconciliation:** ArgoCD continuously compares the desired state in Git with the actual state running inside Kubernetes.

- **Self-healing:** When cluster resources drift from the desired state, ArgoCD automatically restores the correct configuration.

- **Drift detection:** Configuration drift is detected automatically without requiring manual validation.

- **Automatic synchronization:** Application changes are deployed automatically after they have been validated by the Continuous Integration pipeline.

- **Helm integration:** ArgoCD uses Helm as the deployment engine for Kubernetes applications. Helm remains the packaging solution while ArgoCD becomes the deployment orchestrator.

- **Separation of responsibilities:** GitHub Actions is responsible for validation, testing and building artifacts. ArgoCD is responsible for deployment, synchronization, drift detection and self-healing.

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

1. Review `platform-config/bootstrap/root-application.yaml` and confirm that it points Argo CD at the correct Git source.

   This file is the first Argo CD `Application` you apply manually. It is called the root Application because it tells Argo CD where to find the rest of the platform desired state. After it is applied, Argo CD reads the Git repository and creates the child Applications from the configured path.

   Check these fields before continuing:

   - `metadata.name`: should be `platform-root`, which is the Application you will inspect later.
   - `metadata.namespace`: should be `argocd`, because the Argo CD controller watches Applications in that namespace.
   - `spec.source.repoURL`: must point to your `platform-config` repository.
   - `spec.source.targetRevision`: must point to the branch or tag Argo CD should read, usually `main` for these labs.
   - `spec.source.path`: must point to `clusters/dev`, where the Development cluster's child Applications live.
   - `spec.destination.server`: should be `https://kubernetes.default.svc`, which means the same cluster where Argo CD is running.
   - `spec.syncPolicy.automated.prune`: allows Argo CD to remove resources that were deleted from Git.
   - `spec.syncPolicy.automated.selfHeal`: allows Argo CD to correct manual in-cluster drift back to the Git-defined state.

   Run this from the workspace root to inspect the root Application:

   ```bash
   cd "$WORKSPACE"
   sed -n '1,120p' platform-config/bootstrap/root-application.yaml
   ```

   If your GitHub organization or branch differs from the committed example, update `repoURL` or `targetRevision`, then commit and push that `platform-config` change before applying the root Application.
2. Review the child Applications in `platform-config/clusters/dev` so you understand what Argo CD will reconcile after the root Application is created.

   Each YAML file in this directory is intended to become an Argo CD child Application for one platform component or workload. The root Application does not install those components directly; it points Argo CD at this directory, and Argo CD then reconciles each child Application it finds there.

   List the child Application files:

   ```bash
   find platform-config/clusters/dev -maxdepth 1 -type f -name '*.yaml' -print | sort
   ```

   Review the names, source paths and destinations:

   ```bash
   for file in platform-config/clusters/dev/*.yaml
   do
     echo "===== $file ====="
     grep -E 'name:|repoURL:|targetRevision:|path:|namespace:' "$file"
   done
   ```

   At this point, it is acceptable if some child Applications point to components introduced in later labs. The goal in this step is to verify that Argo CD will read the expected repository, branch and path, and that you understand which Applications may initially be `Progressing`, `OutOfSync` or `Unknown` until their lab-specific configuration is completed.

   Confirm the `sample-api` Application uses the image published in Lab 06:

   ```bash
   grep -A4 'image:' platform-config/clusters/dev/sample-api.yaml
   ```

   The Development lab path uses `ghcr.io/${GITHUB_ORG}/sample-api:latest` so the first GitOps deployment can follow the newest successful `main` build without editing the image tag manually. The package should remain private by default, so the Application also references an `imagePullSecrets` entry named `ghcr-pull`.

   Confirm the Application values include the pull secret reference:

   ```bash
   grep -A8 'image:' platform-config/clusters/dev/sample-api.yaml
   ```

   You can confirm public pull access from your workstation with:

   ```bash
   curl -fsS "https://ghcr.io/token?service=ghcr.io&scope=repository:${GITHUB_ORG}/sample-api:pull" \
     | python3 -m json.tool
   ```

   A `401 Unauthorized` response means the package is private from the cluster's point of view. That is expected for this lab if you create the pull secret in the next step.
3. Create the image pull secret that allows Kubernetes nodes to pull the private GHCR image.

   Use a GitHub token with only the permissions needed to read packages. Do not use a broad personal token unless your environment requires it. Do not commit the token value to Git.

   ```bash
   kubectl create namespace sample-api-dev --dry-run=client -o yaml | kubectl apply -f -

   export GITHUB_USER="<your-github-username>"
   read -r -s GHCR_READ_TOKEN

   kubectl -n sample-api-dev create secret docker-registry ghcr-pull \
     --docker-server=ghcr.io \
     --docker-username="$GITHUB_USER" \
     --docker-password="$GHCR_READ_TOKEN" \
     --dry-run=client -o yaml | kubectl apply -f -

   unset GHCR_READ_TOKEN
   ```

   Paste the token at the hidden prompt. Validate only the secret metadata, not the token value:

   ```bash
   kubectl -n sample-api-dev get secret ghcr-pull
   ```

   This secret is a bootstrap exception for Lab 07. Later labs replace ad hoc secret handling with External Secrets Operator and IRSA patterns.
4. Commit and push any required `platform-config` changes before bootstrapping Argo CD.
5. Confirm kubectl points at the intended EKS cluster and install Argo CD:

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
   ```

6. Bootstrap the root Application from `platform-config/bootstrap/root-application.yaml`:

   ```bash
   kubectl -n argocd wait --for=condition=available deployment/argocd-server --timeout=300s
   kubectl apply -f platform-config/bootstrap/root-application.yaml
   ```

7. Verify that Argo CD creates child Applications and reports the Lab 07 bootstrap resources as healthy:

   ```bash
   kubectl -n argocd get pods
   kubectl -n argocd get applications.argoproj.io
   kubectl -n argocd describe application platform-root
   kubectl -n argocd get application platform-root \
     -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}{"\n"}'
   kubectl -n argocd logs statefulset/argocd-application-controller --since=10m
   kubectl get events -A --sort-by=.lastTimestamp | tail -50
   ```

   The Argo CD application controller runs as a StatefulSet in the Helm chart used by this lab, so the log command targets `statefulset/argocd-application-controller`.

   For this lab, `platform-root` and `argocd` should be `Synced / Healthy`. Later-lab Applications may appear as `Progressing`, `OutOfSync` or `Unknown` until their dedicated labs provide the required values, CRDs, IAM roles, secrets or chart versions.

8. Use Argo CD status and controller logs to troubleshoot any repository or manifest errors.

   The direct install/bootstrap commands in this section are only for bringing up Argo CD itself. After Argo CD is running, application and platform changes should flow through GitOps rather than manual `kubectl apply`, `helm install` or `helm upgrade` commands.

## Expected Results

Argo CD is installed in the `argocd` namespace, the `platform-root` Application exists, Argo CD begins reconciling the child Applications from `platform-config/clusters/dev`, and the Lab 07 bootstrap resources are healthy.

## Validation

- Argo CD controller, repo-server and API server pods are ready.
- `platform-root` exists and can read the `platform-config` repository.
- Child Applications are created from `platform-config/clusters/dev`.
- `platform-root` and `argocd` are `Synced / Healthy`.
- `sample-api` is `Synced` and becomes healthy when `ghcr.io/<github-organization>/sample-api:latest` is published and the `ghcr-pull` image pull secret exists in `sample-api-dev`.
- If `sample-api` shows `ImagePullBackOff`, the image tag is missing, the `ghcr-pull` secret is missing, or the token cannot read the package.
- Later-lab Applications may be `Progressing`, `OutOfSync` or `Unknown` until their dedicated labs complete the required configuration.
- Changing a harmless Git-managed annotation is reconciled into the cluster.
- Manually changing that annotation in-cluster is reverted by self-heal.
- Removing a Git-managed test resource removes it from the cluster when pruning is enabled.
- Controller logs contain no repository authentication, manifest-generation or comparison errors.
- Do not test self-heal or pruning on production workloads; use a temporary test object.

## Troubleshooting

Start with Argo CD status:

```bash
kubectl -n argocd get pods
kubectl -n argocd get applications.argoproj.io -o wide
kubectl -n argocd describe application platform-root
kubectl -n argocd logs statefulset/argocd-application-controller --since=10m
```

If `sample-api` is not healthy, inspect the pod image-pull events directly:

```bash
kubectl -n sample-api-dev get pods
kubectl -n sample-api-dev describe pod -l app.kubernetes.io/name=sample-api
```

If the event says `failed to fetch anonymous token` or `401 Unauthorized`, Kubernetes did not use valid pull credentials. Confirm the secret exists and is referenced by the rendered workload:

```bash
kubectl -n sample-api-dev get secret ghcr-pull
kubectl -n sample-api-dev get rollout sample-api -o yaml | grep -A3 imagePullSecrets
```

If the secret is missing, recreate it with a least-privilege `read:packages` token. If the secret exists but pulls still fail, create a new token, update the secret and delete the stuck pods so Kubernetes retries the image pull.

Common issues:

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `applications.argoproj.io` is unknown | Argo CD CRDs are not installed yet | Recheck the Helm install step and wait for Argo CD pods |
| `platform-root` cannot fetch manifests | Wrong `repoURL`, branch or repository visibility | Correct `platform-config/bootstrap/root-application.yaml`, commit and reapply the root Application |
| Child Applications are missing | Root Application did not sync or points at the wrong path | Confirm `path: clusters/dev` and inspect `platform-root` events |
| Application is `OutOfSync` | Desired state differs from cluster state | Review the diff in Argo CD or describe the Application |
| Application is `Degraded` | Rendered manifests failed or workloads are unhealthy | Inspect the Application events and affected Kubernetes resources |
| `sample-api` pods show `ImagePullBackOff` | `latest` was not published, `ghcr-pull` is missing, or the token cannot read the package | Confirm Lab 06 CI published `latest`, recreate `ghcr-pull` with `read:packages`, then delete the stuck pods |

## Final Repository State

The implementation remains GitOps-driven and mergeable to `main`.

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

## References

- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [OpenGitOps Principles](https://opengitops.dev/)
- [Helm Documentation](https://helm.sh/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [CNCF Argo Project](https://www.cncf.io/projects/argo/)

## Next Steps

Continue with [Lab 08 - Prometheus and Grafana](./lab08-prometheus-grafana.md).
