# Lab 11 - Karpenter

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Observability & Operations |
| **Lab** | 11 |
| **Difficulty** | Advanced |
| **Estimated Time** | 45-75 minutes |
| **Primary Tools** | Terraform, Helm, kubectl, Argo CD, Karpenter |

## Introduction

This lab introduces Karpenter as the cluster autoscaling component for the platform.

This lab can add AWS cost when Karpenter provisions extra EC2 instances for pending pods. The lab validates that behavior with temporary demand and the final cleanup lab removes any remaining Karpenter-created capacity.

Karpenter watches unschedulable pods and provisions right-sized compute capacity for the EKS cluster. In this lab it is managed through GitOps so autoscaling configuration remains declarative and reviewable.

For beginners, Karpenter answers a practical question: what happens when the cluster needs more room? Instead of keeping oversized nodes running all the time, Karpenter can add capacity when pods are pending and later remove unused capacity to control cost.

Concepts introduced in this lab include Karpenter, unschedulable pods, NodePools, EC2NodeClasses, NodeClaims and consolidation. See the [Concepts Reference](../concepts/README.md) for the Kubernetes and AWS concepts behind cluster autoscaling.

## Outcome
Validate Karpenter in the complete platform reference implementation and demonstrate that it can create workload capacity.

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
- `platform-live/environments/shared`: Terraform outputs and tags that Karpenter depends on, such as cluster name, private subnets, security groups and node IAM role details.
- `platform-modules/modules/eks/karpenter.tf`: Karpenter controller IAM role, node IAM role, EKS Pod Identity association and node access entry.

## Step-by-Step Implementation

1. Review the Karpenter Argo CD Application:

   ```bash
   cd "$WORKSPACE/platform-config"
   printf '\n===== Karpenter Application source =====\n'
   yq '.spec.source' clusters/dev/karpenter.yaml
   printf '\n===== Karpenter Application destination =====\n'
   yq '.spec.destination' clusters/dev/karpenter.yaml
   ```

   Confirm the Application uses the Karpenter chart repository, deploys into the `karpenter` namespace and is managed by the root Argo CD Application.

2. Check whether provisioning resources already exist in Git:

   ```bash
   grep -R "kind: NodePool\|kind: EC2NodeClass" -n . || true
   ```

   The Helm chart installs the Karpenter controller, but the controller cannot provision nodes until a `NodePool` and `EC2NodeClass` exist. These manifests should already be present in the current `platform-config` repository.

3. Confirm the AWS inputs that Karpenter needs:

   ```bash
   cd "$WORKSPACE/platform-live/environments/shared"
   export AWS_PAGER=""

   CLUSTER_NAME=$(terraform output -raw cluster_name)
   SUBNET_FILTER_VALUES=$(terraform output -json eks_private_subnet_ids | yq -r 'join(",")')

   if [ -z "$SUBNET_FILTER_VALUES" ]; then
     SUBNET_FILTER_VALUES=$(terraform output -json platform_private_subnet_ids | yq -r 'join(",")')
   fi

   printf '\n===== AWS caller identity =====\n'
   aws sts get-caller-identity
   printf '\n===== EKS cluster name =====\n'
   aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.name' --output text
   printf '\n===== Karpenter subnet candidates =====\n'
   aws ec2 describe-subnets --filters "Name=subnet-id,Values=$SUBNET_FILTER_VALUES" \
     --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,Tags[?Key==`Name`].Value|[0]]' \
     --output table
   ```

   `AWS_PAGER=""` disables the AWS CLI pager so these commands return directly to the terminal when pasted as a block. `terraform output -raw cluster_name` reads the actual EKS cluster name created in the dev environment and stores it in `CLUSTER_NAME` for the AWS CLI commands. `SUBNET_FILTER_VALUES` uses the Terraform subnet outputs instead of assuming a tag filter, so the command prints the subnets that the EKS cluster actually uses. Karpenter needs discoverable private subnets, security groups, a controller IAM role connected through EKS Pod Identity and a node IAM role for created instances.

   The Terraform network module tags subnets with the cluster name for Kubernetes discovery. If `aws ec2 describe-subnets --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=shared,owned"` returns no subnets, pull the latest `platform-live` changes and run Terraform plan/apply for the dev environment so the subnet discovery tag matches the actual EKS cluster name.

4. Verify the Terraform resources required by Karpenter:

   ```bash
   cd "$WORKSPACE/platform-live/environments/shared"
   printf '\n===== Karpenter controller role ARN =====\n'
   terraform output -raw karpenter_controller_role_arn
   printf '\n===== Karpenter node role name =====\n'
   terraform output -raw karpenter_node_role_name
   ```

   Expected result: both outputs print values. These resources are part of the EKS Terraform configuration and should already exist because the earlier Terraform labs applied the current platform configuration. The node role output should match the `role` value in `platform-config/addons/karpenter/ec2nodeclass.yaml`.

   If either output is missing, pull the latest `platform-modules` and `platform-live` repos, then return to the EKS Terraform lab flow and apply the dev environment before continuing. Do not treat Lab 11 as a place to make new Terraform changes.

   Optional drift check:

   ```bash
   terraform plan -detailed-exitcode
   ```

   Exit code `0` means the environment already matches the Terraform configuration. Exit code `2` means Terraform found unapplied changes; review the plan before applying anything.

5. Render or validate the Karpenter desired state before relying on Argo CD:

   ```bash
   cd "$WORKSPACE/platform-config"

   printf '\n===== Karpenter chart version =====\n'
   yq -r '.spec.source.targetRevision' clusters/dev/karpenter.yaml

   printf '\n===== Render Karpenter chart =====\n'
   helm template karpenter oci://public.ecr.aws/karpenter/karpenter \
     --version "$(yq -r '.spec.source.targetRevision' clusters/dev/karpenter.yaml)" \
     --namespace karpenter \
     --values <(yq -r '.spec.source.helm.values' clusters/dev/karpenter.yaml) \
     >/dev/null

   printf '\n===== Karpenter Application dry-run =====\n'
   kubectl apply --dry-run=client -f clusters/dev/karpenter.yaml
   printf '\n===== Karpenter provisioning Application dry-run =====\n'
   kubectl apply --dry-run=client -f clusters/dev/karpenter-provisioning.yaml
   printf '\n===== NodePool dry-run =====\n'
   kubectl apply --dry-run=client -f addons/karpenter/nodepool.yaml
   printf '\n===== EC2NodeClass dry-run =====\n'
   kubectl apply --dry-run=client -f addons/karpenter/ec2nodeclass.yaml
   ```

   No output from `helm template` means the chart rendered successfully. Any Helm error here will also fail in Argo CD. The `targetRevision` value should be pinned to a tested Karpenter chart version so future chart changes do not unexpectedly change this lab. The Helm value `settings.clusterName` must match the Terraform `cluster_name` output from the dev environment.

   Each `kubectl apply --dry-run=client` should print resources as `created (dry run)` or `configured (dry run)`. Stop on unknown kinds or schema errors because Argo CD will hit the same API validation problem.

   A client-side dry-run asks Kubernetes whether it understands the manifest shape without creating the object. This is especially useful for Karpenter resources because they depend on CRDs being installed before custom resources can be accepted.

6. Refresh the root Argo CD Application, then reconcile `karpenter`:

   ```bash
   printf '\n===== Refresh dev root =====\n'
   kubectl -n argocd annotate application platform-root-dev argocd.argoproj.io/refresh=hard --overwrite
   printf '\n===== Karpenter Application before refresh =====\n'
   kubectl -n argocd get application karpenter -o wide
   printf '\n===== Refresh Karpenter Applications =====\n'
   kubectl -n argocd annotate application karpenter argocd.argoproj.io/refresh=hard --overwrite
   printf '\n===== Karpenter Application after refresh =====\n'
   kubectl -n argocd get application karpenter -o wide
   printf '\n===== Karpenter provisioning Application =====\n'
   kubectl -n argocd get application karpenter-provisioning -o wide
   printf '\n===== Karpenter Application details =====\n'
   kubectl -n argocd describe application karpenter
   printf '\n===== Karpenter workloads =====\n'
   kubectl -n karpenter get deployment,pod -o wide
   printf '\n===== Karpenter events =====\n'
   kubectl -n karpenter get events --sort-by=.lastTimestamp
   ```

   `karpenter` should become `Synced / Healthy`. `Progressing` usually means the Deployment is still creating pods. `Degraded` means Argo CD synced the desired state but one or more Kubernetes resources are unhealthy. Use `describe application` to see the resource tree, `get deployment,pod` to see whether the controller is ready, and namespace events to see scheduling or image-pull failures. If `kubectl -n karpenter get events --sort-by=.lastTimestamp` prints `No resources found`, that is normal when no recent events exist in the namespace. If a controller pod is in `CrashLoopBackOff`, check the previous container logs before the next restart overwrites the useful error:

   ```bash
   kubectl -n karpenter logs deployment/karpenter --previous --tail=200
   ```

   If the child Application stays on an old revision, inspect `platform-root-dev` before troubleshooting the child Application.

7. Validate Karpenter readiness and configuration:

   ```bash
   printf '\n===== Karpenter Application =====\n'
   kubectl -n argocd get application karpenter -o wide
   printf '\n===== Karpenter provisioning Application =====\n'
   kubectl -n argocd get application karpenter-provisioning -o wide
   printf '\n===== Karpenter pods =====\n'
   kubectl -n karpenter get pods
   printf '\n===== Karpenter custom resources =====\n'
   kubectl get nodepool,ec2nodeclass
   printf '\n===== NodePool details =====\n'
   kubectl describe nodepool karpenter
   printf '\n===== EC2NodeClass details =====\n'
   kubectl describe ec2nodeclass default
   printf '\n===== Karpenter logs =====\n'
   kubectl -n karpenter logs deployment/karpenter --since=15m --tail=300
   ```

   The controller pod being ready only proves Karpenter is installed. `NodePool` and `EC2NodeClass` must also report ready before provisioning can work. The lab NodePool uses on-demand capacity so the first run does not depend on EC2 Spot service-linked-role setup or current Spot availability.

   In the `describe` output, look for readiness conditions such as `Ready=True`. If either custom resource is `Ready=False`, read the condition message before creating the inflate workload.

8. Confirm the instance types Karpenter may launch:

   ```bash
   cd "$WORKSPACE/platform-config"

   printf '\n===== NodePool requirements =====\n'
   yq '.spec.template.spec.requirements' addons/karpenter/nodepool.yaml
   printf '\n===== Allowed instance type assertion =====\n'
   yq -e '.spec.template.spec.requirements[] | select(.key == "node.kubernetes.io/instance-type" and .operator == "In" and (.values | contains(["t3.small", "t3.medium", "c7a.medium"])))' addons/karpenter/nodepool.yaml
   printf '\n===== NodePool dry-run =====\n'
   kubectl apply --dry-run=client -f addons/karpenter/nodepool.yaml
   ```

   This keeps the lab predictable by limiting Karpenter to a small set of inexpensive instance types. Prefer a short list over a single instance type, because one exact type may be temporarily unavailable in an Availability Zone. If this check fails, pull the latest `platform-config` repository before creating the test workload.

   Refresh `karpenter-provisioning` before creating the test workload:

   ```bash
   printf '\n===== Refresh dev root =====\n'
   kubectl -n argocd annotate application platform-root-dev argocd.argoproj.io/refresh=hard --overwrite
   printf '\n===== Refresh Karpenter provisioning =====\n'
   kubectl -n argocd annotate application karpenter-provisioning argocd.argoproj.io/refresh=hard --overwrite
   printf '\n===== NodePool details =====\n'
   kubectl describe nodepool karpenter
   ```

9. Create a temporary workload that cannot fit on existing nodes, then watch provisioning:

   ```bash
   printf '\n===== Create Karpenter test namespace =====\n'
   kubectl create namespace karpenter-test
   printf '\n===== Create inflate deployment =====\n'
   kubectl -n karpenter-test create deployment inflate --image=public.ecr.aws/eks-distro/kubernetes/pause:3.10
   printf '\n===== Scale inflate deployment =====\n'
   kubectl -n karpenter-test scale deployment inflate --replicas=20
   printf '\n===== Watch test pods =====\n'
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

   The watch streams are safe to stop with `Ctrl-C` after test pods are `Running`, a `NodeClaim` exists and at least one new node reaches `Ready`. If pods stay `Pending`, inspect Karpenter logs and NodeClaim conditions instead of creating more test workloads.

   The `pause` image does almost nothing, but each replica still needs a schedulable pod slot. Scaling it beyond current capacity intentionally creates `Pending` pods, and Karpenter reacts by creating new node capacity.

   The `kubectl get node -w` command is a watch stream. It can print the same node multiple times as status changes from `NotReady` to `Ready`, so repeated lines do not mean Kubernetes created duplicate nodes with the same name. To see the current unique nodes, run a normal non-watch query in another terminal:

   ```bash
   printf '\n===== Current nodes =====\n'
   kubectl get nodes -o wide
   printf '\n===== Current node claims =====\n'
   kubectl get nodeclaim -o wide
   ```

10. Clean up the temporary namespace after validation:

   ```bash
   printf '\n===== Delete Karpenter test namespace =====\n'
   kubectl delete namespace karpenter-test
   printf '\n===== Remaining node claims and nodes =====\n'
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
printf '\n===== Karpenter Application details =====\n'
kubectl -n argocd describe application karpenter
printf '\n===== Karpenter pods =====\n'
kubectl -n karpenter get pods -o wide
printf '\n===== Karpenter deployment details =====\n'
kubectl -n karpenter describe deployment karpenter
printf '\n===== Karpenter events =====\n'
kubectl -n karpenter get events --sort-by=.lastTimestamp
printf '\n===== Karpenter provisioning resources =====\n'
kubectl get nodepool,ec2nodeclass,nodeclaim
printf '\n===== Karpenter recent logs =====\n'
kubectl -n karpenter logs deployment/karpenter --since=15m --tail=300
printf '\n===== Karpenter previous logs =====\n'
kubectl -n karpenter logs deployment/karpenter --previous --tail=200
```

If Karpenter is installed but no nodes are created:

- Confirm `NodePool` and `EC2NodeClass` resources exist and are ready.
- Confirm subnet and security-group discovery tags match the cluster.
- Confirm the node IAM role or instance profile exists.
- Check controller logs for IAM, pricing, AMI, subnet or security-group errors.

If the controller is in `CrashLoopBackOff` and logs mention `failed to refresh cached credentials` or `no EC2 IMDS role found`:

- Karpenter does not have AWS credentials.
- Confirm the Karpenter ServiceAccount is connected to an IAM role through EKS Pod Identity.
- Confirm that IAM role allows Karpenter to call the required EC2, SSM, IAM, EKS and pricing APIs for node provisioning.
- After fixing the IAM binding, refresh the Argo CD Application and watch the controller Deployment again.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Delete only the temporary `karpenter-test` namespace created during validation. Keep Karpenter installed because later labs may depend on cluster autoscaling behavior.

## Next Steps
Continue with [Lab 12 - External Secrets Operator](./lab12-external-secrets-operator.md).
