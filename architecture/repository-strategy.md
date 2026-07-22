# Repository Strategy

## GitHub Organization

The intended GitHub organization is `steoli-platform-labs`.

## Repository Responsibilities

| Repository | Responsibility | Must Not Contain |
|------------|----------------|------------------|
| platform-bootstrap | Terraform state bootstrap resources | EKS workloads |
| platform-modules | Reusable Terraform modules | Environment-specific values |
| platform-live | Environment compositions and AWS deployments | Application source code |
| platform-config | ArgoCD applications and Kubernetes desired state | Terraform state |
| helm-charts | Custom Helm charts | Environment credentials |
| sample-api | Reference application and CI | Cluster deployment commands |
| docs | Architecture and labs | Secrets or generated state |
| .github | Public organization profile | Platform implementation code or secrets |

## Change Flow

Infrastructure changes flow from module development to environment composition. Application changes flow from source code to image publication and then to a GitOps configuration update.

```text
Infrastructure:
platform-modules -> platform-live -> Terraform -> AWS

Application:
sample-api -> GitHub Actions -> GHCR -> platform-config -> ArgoCD -> EKS
```

## Branching

The initial project uses trunk-based development:

- `main` is protected.
- Changes are proposed through pull requests.
- Pull requests require validation checks.
- Direct commits to `main` should be disabled once automation is available.
