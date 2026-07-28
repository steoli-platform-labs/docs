# Lab 15 - Multi-Environment Platform

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Operations |
| **Lab** | 15 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 45-60 minutes |
| **Estimated Cost** | Low |
| **Primary Tools** | AWS CLI, Helm, kubectl, Argo CD |

## Introduction

This lab activates the platform's multi-environment GitOps layout.

Labs 01-14 build and validate the dev platform. Lab 15 adds staging and production desired state by using one root Argo CD Application per environment path. The roots are `platform-root-dev`, `platform-root-staging` and `platform-root-production`, and each root reconciles one `platform-config/clusters/<environment>` directory.

For cost and simplicity, this lab runs dev, staging and production in one shared EKS cluster using separate namespaces and Argo CD environment roots. In many production platforms, these environments would be separated further by using different EKS clusters, different AWS accounts, or both. The GitOps structure shown here still maps to that model: each environment root would point at the desired state for its own cluster instead of another namespace in the same cluster.

Concepts introduced in this lab include environment separation, namespace boundaries, environment root Applications, promotion, environment-specific desired state and Git history as an audit trail. See the [Concepts Reference](../concepts/README.md) for how multi-environment GitOps fits into the platform.

## Outcome

Activate staging and production as GitOps-managed environments in the same EKS cluster, while keeping dev resources managed by the dev root Application.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 14 completed
- AWS CLI, kubectl, Helm and yq installed
- Argo CD running in the dev cluster
- `sample-api:1.0.0` published to GHCR by Lab 06
- AWS credentials that can read and write the lab Secrets Manager secret values

## Files to Review

Review these files before activation:

- `platform-config/bootstrap/root-application-dev.yaml`: dev root Application for `clusters/dev`.
- `platform-config/bootstrap/root-application-staging.yaml`: staging root Application for `clusters/staging`.
- `platform-config/bootstrap/root-application-production.yaml`: production root Application for `clusters/production`.
- `platform-config/clusters/dev/platform-namespaces.yaml`: child Application that reconciles namespace desired state.
- `platform-config/clusters/dev/sample-api-dev.yaml`: dev sample API Application and values.
- `platform-config/clusters/staging/sample-api-staging.yaml`: staging sample API Application and values.
- `platform-config/clusters/production/sample-api-production.yaml`: production sample API Application and values.
- `platform-config/environments/namespaces.yaml`: namespace boundaries and environment labels.
- `helm-charts/charts/sample-api/values.yaml`: reusable chart defaults that environment-specific overrides build on.

## Step-by-Step Implementation

1. Review the environment roots and confirm each root points at one environment path:

   ```bash
   cd "$WORKSPACE/platform-config"

   yq '.metadata.name + " -> " + .spec.source.path' bootstrap/root-application-dev.yaml
   yq '.metadata.name + " -> " + .spec.source.path' bootstrap/root-application-staging.yaml
   yq '.metadata.name + " -> " + .spec.source.path' bootstrap/root-application-production.yaml
   ```

   Expected output:

   ```text
   platform-root-dev -> clusters/dev
   platform-root-staging -> clusters/staging
   platform-root-production -> clusters/production
   ```

   This separation makes Argo CD ownership explicit. A staging change is discovered by `platform-root-staging`, a production change is discovered by `platform-root-production`, and dev remains owned by `platform-root-dev`.

2. Review the namespace desired state and the child Application that applies it:

   ```bash
   yq '.' environments/namespaces.yaml
   yq '.spec.source.path' clusters/dev/platform-namespaces.yaml
   ```

   The namespace file defines `sample-api-dev`, `sample-api-staging` and `sample-api-production` with environment labels. The `platform-namespaces` child Application points Argo CD at the `environments` directory so the namespace layer is GitOps-managed instead of manually applied.

3. Review the sample API Applications for each environment:

   ```bash
   yq '.metadata.name + " -> " + .spec.destination.namespace' clusters/dev/sample-api-dev.yaml
   yq '.metadata.name + " -> " + .spec.destination.namespace' clusters/staging/sample-api-staging.yaml
   yq '.metadata.name + " -> " + .spec.destination.namespace' clusters/production/sample-api-production.yaml

   yq '.spec.source.helm.releaseName' clusters/dev/sample-api-dev.yaml
   yq '.spec.source.helm.releaseName' clusters/staging/sample-api-staging.yaml
   yq '.spec.source.helm.releaseName' clusters/production/sample-api-production.yaml

   yq '.spec.source.helm.values | from_yaml | {"environment": .environment, "replicaCount": .replicaCount, "autoscaling": .autoscaling, "secret": .secret}' clusters/dev/sample-api-dev.yaml
   yq '.spec.source.helm.values | from_yaml | {"environment": .environment, "replicaCount": .replicaCount, "autoscaling": .autoscaling, "secret": .secret}' clusters/staging/sample-api-staging.yaml
   yq '.spec.source.helm.values | from_yaml | {"environment": .environment, "replicaCount": .replicaCount, "autoscaling": .autoscaling, "secret": .secret}' clusters/production/sample-api-production.yaml
   ```

   Each Application points at the same reusable Helm chart but targets a different namespace and values block. The Applications keep `releaseName: sample-api` so the Kubernetes resource names stay stable in each namespace even though the Argo CD Application names are environment-scoped.

4. Create or update the external secret values required by staging and production:

   ```bash
   export AWS_PAGER=""
   export AWS_REGION="eu-north-1"

   aws secretsmanager create-secret \
     --name platform-labs/sample-api-staging \
     --secret-string '{"EXAMPLE_CONFIG":"staging"}' \
     --region "$AWS_REGION" || \
   aws secretsmanager put-secret-value \
     --secret-id platform-labs/sample-api-staging \
     --secret-string '{"EXAMPLE_CONFIG":"staging"}' \
     --region "$AWS_REGION"

   aws secretsmanager create-secret \
     --name platform-labs/sample-api-production \
     --secret-string '{"EXAMPLE_CONFIG":"production"}' \
     --region "$AWS_REGION" || \
   aws secretsmanager put-secret-value \
     --secret-id platform-labs/sample-api-production \
     --secret-string '{"EXAMPLE_CONFIG":"production"}' \
     --region "$AWS_REGION"
   ```

   The chart creates an `ExternalSecret` per environment. External Secrets Operator reads these paths from AWS Secrets Manager and writes Kubernetes Secrets into the target namespace.

5. Run local validation before Argo CD applies the new desired state:

   ```bash
   cd "$WORKSPACE"

   kubectl apply --dry-run=client -f platform-config/bootstrap/root-application-dev.yaml
   kubectl apply --dry-run=client -f platform-config/bootstrap/root-application-staging.yaml
   kubectl apply --dry-run=client -f platform-config/bootstrap/root-application-production.yaml
   kubectl apply --dry-run=client -f platform-config/environments/namespaces.yaml

   helm lint helm-charts/charts/sample-api
   helm template sample-api helm-charts/charts/sample-api \
     --namespace sample-api-dev \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/dev/sample-api-dev.yaml) >/dev/null
   helm template sample-api helm-charts/charts/sample-api \
     --namespace sample-api-staging \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/staging/sample-api-staging.yaml) >/dev/null
   helm template sample-api helm-charts/charts/sample-api \
     --namespace sample-api-production \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/production/sample-api-production.yaml) >/dev/null
   ```

   These checks confirm Kubernetes can parse the bootstrap manifests and the chart can render all three environment values blocks.

6. Apply the environment root Applications:

   ```bash
   cd "$WORKSPACE"

   kubectl apply -f platform-config/bootstrap/root-application-dev.yaml
   kubectl apply -f platform-config/bootstrap/root-application-staging.yaml
   kubectl apply -f platform-config/bootstrap/root-application-production.yaml
   ```

   Applying root Applications is a bootstrap exception to the GitOps rule. After these roots exist, Argo CD owns the child Applications and workloads.

7. Refresh and inspect all environment roots and sample API Applications:

    ```bash
    for app in platform-root-dev platform-root-staging platform-root-production; do
      kubectl -n argocd annotate application "$app" argocd.argoproj.io/refresh=hard --overwrite
    done

    kubectl -n argocd get application \
      platform-root-dev \
      platform-root-staging \
      platform-root-production \
      platform-namespaces \
      sample-api-dev \
      sample-api-staging \
      sample-api-production \
      -o wide
    ```

    Expected result: each root is `Synced / Healthy`, `platform-namespaces` is `Synced / Healthy`, and the three sample API Applications are created. Workload health depends on the public GHCR image, AWS secret values and cluster capacity being ready.

8. Validate namespace separation and workload state:

    ```bash
    kubectl get namespaces -L environment

    for ns in sample-api-dev sample-api-staging sample-api-production; do
      echo "===== $ns ====="
      kubectl -n "$ns" get rollout,svc,pod,externalsecret,networkpolicy,pdb
    done
    ```

    Each namespace should show its own sample API resources. If staging or production pods are pending, inspect the pod events before changing GitOps desired state.

9. Query each environment's API:

    ```bash
    for ns in sample-api-dev sample-api-staging sample-api-production; do
      echo "===== $ns ====="
      kubectl -n "$ns" port-forward svc/sample-api 8080:80 >/tmp/$ns-port-forward.log 2>&1 &
      PF_PID=$!
      sleep 2
      curl -fsS http://localhost:8080/health || true
      kill "$PF_PID"
    done
    ```

    In a completed multi-environment setup, each environment returns a healthy response from its own namespace.

## Expected Results

The cluster has GitOps-managed dev, staging and production sample API environments. Each environment has a root Application, a child workload Application, a namespace boundary and environment-specific Helm values.

## Validation

- `platform-root-dev`, `platform-root-staging` and `platform-root-production` exist in Argo CD.
- The root Applications point to `clusters/dev`, `clusters/staging` and `clusters/production` respectively.
- `platform-namespaces` applies the namespaces from `platform-config/environments`.
- `sample-api-dev`, `sample-api-staging` and `sample-api-production` exist and target separate namespaces.
- `kubectl get namespaces -L environment` shows `dev`, `staging` and `production` labels.
- Each sample API namespace contains its own rollout, Service, ExternalSecret, NetworkPolicy and PDB.
- Argo CD reports no repository authentication, manifest-generation or comparison errors.

## Troubleshooting

Start by confirming what Argo CD is configured to read:

```bash
cd "$WORKSPACE/platform-config"
yq '.metadata.name + " -> " + .spec.source.path' bootstrap/root-application-dev.yaml
yq '.metadata.name + " -> " + .spec.source.path' bootstrap/root-application-staging.yaml
yq '.metadata.name + " -> " + .spec.source.path' bootstrap/root-application-production.yaml
kubectl get namespaces -L environment
kubectl -n argocd get applications.argoproj.io -o wide
```

If staging or production Applications are missing:

- Confirm the corresponding root Application exists in `argocd`.
- Confirm the root points at the expected `clusters/<environment>` path.

If pods show `ImagePullBackOff`:

- Confirm `ghcr.io/steoli-platform-labs/sample-api:1.0.0` can be pulled without Docker login.
- Confirm the image tag in the affected Argo CD Application values matches a published reference image.

If an `ExternalSecret` is not ready:

- Confirm `ClusterSecretStore/aws-secrets-manager` is `Ready=True`.
- Confirm the environment-specific AWS Secrets Manager path exists.
- Confirm External Secrets Operator has AWS access through the workload identity configured in Lab 13.

## Final Repository State

The implementation remains GitOps-driven and mergeable to `main`. `platform-config` contains one root Application per environment and one sample API Application per environment.

## Cleanup

No cleanup is required. Keep staging and production only if you want the shared dev cluster to continue running all three lab environments.

## Next Steps

Continue with [Lab 16 - Progressive Delivery](./lab16-progressive-delivery.md).
