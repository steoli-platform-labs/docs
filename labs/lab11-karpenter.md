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
Complete Lab 01 - Lab 10. AWS CLI, Terraform, kubectl and Helm must be installed, with repository URLs configured.

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
   aws sts get-caller-identity
   aws eks describe-cluster --name <cluster-name> --query 'cluster.name' --output text
   aws ec2 describe-subnets --filters "Name=tag:kubernetes.io/cluster/<cluster-name>,Values=shared,owned" \
     --query 'Subnets[*].[SubnetId,AvailabilityZone,Tags]' --output table
   ```

   Karpenter needs discoverable private subnets, security groups and an IAM role or instance profile for nodes. Use your actual cluster name from the Terraform outputs.

4. Render or validate the Karpenter desired state before relying on Argo CD:

   ```bash
   yq -r '.spec.source.targetRevision' clusters/dev/karpenter.yaml

   helm template karpenter karpenter \
     --repo public.ecr.aws/karpenter \
     --version "$(yq -r '.spec.source.targetRevision' clusters/dev/karpenter.yaml)" \
     --namespace karpenter \
     >/dev/null

   kubectl apply --dry-run=client -f clusters/dev/karpenter.yaml
   ```

   No output from `helm template` means the chart rendered successfully. Any Helm error here will also fail in Argo CD. If `targetRevision` is still `*`, pin a tested Karpenter chart version before committing so future chart changes do not unexpectedly change this lab.

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
   ```

   `karpenter` should become `Synced / Healthy`. If it stays on an old revision, inspect `platform-root` before troubleshooting the child Application.

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
kubectl get nodepool,ec2nodeclass,nodeclaim
kubectl -n karpenter logs deployment/karpenter --since=15m --tail=300
```

If Karpenter is installed but no nodes are created:

- Confirm `NodePool` and `EC2NodeClass` resources exist and are ready.
- Confirm subnet and security-group discovery tags match the cluster.
- Confirm the node IAM role or instance profile exists.
- Check controller logs for IAM, pricing, AMI, subnet or security-group errors.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Delete only the temporary `karpenter-test` namespace created during validation. Keep Karpenter installed because later labs may depend on cluster autoscaling behavior.

## Next Steps
Continue with [Lab 12 - External Secrets Operator](./lab12-external-secrets-operator.md).
