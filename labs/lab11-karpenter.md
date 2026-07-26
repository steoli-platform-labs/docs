# Lab 11 - Karpenter

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Observability & Operations |
| **Lab** | 11 |
| **Difficulty** | Advanced |
| **Estimated Time** | 45-75 minutes |
| **Estimated Cost** | Medium |
| **Terraform** | No |
| **Kubernetes** | Yes |
| **GitOps** | Yes |

## Introduction

This lab introduces Karpenter as the cluster autoscaling component for the platform.

Karpenter watches unschedulable pods and provisions right-sized compute capacity for the EKS cluster. In this lab it is managed through GitOps so autoscaling configuration remains declarative and reviewable.

Concepts introduced in this lab include Karpenter, unschedulable pods, NodePools, EC2NodeClasses, NodeClaims and consolidation. See the [Concepts Reference](../concepts/README.md) for the Kubernetes and AWS concepts behind cluster autoscaling.

## Outcome
Implement and validate Karpenter in the complete platform reference implementation.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 10 completed
- AWS CLI, Terraform, kubectl and Helm installed
- Repository URLs configured

## Repository Changes
Primary implementation: `platform-config/clusters/dev/karpenter.yaml` plus the Karpenter provisioning resources that define cluster capacity.

## Files to Review
Review these files before validation:

- `platform-config/clusters/dev/karpenter.yaml`: Argo CD Application for the Karpenter Helm chart.
- Karpenter `NodePool` and `EC2NodeClass` manifests, if present in the repo. These are required for Karpenter to create nodes.
- `platform-live/environments/dev`: Terraform outputs and tags that Karpenter depends on, such as cluster name, private subnets, security groups and node IAM role details.

## Step-by-Step Implementation

1. Review the Karpenter Argo CD Application:

   ```bash
   cd "$WORKSPACE/platform-config"
   yq '.spec.source' clusters/dev/karpenter.yaml
   yq '.spec.destination' clusters/dev/karpenter.yaml
   ```

   Confirm the Application uses the Karpenter chart repository, deploys into the `karpenter` namespace and is managed by the root Argo CD Application.

2. Check whether provisioning resources already exist in Git:

   ```bash
   grep -R "kind: NodePool\|kind: EC2NodeClass" -n . || true
   ```

   The Helm chart installs the Karpenter controller, but the controller cannot provision nodes until a `NodePool` and `EC2NodeClass` exist. If this command finds no resources, add the required manifests before expecting autoscaling to work.

3. Confirm the AWS inputs that Karpenter needs:

   ```bash
   cd "$WORKSPACE/platform-live/environments/dev"
   export AWS_PAGER=""

   CLUSTER_NAME=$(terraform output -raw cluster_name)
   SUBNET_FILTER_VALUES=$(terraform output -json eks_private_subnet_ids | yq -r 'join(",")')

   if [ -z "$SUBNET_FILTER_VALUES" ]; then
     SUBNET_FILTER_VALUES=$(terraform output -json platform_private_subnet_ids | yq -r 'join(",")')
   fi

   aws sts get-caller-identity
   aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.name' --output text
   aws ec2 describe-subnets --filters "Name=subnet-id,Values=$SUBNET_FILTER_VALUES" \
     --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,Tags[?Key==`Name`].Value|[0]]' \
     --output table
   ```

   `AWS_PAGER=""` disables the AWS CLI pager so these commands return directly to the terminal when pasted as a block. `terraform output -raw cluster_name` reads the actual EKS cluster name created in the dev environment and stores it in `CLUSTER_NAME` for the AWS CLI commands. `SUBNET_FILTER_VALUES` uses the Terraform subnet outputs instead of assuming a tag filter, so the command prints the subnets that the EKS cluster actually uses. Karpenter needs discoverable private subnets, security groups and an IAM role or instance profile for nodes.

   The Terraform network module tags subnets with the cluster name for Kubernetes discovery. If `aws ec2 describe-subnets --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=shared,owned"` returns no subnets, pull the latest `platform-live` changes and run Terraform plan/apply for the dev environment so the subnet discovery tag matches the actual EKS cluster name.

4. Render or validate the Karpenter desired state before relying on Argo CD:

   ```bash
   cd "$WORKSPACE/platform-config"

   yq -r '.spec.source.targetRevision' clusters/dev/karpenter.yaml

   helm template karpenter oci://public.ecr.aws/karpenter/karpenter \
     --version "$(yq -r '.spec.source.targetRevision' clusters/dev/karpenter.yaml)" \
     --namespace karpenter \
     --values <(yq -r '.spec.source.helm.values' clusters/dev/karpenter.yaml) \
     >/dev/null

   kubectl apply --dry-run=client -f clusters/dev/karpenter.yaml
   ```

   No output from `helm template` means the chart rendered successfully. Any Helm error here will also fail in Argo CD. The `targetRevision` value should be pinned to a tested Karpenter chart version so future chart changes do not unexpectedly change this lab. The Helm value `settings.clusterName` must match the Terraform `cluster_name` output from the dev environment.

5. Commit and push the desired state if you changed it:

   ```bash
   git status --short
   git add clusters/dev/karpenter.yaml
   git commit -m "feat: configure karpenter"
   git push
   ```

   If you created separate `NodePool` or `EC2NodeClass` manifests, stage those actual paths before committing. If `git status --short` prints no files, there is nothing to commit.

6. Refresh the root Argo CD Application, then reconcile `karpenter`:

   ```bash
   kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application karpenter -o wide
   kubectl -n argocd annotate application karpenter argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application karpenter -o wide
   kubectl -n argocd describe application karpenter
   kubectl -n karpenter get deployment,pod -o wide
   kubectl -n karpenter get events --sort-by=.lastTimestamp
   ```

   `karpenter` should become `Synced / Healthy`. `Progressing` usually means the Deployment is still creating pods. `Degraded` means Argo CD synced the desired state but one or more Kubernetes resources are unhealthy. Use `describe application` to see the resource tree, `get deployment,pod` to see whether the controller is ready, and namespace events to see scheduling or image-pull failures. If a controller pod is in `CrashLoopBackOff`, check the previous container logs before the next restart overwrites the useful error:

   ```bash
   kubectl -n karpenter logs deployment/karpenter --previous --tail=200
   ```

   If the child Application stays on an old revision, inspect `platform-root` before troubleshooting the child Application.

7. Validate Karpenter readiness and configuration:

   ```bash
   kubectl -n argocd get application karpenter -o wide
   kubectl -n karpenter get pods
   kubectl get nodepool,ec2nodeclass
   kubectl describe nodepool default
   kubectl describe ec2nodeclass default
   kubectl -n karpenter logs deployment/karpenter --since=15m --tail=300
   ```

   The controller pod being ready only proves Karpenter is installed. `NodePool` and `EC2NodeClass` must also report ready before provisioning can work.

8. Create a temporary workload that cannot fit on existing nodes, then watch provisioning:

   ```bash
   kubectl create namespace karpenter-test
   kubectl -n karpenter-test create deployment inflate --image=public.ecr.aws/eks-distro/kubernetes/pause:3.10
   kubectl -n karpenter-test scale deployment inflate --replicas=20
   kubectl -n karpenter-test get pods -w
   ```

   In another terminal, watch Karpenter and nodes:

   ```bash
   kubectl get nodeclaim,node -w
   kubectl -n karpenter logs deployment/karpenter -f
   ```

   Expected behavior: pods become pending first, Karpenter creates a `NodeClaim`, a new node joins the cluster and the pending pods schedule.

9. Clean up the temporary namespace after validation:

   ```bash
   kubectl delete namespace karpenter-test
   kubectl get nodeclaim,node
   ```

   After cleanup, consolidation may remove unnecessary capacity depending on the configured policy.

## Expected Results
The `karpenter` Argo CD Application reconciles successfully and Karpenter can provision capacity for pending pods.

## Validation
- Controller pods are ready and authenticated to AWS.
- NodePool and EC2NodeClass conditions report ready.
- Pending test pods cause a new node claim and EC2 instance to be created.
- Test pods become ready on the new node.
- After deleting the test deployment, consolidation removes unnecessary capacity according to the configured policy.
- Controller logs contain no IAM, subnet, security-group, AMI or instance-profile errors.

## Troubleshooting
Start with the Argo CD Application, Karpenter controller and provisioning resources:

```bash
kubectl -n argocd describe application karpenter
kubectl -n karpenter get pods -o wide
kubectl -n karpenter describe deployment karpenter
kubectl -n karpenter get events --sort-by=.lastTimestamp
kubectl get nodepool,ec2nodeclass,nodeclaim
kubectl -n karpenter logs deployment/karpenter --since=15m --tail=300
kubectl -n karpenter logs deployment/karpenter --previous --tail=200
```

If Karpenter is installed but no nodes are created:

- Confirm `NodePool` and `EC2NodeClass` resources exist and are ready.
- Confirm subnet and security-group discovery tags match the cluster.
- Confirm the node IAM role or instance profile exists.
- Check controller logs for IAM, pricing, AMI, subnet or security-group errors.

If the controller is in `CrashLoopBackOff` and logs mention `failed to refresh cached credentials` or `no EC2 IMDS role found`:

- Karpenter does not have AWS credentials.
- Confirm the Karpenter ServiceAccount is connected to an IAM role through EKS Pod Identity or IRSA.
- Confirm that IAM role allows Karpenter to call the required EC2, SSM, IAM, EKS and pricing APIs for node provisioning.
- After fixing the IAM binding, refresh the Argo CD Application and watch the controller Deployment again.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Delete only the temporary `karpenter-test` namespace created during validation. Keep Karpenter installed because later labs may depend on cluster autoscaling behavior.

## Next Steps
Continue with [Lab 12 - External Secrets Operator](./lab12-external-secrets-operator.md).
