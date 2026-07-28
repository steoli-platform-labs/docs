# Lab 13 - Workload Identity

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Security |
| **Lab** | 13 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-45 minutes |
| **Estimated Cost** | Low |
| **Primary Tools** | AWS CLI, Terraform, kubectl |

## Introduction

This lab introduces IAM Roles for Service Accounts (IRSA), the OIDC-based pattern for letting Kubernetes workloads authenticate to AWS without static credentials.

The current platform already uses workload identity for AWS-integrated controllers. Karpenter and External Secrets Operator use EKS Pod Identity from earlier labs. This lab validates that foundation and explains how IRSA differs when a workload needs the `eks.amazonaws.com/role-arn` service-account annotation pattern.

Concepts introduced in this lab include IAM roles, IAM policies, trust policies, Kubernetes service accounts, OIDC federation, AWS STS and temporary credentials. See the [Concepts Reference](../concepts/README.md) for how IRSA avoids static AWS keys in pods.

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

Important AWS resources in this pattern are:

| Resource | Purpose |
|----------|---------|
| IAM Role | Workload identity |
| IAM Policy | Least privilege permissions |
| IAM Trust Policy | OIDC federation |
| AWS STS | Temporary credentials |

The platform follows these security practices:

- **Workload identity:** Each Kubernetes workload authenticates using its own IAM role.

- **Least privilege:** Each IAM role grants only the permissions required by the associated workload.

- **OIDC federation:** Authentication is performed using the Amazon EKS OIDC provider.

- **Temporary credentials:** AWS STS issues temporary credentials automatically. No long-lived AWS access keys are stored in Kubernetes.

- **GitOps deployment:** Kubernetes manifests are managed through Argo CD. Terraform provisions IAM resources.

- **Workload identity per controller:** Karpenter and External Secrets Operator use separate IAM roles with separate permissions.

## Outcome

Validate the platform workload identity foundation and understand where IRSA service-account annotations fit when a workload needs OIDC-based AWS access.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 12 completed.
- `kubectl` points at the Development EKS cluster.
- Argo CD and the GitOps root Application are operational.
- The Development Terraform environment has been applied from the current repositories.
- External Secrets Operator and Karpenter are already healthy from earlier labs.
- AWS CLI, Terraform, kubectl and Helm are installed, with repository URLs configured.

## Files to Review

Review these files before validation:

- `platform-live/environments/dev`: Terraform outputs for the EKS cluster, OIDC provider and controller IAM roles.
- `platform-modules/modules/eks/karpenter.tf`: Karpenter IAM role and EKS Pod Identity association.
- `platform-modules/modules/eks/external-secrets.tf`: External Secrets IAM role and EKS Pod Identity association.
- `platform-config/clusters/dev/external-secrets.yaml` and `platform-config/clusters/dev/karpenter.yaml`: GitOps Applications for AWS-integrated controllers.

## Step-by-Step Implementation

1. Confirm the EKS cluster has an OIDC issuer and matching IAM OIDC provider:

   ```bash
   cd "$WORKSPACE/platform-live/environments/dev"
   export AWS_PAGER=""

   CLUSTER_NAME=$(terraform output -raw cluster_name)

   OIDC_ISSUER=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
     --query 'cluster.identity.oidc.issuer' \
     --output text)
   OIDC_PROVIDER_HOSTPATH=${OIDC_ISSUER#https://}

   printf 'OIDC issuer: %s\n' "$OIDC_ISSUER"
   aws iam list-open-id-connect-providers \
     --query "OpenIDConnectProviderList[?contains(Arn, '$OIDC_PROVIDER_HOSTPATH')].Arn" \
     --output text
   ```

   `terraform output -raw cluster_name` reads the actual EKS cluster name created in the dev environment. IRSA requires both the EKS OIDC issuer URL and a matching IAM OIDC provider. If either output is empty, stop and reconcile the Development Terraform environment before continuing.

2. Inspect the existing AWS-integrated controller service accounts:

   ```bash
   printf '\n===== External Secrets service account =====\n'
   kubectl -n external-secrets get serviceaccount external-secrets -o yaml
   printf '\n===== Karpenter service account =====\n'
   kubectl -n karpenter get serviceaccount karpenter -o yaml
   ```

   These service accounts are intentionally not annotated with `eks.amazonaws.com/role-arn` because these controllers use EKS Pod Identity, not IRSA annotations.

3. Confirm the EKS Pod Identity associations created by earlier labs:

   ```bash
   aws eks list-pod-identity-associations \
     --cluster-name "$CLUSTER_NAME" \
     --query 'associations[].{namespace:namespace,serviceAccount:serviceAccount,associationArn:associationArn}' \
     --output table
   ```

   Expected result: associations exist for `karpenter/karpenter` and `external-secrets/external-secrets`. These associations bind the Kubernetes service accounts to IAM roles without storing AWS keys in Kubernetes.

4. Review the Terraform-managed IAM roles and policies:

   ```bash
   cd "$WORKSPACE"

   printf '\n===== Karpenter controller role ARN =====\n'
   terraform -chdir=platform-live/environments/dev output karpenter_controller_role_arn
   printf '\n===== External Secrets role ARN =====\n'
   terraform -chdir=platform-live/environments/dev output external_secrets_role_arn

   printf '\n===== Terraform workload identity resources =====\n'
   grep -R "aws_eks_pod_identity_association\|secretsmanager:GetSecretValue\|ec2:RunInstances" -n \
     platform-modules/modules/eks
   ```

   Confirm External Secrets can read only the lab secret path and Karpenter has the EC2 permissions needed for node provisioning. IAM permissions belong in Terraform, not in Kubernetes manifests.

5. Review the IRSA annotation pattern for workloads that need it:

   ```bash
   cd "$WORKSPACE"

   grep -R "eks.amazonaws.com/role-arn" -n platform-config helm-charts || true
   ```

   No output is expected in the current platform. Karpenter and External Secrets Operator already have AWS access, but they use EKS Pod Identity associations created by Terraform instead of IRSA service-account annotations in Kubernetes YAML.

   This check is still useful because it shows where an IRSA-based workload would declare its IAM role if the platform used that pattern for a future controller or application. With IRSA, the Kubernetes service account carries an annotation that points to an IAM role. AWS STS then exchanges the projected service-account token for temporary AWS credentials scoped to that role.

   The annotation format is:

   ```yaml
   eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/<role-name>
   ```

   If a future workload uses IRSA instead of EKS Pod Identity, add this annotation through Helm values or a GitOps-managed service account manifest. The IAM role, IAM policy and OIDC trust relationship still belong in Terraform. Do not manually patch live service accounts, because Argo CD would not have that change in desired state.

6. Validate that controller pods use the expected service accounts and AWS access works:

   ```bash
   printf '\n===== External Secrets pod service accounts =====\n'
   kubectl -n external-secrets get pod -l app.kubernetes.io/name=external-secrets \
     -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.serviceAccountName}{"\n"}{end}'
   printf '\n===== Karpenter pod service accounts =====\n'
   kubectl -n karpenter get pod -l app.kubernetes.io/name=karpenter \
     -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.serviceAccountName}{"\n"}{end}'

   printf '\n===== External Secrets logs =====\n'
   kubectl -n external-secrets logs deployment/external-secrets --since=10m --tail=200
   printf '\n===== Karpenter logs =====\n'
   kubectl -n karpenter logs deployment/karpenter --since=10m --tail=200
   ```

   Successful validation means the controllers use the intended service accounts and can call their required AWS APIs without static credentials. Look for the absence of `AccessDenied`, `NoCredentialProviders` and web identity errors.

## Expected Results

The EKS OIDC issuer exists, AWS-integrated controllers use dedicated workload identity and no static AWS credentials are stored in Kubernetes.

## Validation

- The EKS cluster has an IAM OIDC provider.
- EKS Pod Identity associations exist for Karpenter and External Secrets Operator.
- Controller pods use the expected Kubernetes service accounts.
- External Secrets can sync the intended secret path.
- Karpenter can provision nodes without static credentials.
- Controller logs show no `AccessDenied`, credential-provider or web-identity errors.
- Future IRSA workloads use GitOps-managed `eks.amazonaws.com/role-arn` annotations rather than live manual patches.

## Troubleshooting

Start with the service account, pod identity and controller logs:

```bash
printf '\n===== External Secrets service account =====\n'
kubectl -n external-secrets describe serviceaccount external-secrets
printf '\n===== Karpenter service account =====\n'
kubectl -n karpenter describe serviceaccount karpenter
printf '\n===== External Secrets logs =====\n'
kubectl -n external-secrets logs deployment/external-secrets --since=10m --tail=200
printf '\n===== Karpenter logs =====\n'
kubectl -n karpenter logs deployment/karpenter --since=10m --tail=200
```

If a controller reports `AccessDenied`:

- Confirm the pod uses the expected service account.
- Confirm the EKS Pod Identity association targets the expected namespace and service account.
- Confirm the IAM policy allows the specific AWS action and resource.

If a controller reports missing credentials:

- Confirm the `eks-pod-identity-agent` add-on is installed and healthy.
- Confirm the EKS Pod Identity association targets the expected namespace and service account.
- Restart the controller pod after the association is applied so it receives fresh credential wiring.
- Confirm no static AWS credential environment variables or mounted secrets are masking the Pod Identity credentials.

For future workloads that use IRSA annotations instead of EKS Pod Identity, also confirm the EKS OIDC provider exists in IAM and the service account has the expected `eks.amazonaws.com/role-arn` annotation.

## Final Repository State

The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup

No cleanup is required. Workload identity remains the platform standard for AWS access. Keep one IAM role per workload, avoid wildcard permissions, never use static AWS credentials and audit IAM roles regularly.

## Next Steps

Continue with [Lab 14 - Network Policies](./lab14-network-policies.md).
