# Lab 04 - Amazon EKS

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Kubernetes Platform |
| **Lab** | 04 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-60 minutes |
| **Estimated Cost** | Low |
| **Terraform** | Yes |
| **Kubernetes** | Yes |
| **GitOps** | No |

## Introduction

This lab enables Amazon EKS in the Development Terraform root module.

The EKS cluster uses the VPC and EKS-ready private subnets created in Lab 03.

## Outcome

After this lab, the Development Terraform root module manages an active Amazon EKS cluster with at least one managed node group in private subnets.

## Prerequisites

- Lab 01 - Lab 03 completed.
- AWS CLI, Terraform and kubectl installed.
- The Development root module is already applied with networking enabled.
- Terraform can run from `platform-live/environments/dev`.

## Repository Changes

| Repository | Responsibility |
|------------|----------------|
| `platform-live` | Enables EKS in `environments/dev` |
| `platform-modules` | Provides the reusable EKS module |
| `docs` | Documents the lab workflow |

## Files to Review

| File | Why it matters |
|------|----------------|
| `platform-modules/modules/eks/main.tf` | Defines reusable EKS cluster and node group resources |
| `platform-modules/modules/eks/variables.tf` | Exposes EKS version, subnet and node configuration inputs |
| `platform-modules/modules/eks/outputs.tf` | Exposes cluster connection details to the live stack |
| `platform-live/environments/dev/main.tf` | Enables or disables EKS in the Development environment |
| `platform-live/environments/dev/terraform.tfvars.example` | Shows safe defaults for enabling EKS |

## Step-by-Step Implementation

Enable EKS through Terraform, select a supported Kubernetes version and apply the Development root module.

Open the Development root module:

```bash
cd "$WORKSPACE/platform-live/environments/dev"
```

Check the EKS versions available in your AWS region:

```bash
aws eks describe-cluster-versions \
  --region "$AWS_REGION" \
  --query 'clusterVersions[?status==`STANDARD_SUPPORT`].clusterVersion' \
  --output table
```

Choose a version in standard support unless you intentionally need an older version. EKS versions change over time, so prefer the newest standard-support version that is compatible with the platform components used in these labs.

If `eks_private_subnet_cidrs` is set, EKS uses those dedicated private subnets from the secondary VPC CIDR. If it is empty, EKS uses the platform private subnets from the primary VPC CIDR instead.

Edit `terraform.tfvars` and enable EKS:

```hcl
enable_eks = true

kubernetes_version  = "1.36"
node_instance_types = ["t3.medium"]
```

Plan and apply:

```bash
terraform fmt
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Review the plan before applying. EKS creation can take several minutes.

## Expected Results

Terraform creates an active EKS control plane, a managed node group and access entries configured by the live environment. `kubectl` can connect to the cluster after kubeconfig is updated.

## Validation

Configure kubectl:

```bash
CLUSTER="$(terraform output -raw cluster_name)"
aws eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION"
```

Verify the cluster:

```bash
aws eks describe-cluster \
  --name "$CLUSTER" \
  --query 'cluster.{status:status,version:version,endpoint:endpoint,subnets:resourcesVpcConfig.subnetIds}'

aws eks list-nodegroups --cluster-name "$CLUSTER"
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A
kubectl get --raw='/readyz?verbose'
```

Pass criteria:

- EKS cluster status is `ACTIVE`.
- The configured Kubernetes version is returned.
- At least one managed node group exists.
- Nodes are `Ready`.
- Nodes are placed in the expected private subnets: dedicated EKS subnets when configured, otherwise platform private subnets.
- CoreDNS, kube-proxy and VPC CNI pods are running.
- The Kubernetes API `/readyz` endpoint reports success.
- `terraform plan -detailed-exitcode` returns `0` after apply.

## Troubleshooting

Start with:

```bash
kubectl get events -A --sort-by=.lastTimestamp
kubectl get pods -A
```

If nodes do not join, verify that EKS is using the expected private subnet IDs and that private subnet routing through NAT is working.

## Commit and Push

Commit only Terraform source changes and documentation. Keep local `backend.hcl`, `terraform.tfvars`, plan files and `.terraform/` ignored.

In `platform-modules`:

```bash
cd "$WORKSPACE/platform-modules"
git status
git diff --check
git add modules/eks/
git commit -m "add reusable eks module"
git push
```

In `platform-live`:

```bash
cd "$WORKSPACE/platform-live"
git status
git diff --check
git add environments/dev/
git commit -m "enable development eks cluster"
git push
```

## Final Repository State

At completion, `platform-live` composes the reusable EKS module for the Development environment and `platform-modules` contains reusable EKS module code. The deployed cluster remains managed by Terraform.

## Cleanup

Do not destroy the Development root module. Later labs depend on the EKS cluster.

Do not commit local generated files:

- `backend.hcl`
- `terraform.tfvars`
- `tfplan`
- `.terraform/`

## Next Steps

Continue with [Lab 05 - Helm](./lab05-helm.md).
