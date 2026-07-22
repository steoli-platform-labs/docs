# Lab 13 - IRSA

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Security |
| **Lab** | 13 |
| **Difficulty** | Advanced |
| **Estimated Time** | 45–75 minutes |
| **Estimated Cost** | Low |
| **Terraform** | Yes |
| **Kubernetes** | Yes |
| **GitOps** | Yes |

## Summary

This lab introduces IAM Roles for Service Accounts (IRSA), enabling Kubernetes workloads to authenticate securely with AWS services without using static credentials.

IRSA integrates Kubernetes service accounts with AWS IAM through the Amazon EKS OIDC identity provider, allowing workloads to obtain temporary AWS credentials automatically.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 12 completed
- Amazon EKS operational
- OIDC provider configured
- AWS Secrets Manager operational
- AWS CLI, Terraform, kubectl, Helm and repository URLs configured

## Architecture

```text
           Kubernetes Pod
                  │
          Service Account
                  │
           IAM Role (IRSA)
                  │
        AssumeRoleWithWebIdentity
                  │
              AWS STS
                  │
      Temporary AWS Credentials
                  │
         AWS Service Access
```

## AWS Resources

The following AWS resources are introduced during this lab.

| Resource | Purpose |
|----------|---------|
| IAM Role | Workload identity |
| IAM Policy | Least privilege permissions |
| IAM Trust Policy | OIDC federation |
| AWS STS | Temporary credentials |

## Design Decisions

The platform follows AWS security best practices.

### Workload Identity

Each Kubernetes workload authenticates using its own IAM role.

### Least Privilege

Each IAM role grants only the permissions required by the associated workload.

### OIDC Federation

Authentication is performed using the Amazon EKS OIDC provider.

### Temporary Credentials

AWS STS issues temporary credentials automatically.

No long-lived AWS access keys are stored in Kubernetes.

### GitOps Deployment

All Kubernetes manifests are managed through ArgoCD.

Terraform provisions the required IAM resources.

### Platform Migration

Existing platform services are migrated from static credentials to IRSA.

This includes:

- External Secrets Operator
- Karpenter

## Implementation Overview

This lab consists of the following high-level tasks.

1. Verify the EKS OIDC provider
2. Create IAM roles using Terraform
3. Create IAM policies
4. Configure trust relationships
5. Update Kubernetes Service Accounts
6. Migrate External Secrets Operator
7. Migrate Karpenter
8. Verify AWS authentication
9. Remove static credentials

## Outcome

Implement and validate IRSA in the complete platform reference implementation.

## Repository Changes

Primary implementation: `EKS OIDC output and service-account annotations`.

## Files to Review

Review the IRSA Terraform and GitOps files and update any environment-specific values before validation.

## Step-by-Step Implementation

1. Review the Terraform outputs for the EKS OIDC provider and any workload IAM roles used by platform controllers.
2. Review the service-account annotations in GitOps-managed manifests.
3. Apply Terraform changes first if IAM roles or trust policies changed.
4. Commit and push GitOps annotation changes after the IAM roles exist.
5. Let Argo CD reconcile affected Applications and validate that pods use the annotated service accounts.

## Commands

```bash
cd "$WORKSPACE"
terraform -chdir=platform-modules fmt -recursive
terraform -chdir=platform-live fmt -recursive
terraform -chdir=platform-live/environments/dev validate
kubectl -n argocd get applications.argoproj.io -o wide
```

## Expected Results

IAM roles, trust policies and service-account annotations are present before workloads rely on AWS APIs.

## Validation

### IRSA verification

```bash
kubectl -n external-secrets get serviceaccount external-secrets -o yaml
kubectl -n karpenter get serviceaccount karpenter -o yaml
kubectl -n external-secrets get pod -l app.kubernetes.io/name=external-secrets \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.serviceAccountName}{"\n"}{end}'
kubectl -n karpenter get pod -l app.kubernetes.io/name=karpenter \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.serviceAccountName}{"\n"}{end}'
```

Verify each service account contains the expected annotation:

```text
eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/<role-name>
```

Inspect the role trust policy and permissions:

```bash
aws iam get-role --role-name <role-name>
aws iam list-attached-role-policies --role-name <role-name>
aws iam list-role-policies --role-name <role-name>
```

Pass criteria:

- The EKS cluster has an IAM OIDC provider.
- Each controller pod uses the annotated service account.
- Trust policies restrict `sub` to the exact namespace and service-account name and restrict `aud` to `sts.amazonaws.com`.
- External Secrets can read only the intended secret path.
- Karpenter has only the permissions required for node provisioning.
- Controller logs show no `AccessDenied`, credential-provider or web-identity errors.
- Removing the annotation from a temporary test deployment causes AWS access to fail, proving credentials are not inherited from node roles.

An OIDC output alone is not an IRSA implementation; IAM roles, trust policies and service-account annotations must all exist.

## Troubleshooting

Start with the service account, pod identity and controller logs:

```bash
kubectl -n external-secrets describe serviceaccount external-secrets
kubectl -n karpenter describe serviceaccount karpenter
kubectl -n external-secrets logs deployment/external-secrets --since=10m --tail=200
kubectl -n karpenter logs deployment/karpenter --since=10m --tail=200
```

## Commit and Push

Use a focused conventional commit such as `feat: complete lab 13`.

## Final Repository State

The implementation remains GitOps-driven and mergeable to `main`.

## Success Criteria

This lab is complete when:

- Kubernetes workloads authenticate using IRSA.
- AWS STS issues temporary credentials.
- External Secrets Operator uses IRSA.
- Karpenter uses IRSA.
- Static AWS credentials have been eliminated.

## Best Practices

This lab follows AWS identity best practices.

- Use one IAM role per workload.
- Follow the Principle of Least Privilege.
- Avoid wildcard permissions.
- Never use static AWS credentials.
- Audit IAM roles regularly.

## Cleanup

No cleanup is required.

IRSA becomes the platform's standard authentication mechanism for AWS access.

## Lessons Learned

IAM Roles for Service Accounts eliminate the need for static AWS credentials in Kubernetes.

By combining OIDC federation, IAM and AWS STS, the platform achieves secure, scalable and production-ready workload authentication aligned with AWS best practices.

## References

- Amazon EKS IAM Roles for Service Accounts
- AWS STS Documentation
- Amazon EKS Best Practices Guide
- Kubernetes Service Accounts
- AWS IAM Documentation

## Next Steps

Continue with [Lab 14 - Network Policies](./lab14-network-policies.md).
