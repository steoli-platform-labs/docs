# Lab 07 - Argo CD

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Kubernetes Platform |
| **Lab** | 07 |
| **Difficulty** | Advanced |
| **Estimated Time** | 45–75 minutes |
| **Estimated Cost** | Free |
| **Primary Tools** | Helm, kubectl, Argo CD |

## Introduction

This lab introduces ArgoCD as the GitOps deployment platform for Kubernetes.

ArgoCD continuously monitors Git repositories and automatically synchronizes the desired platform state with the Amazon EKS cluster. From this point onward, Git becomes the single source of truth for Kubernetes deployments.

Concepts introduced in this lab include GitOps, Argo CD Applications, app-of-apps, desired state, actual state, reconciliation, sync status, health status, drift, self-heal and pruning. See the [Concepts Reference](../concepts/README.md) for the meaning of each term, including when to refresh `platform-root-dev` versus a child Application.

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

## Files to Review

Review the GitOps bootstrap and cluster desired-state files. Update repository URLs and environment-specific values before validation.

Key files:

| File | Purpose |
|------|---------|
| `platform-config/bootstrap/root-application-dev.yaml` | Dev root Argo CD Application that points at `platform-config/clusters/dev` |
| `platform-config/clusters/dev/argocd.yaml` | Child Application that lets Argo CD manage itself after bootstrap |
| `platform-config/clusters/dev/sample-api-dev.yaml` | Child Application that deploys the dev sample API from `helm-charts` |
| `platform-config/clusters/dev/*.yaml` | Desired state for platform services introduced across later labs |

## Step-by-Step Implementation

1. Review `platform-config/bootstrap/root-application-dev.yaml` and confirm that it points Argo CD at the correct Git source.

   This file is the first Argo CD `Application` you apply manually. It is called the root Application because it tells Argo CD where to find the rest of the platform desired state. After it is applied, Argo CD reads the Git repository and creates the child Applications from the configured path.

   Check these fields before continuing:

   - `metadata.name`: should be `platform-root-dev`, which is the Application you will inspect later.
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
   sed -n '1,120p' platform-config/bootstrap/root-application-dev.yaml
   ```

   In reference/demo mode, use the committed repository URL and branch as-is. No repository update is required for this lab.
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
     printf '\n===== %s =====\n' "$file"
     grep -E 'name:|repoURL:|targetRevision:|path:|namespace:' "$file"
   done
   ```

   At this point, it is acceptable if some child Applications point to components introduced in later labs. The goal in this step is to verify that Argo CD will read the expected repository, branch and path, and that you understand which Applications may initially be `Progressing`, `OutOfSync` or `Unknown` until their lab-specific configuration is completed.

   Confirm the `sample-api-dev` Application uses the image published in Lab 06:

   ```bash
   grep -A4 'image:' platform-config/clusters/dev/sample-api-dev.yaml
   ```

   The Development lab path uses `ghcr.io/${GITHUB_ORG}/sample-api:1.0.0`, the public release image tag published in Lab 06. No image pull secret is required for the reference image.

   Real platforms often keep application images private. In that case, each workload namespace needs a registry credential secret, and the Helm values should set `imagePullSecrets` to reference that secret name. The reference lab does not require this because the published `sample-api` package is public.

3. Confirm kubectl points at the intended EKS cluster, compare the Argo CD chart version and install Argo CD:

   ```bash
   cd "$WORKSPACE"

   printf '\n===== Current kubectl context =====\n'
   kubectl config current-context

   printf '\n===== Cluster nodes =====\n'
   kubectl get nodes

   printf '\n===== Configured Argo CD chart version =====\n'
   yq -r '.spec.source.targetRevision' platform-config/clusters/dev/argocd.yaml

   printf '\n===== Latest available Argo CD chart version =====\n'
   helm show chart argo-cd --repo https://argoproj.github.io/argo-helm | yq '.version'

   printf '\n===== Install or upgrade Argo CD =====\n'
   helm repo add argo https://argoproj.github.io/argo-helm
   helm repo update
   helm upgrade --install argocd argo/argo-cd \
      --version "$(yq -r '.spec.source.targetRevision' platform-config/clusters/dev/argocd.yaml)" \
      --namespace argocd \
      --create-namespace \
      --wait
   ```

   The pinned version in `platform-config/clusters/dev/argocd.yaml` is the version tested by this lab. Newer chart versions may exist by the time you run the lab. Do not change the pinned version just because a newer version is available; Helm charts can change required values between releases.

   Continue only when `kubectl get nodes` shows `Ready` nodes and the Helm install or upgrade completes successfully. If Helm times out, inspect `kubectl -n argocd get pods` before retrying; partially created pods usually explain whether the issue is scheduling, image pull or readiness.

4. Bootstrap the dev root Application from `platform-config/bootstrap/root-application-dev.yaml`:

   ```bash
   printf '\n===== Wait for Argo CD server =====\n'
   kubectl -n argocd wait --for=condition=available deployment/argocd-server --timeout=300s
   printf '\n===== Apply dev root Application =====\n'
   kubectl apply -f platform-config/bootstrap/root-application-dev.yaml
   ```

   `kubectl wait` makes sure the Argo CD API server is ready to accept work. Applying the root Application is the bootstrap handoff: after this object exists, Argo CD reads Git and creates the child Applications for the platform.

5. Verify that Argo CD creates child Applications and reports the Lab 07 bootstrap resources as healthy:

   ```bash
   printf '\n===== Argo CD pods =====\n'
   kubectl -n argocd get pods

   printf '\n===== Argo CD Applications =====\n'
   kubectl -n argocd get applications.argoproj.io

   printf '\n===== platform-root-dev details =====\n'
   kubectl -n argocd describe application platform-root-dev

   printf '\n===== platform-root-dev status =====\n'
   kubectl -n argocd get application platform-root-dev \
     -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}{"\n"}'

   printf '\n===== Argo CD application controller logs =====\n'
   kubectl -n argocd logs statefulset/argocd-application-controller --since=10m

   printf '\n===== Recent cluster events =====\n'
   kubectl get events -A --sort-by=.lastTimestamp | tail -50
   ```

   The Argo CD application controller runs as a StatefulSet in the Helm chart used by this lab, so the log command targets `statefulset/argocd-application-controller`.

   For this lab, `platform-root-dev` and `argocd` should be `Synced / Healthy`. Later-lab Applications may appear as `Progressing`, `OutOfSync` or `Unknown` until their dedicated labs provide the required values, CRDs, IAM roles, secrets or chart versions.

   Treat `platform-root-dev` or `argocd` being `Degraded` as a stop condition. Treat later-lab Applications as informational unless their errors block Argo CD itself or the `sample-api-dev` Application used in the next labs.

6. Access the Argo CD UI and inspect the same Applications visually.

   Get the initial admin password:

   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret \
     -o jsonpath='{.data.password}' | base64 --decode; printf '\n'
   ```

   Start a local port-forward in a separate terminal:

   ```bash
   kubectl -n argocd port-forward svc/argocd-server 8080:80
   ```

   Open `http://localhost:8080`, log in with username `admin` and the password from the secret, then inspect `platform-root-dev`, `argocd` and `sample-api-dev`.

   The `jsonpath` command extracts only the password field from the Kubernetes Secret, and `base64 --decode` turns Kubernetes' stored representation back into readable text. The port-forward gives browser access from your laptop without exposing Argo CD publicly on the internet.

   Use the UI to confirm the application tree, sync status, health status, rendered resources and any diffs. This lab uses local port-forwarding only; do not expose the Argo CD server publicly without an approved access pattern such as SSO, VPN or an internal ingress.

7. Use Argo CD status, the UI and controller logs to troubleshoot any repository or manifest errors.

   The direct install/bootstrap commands in this section are only for bringing up Argo CD itself. After Argo CD is running, application and platform changes should flow through GitOps rather than manual `kubectl apply`, `helm install` or `helm upgrade` commands.

## Expected Results

Argo CD is installed in the `argocd` namespace, the `platform-root-dev` Application exists, Argo CD begins reconciling the child Applications from `platform-config/clusters/dev`, the Lab 07 bootstrap resources are healthy and the UI is reachable through local port-forwarding.

## Validation

- Argo CD controller, repo-server and API server pods are ready.
- `platform-root-dev` exists and can read the `platform-config` repository.
- Child Applications are created from `platform-config/clusters/dev`.
- `platform-root-dev` and `argocd` are `Synced / Healthy`.
- `sample-api-dev` is `Synced` and becomes healthy when `ghcr.io/<github-organization>/sample-api:1.0.0` is published and publicly pullable.
- If `sample-api-dev` shows `ImagePullBackOff`, the image tag is missing or the package is no longer public.
- Later-lab Applications may be `Progressing`, `OutOfSync` or `Unknown` until their dedicated labs complete the required configuration.
- The Argo CD UI is reachable through local port-forwarding and shows the same Application statuses as `kubectl`.
- Controller logs contain no repository authentication, manifest-generation or comparison errors.

## Troubleshooting

Start with Argo CD status:

```bash
printf '\n===== Argo CD pods =====\n'
kubectl -n argocd get pods
printf '\n===== Argo CD Applications =====\n'
kubectl -n argocd get applications.argoproj.io -o wide
printf '\n===== platform-root-dev details =====\n'
kubectl -n argocd describe application platform-root-dev
printf '\n===== Argo CD application controller logs =====\n'
kubectl -n argocd logs statefulset/argocd-application-controller --since=10m
```

If `sample-api-dev` is not healthy, inspect the pod image-pull events directly:

```bash
printf '\n===== sample-api-dev pods =====\n'
kubectl -n sample-api-dev get pods
printf '\n===== sample-api-dev pod details =====\n'
kubectl -n sample-api-dev describe pod -l app.kubernetes.io/name=sample-api
```

If the event says `failed to fetch anonymous token` or `401 Unauthorized`, the reference package may no longer be public. Confirm `ghcr.io/steoli-platform-labs/sample-api:1.0.0` can be pulled without Docker login.

Common issues:

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `applications.argoproj.io` is unknown | Argo CD CRDs are not installed yet | Recheck the Helm install step and wait for Argo CD pods |
| `platform-root-dev` cannot fetch manifests | Wrong `repoURL`, branch or repository visibility | Correct `platform-config/bootstrap/root-application-dev.yaml`, commit and reapply the root Application |
| Child Applications are missing | Root Application did not sync or points at the wrong path | Confirm `path: clusters/dev` and inspect `platform-root-dev` events |
| Application is `OutOfSync` | Desired state differs from cluster state | Review the diff in Argo CD or describe the Application |
| Application is `Degraded` | Rendered manifests failed or workloads are unhealthy | Inspect the Application events and affected Kubernetes resources |
| `sample-api` pods show `ImagePullBackOff` | `1.0.0` was not published or the package is not publicly pullable | Confirm Lab 06 published `1.0.0` and `docker pull ghcr.io/steoli-platform-labs/sample-api:1.0.0` works without login |

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
