# Security Model

## Principles

- Apply least privilege.
- Prefer short-lived credentials.
- Do not store secrets in Git.
- Use IAM roles for AWS access from Kubernetes.
- Use AWS Secrets Manager as the external secret source.
- Apply default-deny network policies where supported.
- Separate human, automation and workload identities.

## Identity Layers

| Identity | Mechanism |
|----------|-----------|
| Human AWS access | AWS IAM Identity Center or short-lived AWS credentials |
| Terraform automation | Dedicated IAM role with scoped permissions |
| GitHub Actions | OpenID Connect federation where introduced |
| Kubernetes workloads | IAM Roles for Service Accounts |
| GitOps reconciliation | Kubernetes RBAC and repository credentials |

## Secret Handling

Secrets must never be committed to Git. Kubernetes secrets are synchronized from AWS Secrets Manager by External Secrets Operator. Local `.env`, credential and Terraform variable files containing sensitive values must be ignored by Git.
