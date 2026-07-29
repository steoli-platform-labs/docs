# Lab 04 - Amazon EKS

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Kubernetes Platform |
| **Lab** | 04 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-60 minutes |
| **Estimated Cost** | Low |
| **Primary Tools** | Terraform, AWS CLI, kubectl |

## Introduction

This lab enables Amazon EKS in the Development Terraform root module.

The EKS cluster uses the VPC and EKS-ready private subnets created in Lab 03.

EKS is introduced here because the rest of the platform needs a Kubernetes runtime. Helm charts, GitOps controllers, observability tools and sample workloads all need a cluster where they can run.

Concepts introduced in this lab include Amazon EKS, Kubernetes clusters, control planes, worker nodes, node groups, kubeconfig and `kubectl`. See the [Concepts Reference](../concepts/README.md) for the difference between these components.

## Outcome

After this lab, the Development Terraform root module manages an active Amazon EKS cluster with at least one managed node group in private subnets.

## Prerequisites

- Lab 01 - Lab 03 completed.
- AWS CLI, Terraform and kubectl installed.
- The Development root module is already applied with networking enabled.
- Terraform can run from `platform-live/environments/dev`.

## Files to Review

This lab reviews the reusable EKS module in `platform-modules` and the Development environment composition in `platform-live`.

| File | Why it matters |
|------|----------------|
| `platform-modules/modules/eks/main.tf` | Defines reusable EKS cluster and node group resources |
| `platform-modules/modules/eks/variables.tf` | Exposes EKS version, subnet and node configuration inputs |
| `platform-modules/modules/eks/outputs.tf` | Exposes cluster connection details to the live stack |
| `platform-live/environments/dev/main.tf` | Enables or disables EKS in the Development environment |
| `platform-live/environments/dev/terraform.tfvars.example` | Shows safe defaults for enabling EKS |

## Step-by-Step Implementation

Enable EKS through Terraform, select a supported Kubernetes version and apply the Development root module.

1. Open the Development root module:

   ```bash
   cd "$WORKSPACE/platform-live/environments/dev"
   ```

2. Check the EKS versions available in your AWS region:

   ```bash
   export AWS_PAGER=""

   aws eks describe-cluster-versions \
     --region "$AWS_REGION" \
     --query 'clusterVersions[?status==`STANDARD_SUPPORT`].clusterVersion' \
     --output table
   ```

   Choose a version in standard support unless you intentionally need an older version. EKS versions change over time, so prefer the newest standard-support version that is compatible with the platform components used in these labs.

   The `kubernetes_version` you choose in the next step must appear in this command output. If the example version is not listed, use a listed standard-support version instead of copying the example blindly.

   If `eks_private_subnet_cidrs` is set, EKS uses those dedicated private subnets from the secondary VPC CIDR. If it is empty, EKS uses the platform private subnets from the primary VPC CIDR instead.

3. Edit `terraform.tfvars` and enable EKS:

   ```hcl
   enable_eks = true

   kubernetes_version  = "1.36"
   node_instance_types = ["t3.medium"]
   ```

   `enable_eks = true` turns on the Kubernetes cluster portion of the live Terraform stack. Without it, the network from Lab 03 exists, but there is no EKS control plane or worker node group for `kubectl` to use.

4. Plan and apply:

   ```bash
   printf '\n===== Terraform format =====\n'
   terraform fmt
   printf '\n===== Terraform validate =====\n'
   terraform validate
   printf '\n===== Terraform plan =====\n'
   terraform plan -out=tfplan
   printf '\n===== Terraform apply =====\n'
   terraform apply tfplan
   ```

   Review the plan before applying. EKS creation can take several minutes.

   Proceed only if the plan creates the EKS cluster, managed node group and access resources without destroying the VPC networking from Lab 03. EKS control plane and node group creation commonly take 10 minutes or more and incur hourly cost while running.

5. Configure kubectl:

   ```bash
   export AWS_PAGER=""
   CLUSTER="$(terraform output -raw cluster_name)"
   aws eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION"
   ```

   Expected output says a kubeconfig context was added or updated. Stop if `CLUSTER` is empty or AWS returns `ResourceNotFoundException`; that means Terraform output or cluster creation did not complete as expected.

   `kubectl` does not automatically know about new EKS clusters. `aws eks update-kubeconfig` writes a local Kubernetes context with the cluster endpoint and AWS authentication settings so later `kubectl` commands know which cluster to contact.

6. Verify the cluster:

   ```bash
   export AWS_PAGER=""

   printf '\n===== EKS cluster details =====\n'
   aws eks describe-cluster \
     --name "$CLUSTER" \
     --query 'cluster.{status:status,version:version,endpoint:endpoint,subnets:resourcesVpcConfig.subnetIds}'

   printf '\n===== EKS managed node groups =====\n'
   aws eks list-nodegroups --cluster-name "$CLUSTER"

   printf '\n===== Kubernetes cluster info =====\n'
   kubectl cluster-info

   printf '\n===== Kubernetes nodes =====\n'
   kubectl get nodes -o wide

   printf '\n===== Kubernetes pods =====\n'
   kubectl get pods -A

   printf '\n===== Kubernetes readyz =====\n'
   kubectl get --raw='/readyz?verbose'
   ```

   Proceed when the cluster status is `ACTIVE`, at least one node group is listed, `kubectl get nodes` shows nodes in `Ready`, system pods are running and `/readyz` ends with a successful ready check.

   The AWS CLI checks prove the cloud-side EKS resources exist. The `kubectl` checks prove the Kubernetes API is reachable and the worker nodes can actually run pods.

   Run a final no-drift check after apply:

   ```bash
   printf '\n===== Terraform drift check =====\n'
   terraform plan -detailed-exitcode
   ```

   Exit code `0` means the applied state matches configuration. Exit code `2` means Terraform sees changes and you should review them before continuing. Exit code `1` is an error.

7. Confirm only Terraform source and documentation files are tracked. Keep local `backend.hcl`, `terraform.tfvars`, plan files and `.terraform/` ignored.

   In `platform-modules`:

   ```bash
   cd "$WORKSPACE/platform-modules"
   printf '\n===== platform-modules git status =====\n'
   git status
   printf '\n===== platform-modules whitespace check =====\n'
   git diff --check
   printf '\n===== platform-modules ignored local files check =====\n'
   git ls-files backend.hcl terraform.tfvars terraform.tfstate terraform.tfstate.backup '*.tfplan'
   ```

   In `platform-live`:

   ```bash
   cd "$WORKSPACE/platform-live"
   printf '\n===== platform-live git status =====\n'
   git status
   printf '\n===== platform-live whitespace check =====\n'
   git diff --check
   printf '\n===== platform-live ignored local files check =====\n'
   git ls-files backend.hcl terraform.tfvars terraform.tfstate terraform.tfstate.backup '*.tfplan'
   ```

   The `git ls-files` commands should print no local backend, variable, state or plan files.

## Expected Results

Terraform creates an active EKS control plane, a managed node group and access entries configured by the live environment. `kubectl` can connect to the cluster after kubeconfig is updated.

## Validation

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
printf '\n===== Cluster events =====\n'
kubectl get events -A --sort-by=.lastTimestamp
printf '\n===== Cluster pods =====\n'
kubectl get pods -A
```

If nodes do not join, verify that EKS is using the expected private subnet IDs and that private subnet routing through NAT is working.

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
