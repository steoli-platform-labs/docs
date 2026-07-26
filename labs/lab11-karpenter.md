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

## Files to Review
Review these files before validation:

- `platform-config/clusters/dev/karpenter.yaml`: Argo CD Application for the Karpenter Helm chart.
- `platform-config/clusters/dev/karpenter-provisioning.yaml`: Argo CD Application for Karpenter `NodePool` and `EC2NodeClass` resources.
- `platform-config/addons/karpenter/nodepool.yaml` and `platform-config/addons/karpenter/ec2nodeclass.yaml`: provisioning resources required for Karpenter to create nodes.
- `platform-live/environments/dev`: Terraform outputs and tags that Karpenter depends on, such as cluster name, private subnets, security groups and node IAM role details.
- `platform-modules/modules/eks/karpenter.tf`: Karpenter controller IAM role, node IAM role, EKS Pod Identity association and node access entry.

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

   `AWS_PAGER=""` disables the AWS CLI pager so these commands return directly to the terminal when pasted as a block. `terraform output -raw cluster_name` reads the actual EKS cluster name created in the dev environment and stores it in `CLUSTER_NAME` for the AWS CLI commands. `SUBNET_FILTER_VALUES` uses the Terraform subnet outputs instead of assuming a tag filter, so the command prints the subnets that the EKS cluster actually uses. Karpenter needs discoverable private subnets, security groups, a controller IAM role connected through EKS Pod Identity and a node IAM role for created instances.

   The Terraform network module tags subnets with the cluster name for Kubernetes discovery. If `aws ec2 describe-subnets --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=shared,owned"` returns no subnets, pull the latest `platform-live` changes and run Terraform plan/apply for the dev environment so the subnet discovery tag matches the actual EKS cluster name.

4. Verify the Terraform resources required by Karpenter:

   ```bash
   cd "$WORKSPACE/platform-live/environments/dev"
   terraform output -raw karpenter_controller_role_arn
   terraform output -raw karpenter_node_role_name
   ```

   Expected result: both outputs print values. These resources are part of the EKS Terraform configuration and should already exist because the earlier Terraform labs applied the current platform configuration. The node role output should match the `role` value in `platform-config/addons/karpenter/ec2nodeclass.yaml`.

   If either output is missing, pull the latest `platform-modules` and `platform-live` repos, then return to the EKS Terraform lab flow and apply the dev environment before continuing. Do not treat Lab 11 as a place to make new Terraform changes unless you are upgrading an older already-created lab environment.

   Optional drift check:

   ```bash
   terraform plan -detailed-exitcode
   ```

   Exit code `0` means the environment already matches the Terraform configuration. Exit code `2` means Terraform found unapplied changes; review the plan before applying anything.

5. Render or validate the Karpenter desired state before relying on Argo CD:

   ```bash
   cd "$WORKSPACE/platform-config"

   yq -r '.spec.source.targetRevision' clusters/dev/karpenter.yaml

   helm template karpenter oci://public.ecr.aws/karpenter/karpenter \
     --version "$(yq -r '.spec.source.targetRevision' clusters/dev/karpenter.yaml)" \
     --namespace karpenter \
     --values <(yq -r '.spec.source.helm.values' clusters/dev/karpenter.yaml) \
     >/dev/null

   kubectl apply --dry-run=client -f clusters/dev/karpenter.yaml
   kubectl apply --dry-run=client -f clusters/dev/karpenter-provisioning.yaml
   kubectl apply --dry-run=client -f addons/karpenter/nodepool.yaml
   kubectl apply --dry-run=client -f addons/karpenter/ec2nodeclass.yaml
   ```

   No output from `helm template` means the chart rendered successfully. Any Helm error here will also fail in Argo CD. The `targetRevision` value should be pinned to a tested Karpenter chart version so future chart changes do not unexpectedly change this lab. The Helm value `settings.clusterName` must match the Terraform `cluster_name` output from the dev environment.

6. Commit and push the desired state if you changed it:

   ```bash
   git status --short
   git add clusters/dev/karpenter.yaml clusters/dev/karpenter-provisioning.yaml addons/karpenter/
   git commit -m "feat: configure karpenter"
   git push
   ```

   If `git status --short` prints no files, there is nothing to commit.

7. Refresh the root Argo CD Application, then reconcile `karpenter`:

   ```bash
   kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application karpenter -o wide
   kubectl -n argocd annotate application karpenter argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application karpenter -o wide
   kubectl -n argocd get application karpenter-provisioning -o wide
   kubectl -n argocd describe application karpenter
   kubectl -n karpenter get deployment,pod -o wide
   kubectl -n karpenter get events --sort-by=.lastTimestamp
   ```

   `karpenter` should become `Synced / Healthy`. `Progressing` usually means the Deployment is still creating pods. `Degraded` means Argo CD synced the desired state but one or more Kubernetes resources are unhealthy. Use `describe application` to see the resource tree, `get deployment,pod` to see whether the controller is ready, and namespace events to see scheduling or image-pull failures. If `kubectl -n karpenter get events --sort-by=.lastTimestamp` prints `No resources found`, that is normal when no recent events exist in the namespace. If a controller pod is in `CrashLoopBackOff`, check the previous container logs before the next restart overwrites the useful error:

   ```bash
   kubectl -n karpenter logs deployment/karpenter --previous --tail=200
   ```

   If the child Application stays on an old revision, inspect `platform-root` before troubleshooting the child Application.

8. Validate Karpenter readiness and configuration:

   ```bash
   kubectl -n argocd get application karpenter -o wide
   kubectl -n argocd get application karpenter-provisioning -o wide
   kubectl -n karpenter get pods
   kubectl get nodepool,ec2nodeclass
   kubectl describe nodepool karpenter
   kubectl describe ec2nodeclass default
   kubectl -n karpenter logs deployment/karpenter --since=15m --tail=300
   ```

   The controller pod being ready only proves Karpenter is installed. `NodePool` and `EC2NodeClass` must also report ready before provisioning can work. The lab NodePool uses on-demand capacity so the first run does not depend on EC2 Spot service-linked-role setup or current Spot availability.

9. Configure the instance types Karpenter may launch:

   ```bash
   cd "$WORKSPACE/platform-config"

   yq '.spec.template.spec.requirements' addons/karpenter/nodepool.yaml

   if ! yq -e '.spec.template.spec.requirements[] | select(.key == "node.kubernetes.io/instance-type")' addons/karpenter/nodepool.yaml >/dev/null 2>&1; then
     yq -i '.spec.template.spec.requirements += [{"key":"node.kubernetes.io/instance-type","operator":"In","values":["t3.small","t3.medium","c7a.medium"]}]' addons/karpenter/nodepool.yaml
   fi

   yq -i '(.spec.template.spec.requirements[] | select(.key == "node.kubernetes.io/instance-type")).operator = "In"' addons/karpenter/nodepool.yaml
   yq -i '(.spec.template.spec.requirements[] | select(.key == "node.kubernetes.io/instance-type")).values = ["t3.small", "t3.medium", "c7a.medium"]' addons/karpenter/nodepool.yaml

   yq '.spec.template.spec.requirements' addons/karpenter/nodepool.yaml
   kubectl apply --dry-run=client -f addons/karpenter/nodepool.yaml
   ```

   This keeps the lab predictable by limiting Karpenter to a small set of inexpensive instance types. Prefer a short list over a single instance type, because one exact type may be temporarily unavailable in an Availability Zone. If you changed the file, commit and push it, then refresh `karpenter-provisioning` before creating the test workload:

   ```bash
   git status --short
   git add addons/karpenter/nodepool.yaml
   git commit -m "configure karpenter instance types"
   git push
   kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd annotate application karpenter-provisioning argocd.argoproj.io/refresh=hard --overwrite
   kubectl describe nodepool karpenter
   ```

   If `git status --short` prints no files, the instance-type requirement is already configured and there is nothing to commit.

10. Create a temporary workload that cannot fit on existing nodes, then watch provisioning:

   ```bash
   kubectl create namespace karpenter-test
   kubectl -n karpenter-test create deployment inflate --image=public.ecr.aws/eks-distro/kubernetes/pause:3.10
   kubectl -n karpenter-test scale deployment inflate --replicas=20
   kubectl -n karpenter-test get pods -w
   ```

   In another terminal, watch Karpenter and nodes:

   ```bash
   kubectl get nodeclaim -w
   ```

   In another terminal, watch nodes separately because `kubectl get --watch` accepts only one resource type:

   ```bash
   kubectl get node -w
   ```

   In another terminal, follow Karpenter logs:

   ```bash
   kubectl -n karpenter logs deployment/karpenter -f
   ```

   Expected behavior: pods become pending first, Karpenter creates one or more `NodeClaim` resources, one or more new nodes join the cluster and the pending pods schedule. The exact number of nodes depends on current free capacity, selected instance types, daemonset overhead and how many test pods you created. Do not expect exactly three nodes.

   The `kubectl get node -w` command is a watch stream. It can print the same node multiple times as status changes from `NotReady` to `Ready`, so repeated lines do not mean Kubernetes created duplicate nodes with the same name. To see the current unique nodes, run a normal non-watch query in another terminal:

   ```bash
   kubectl get nodes -o wide
   kubectl get nodeclaim -o wide
   ```

11. Clean up the temporary namespace after validation:

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
