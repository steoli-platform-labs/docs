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

## Introduction

This lab introduces IAM Roles for Service Accounts (IRSA), enabling Kubernetes workloads to authenticate securely with AWS services without using static credentials.

IRSA integrates Kubernetes service accounts with AWS IAM through the Amazon EKS OIDC identity provider, allowing workloads to obtain temporary AWS credentials automatically.

Concepts introduced in this lab include IAM roles, IAM policies, trust policies, Kubernetes service accounts, OIDC federation, AWS STS and temporary credentials. See the [Concepts Reference](../concepts/README.md) for how IRSA avoids static AWS keys in pods.

## Outcome

Implement and validate IRSA in the complete platform reference implementation.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 12 completed
- Amazon EKS operational
- OIDC provider configured
- AWS Secrets Manager operational
- AWS CLI, Terraform, kubectl and Helm installed, with repository URLs configured

The request flow for IRSA is:

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

The following AWS resources are introduced during this lab.

| Resource | Purpose |
|----------|---------|
| IAM Role | Workload identity |
| IAM Policy | Least privilege permissions |
| IAM Trust Policy | OIDC federation |
| AWS STS | Temporary credentials |

The platform follows AWS security best practices.

- **Workload identity:** Each Kubernetes workload authenticates using its own IAM role.

- **Least privilege:** Each IAM role grants only the permissions required by the associated workload.

- **OIDC federation:** Authentication is performed using the Amazon EKS OIDC provider.

- **Temporary credentials:** AWS STS issues temporary credentials automatically. No long-lived AWS access keys are stored in Kubernetes.

- **GitOps deployment:** All Kubernetes manifests are managed through ArgoCD. Terraform provisions the required IAM resources.

- **Platform migration:** Existing platform services, including External Secrets Operator and Karpenter, are migrated from static credentials to IRSA.

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

## Repository Changes

Primary implementation: Terraform IAM resources in `platform-live` and GitOps-managed Kubernetes service-account annotations in `platform-config` or Helm values.

## Files to Review

Review these files before validation:

- `platform-live/environments/dev`: Terraform composition and outputs for the EKS OIDC provider and IAM roles.
- `platform-modules`: reusable IAM or EKS module code if IRSA support is implemented there.
- `platform-config/clusters/dev/external-secrets.yaml` and `platform-config/clusters/dev/karpenter.yaml`: GitOps Applications for AWS-integrated controllers.
- Helm values or Kubernetes manifests that render service accounts for External Secrets Operator, Karpenter and other AWS-integrated workloads.

## Step-by-Step Implementation

1. Confirm the EKS cluster has an OIDC issuer:

   ```bash
   cd "$WORKSPACE/platform-live/environments/dev"
   terraform output
   aws eks describe-cluster --name <cluster-name> \
     --query 'cluster.identity.oidc.issuer' \
     --output text
   ```

   IRSA requires the EKS OIDC issuer. If the output is empty or the IAM OIDC provider has not been created, create that infrastructure before annotating service accounts.

2. Identify which workloads need AWS permissions:

   ```bash
   kubectl -n external-secrets get serviceaccount external-secrets -o yaml
   kubectl -n karpenter get serviceaccount karpenter -o yaml
   ```

   External Secrets needs permission to read selected AWS Secrets Manager paths. Karpenter needs permission to provision and manage EC2 capacity. These should be separate IAM roles.

3. Review Terraform for IAM roles, trust policies and policies:

   ```bash
   cd "$WORKSPACE"
   grep -R "AssumeRoleWithWebIdentity\|oidc\|sts.amazonaws.com\|eks.amazonaws.com/role-arn" -n \
     platform-live platform-modules || true
   ```

   Confirm each trust policy restricts `sub` to the exact Kubernetes namespace and service account, such as `system:serviceaccount:external-secrets:external-secrets`.

4. Apply Terraform changes first if IAM roles or trust policies changed. Before applying, run the Terraform validation checks:

   ```bash
   terraform -chdir=platform-modules fmt -recursive
   terraform -chdir=platform-live fmt -recursive
   terraform -chdir=platform-live/environments/dev validate
   ```

   Then apply from the live environment only after reviewing the plan:

   ```bash
   terraform -chdir=platform-live/environments/dev plan
   terraform -chdir=platform-live/environments/dev apply
   ```

   Terraform must create IAM roles before Kubernetes workloads are configured to use them.

5. Review and add service-account annotations in GitOps-managed desired state:

   ```bash
   grep -R "eks.amazonaws.com/role-arn" -n platform-config helm-charts || true
   ```

   The annotation format is:

   ```yaml
   eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/<role-name>
   ```

   Add annotations through Helm values or service-account manifests, not by manually patching live service accounts.

6. Commit and push GitOps annotation changes after the IAM roles exist:

   ```bash
   cd "$WORKSPACE/platform-config"
   git status --short
   git add clusters/dev/external-secrets.yaml clusters/dev/karpenter.yaml addons/external-secrets/cluster-secret-store.yaml
   git commit -m "feat: configure irsa service accounts"
   git push
   ```

   If annotations were added in different GitOps or Helm values files, stage those actual paths instead. Skip the commit if there are no changed files.

7. Refresh the root Argo CD Application and reconcile affected Applications:

   ```bash
   kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get applications.argoproj.io -o wide
   ```

   If only specific apps changed, refresh those apps too, such as `external-secrets` or `karpenter`.

8. Validate that pods use the annotated service accounts:

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

9. Inspect the role trust policy and permissions:

   ```bash
   aws iam get-role --role-name <role-name>
   aws iam list-attached-role-policies --role-name <role-name>
   aws iam list-role-policies --role-name <role-name>
   ```

   Confirm permissions are narrow and the trust policy does not allow arbitrary service accounts.

10. Validate AWS access through controller behavior:

   ```bash
   kubectl -n external-secrets logs deployment/external-secrets --since=10m --tail=200
   kubectl -n karpenter logs deployment/karpenter --since=10m --tail=200
   ```

   Successful validation means controllers can call only the AWS APIs they require without static credentials. Look specifically for absence of `AccessDenied`, `NoCredentialProviders` and web identity errors.

## Expected Results

IAM roles, trust policies and service-account annotations are present before workloads rely on AWS APIs.

## Validation

- The EKS cluster has an IAM OIDC provider.
- Each controller pod uses the annotated service account.
- Trust policies restrict `sub` to the exact namespace and service-account name and restrict `aud` to `sts.amazonaws.com`.
- External Secrets can read only the intended secret path.
- Karpenter has only the permissions required for node provisioning.
- Controller logs show no `AccessDenied`, credential-provider or web-identity errors.
- Removing the annotation from a temporary test deployment causes AWS access to fail, proving credentials are not inherited from node roles.
- An OIDC output alone is not an IRSA implementation; IAM roles, trust policies and service-account annotations must all exist.

## Troubleshooting

Start with the service account, pod identity and controller logs:

```bash
kubectl -n external-secrets describe serviceaccount external-secrets
kubectl -n karpenter describe serviceaccount karpenter
kubectl -n external-secrets logs deployment/external-secrets --since=10m --tail=200
kubectl -n karpenter logs deployment/karpenter --since=10m --tail=200
```

If a controller reports `AccessDenied`:

- Confirm the pod uses the expected service account.
- Confirm the service account has the exact role ARN annotation.
- Confirm the IAM trust policy `sub` matches the namespace and service-account name.
- Confirm the IAM policy allows the specific AWS action and resource.

If a controller reports missing credentials:

- Confirm the EKS OIDC provider exists in IAM.
- Confirm the pod was restarted after the annotation was applied.
- Confirm no static credentials are masking or conflicting with IRSA.

## Final Repository State

The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup

No cleanup is required. IRSA becomes the platform's standard authentication mechanism for AWS access. Keep one IAM role per workload, avoid wildcard permissions, never use static AWS credentials and audit IAM roles regularly.

## Next Steps

Continue with [Lab 14 - Network Policies](./lab14-network-policies.md).
