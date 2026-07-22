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

## Outcome
Implement and validate Karpenter in the complete platform reference implementation.

## Before You Begin
Complete Lab 01 - Lab 10, configure AWS CLI, Terraform, kubectl, Helm and repository URLs.

## Repository Changes
Primary implementation: `platform-config/addons/karpenter`.

## Files to Review
Review the Karpenter desired-state files and update any environment-specific values before validation.

## Step-by-Step Implementation
1. Review `platform-config/clusters/dev/karpenter.yaml` and the manifests under `platform-config/addons/karpenter`.
2. Confirm the Karpenter chart, NodePool and EC2NodeClass values match the EKS cluster.
3. Commit and push any required `platform-config` changes.
4. Let Argo CD reconcile the `karpenter` Application from Git.
5. Validate Karpenter by creating a temporary unschedulable workload and observing node provisioning.

## Commands
```bash
cd "$WORKSPACE"
kubectl -n argocd get application karpenter -o wide
kubectl -n argocd annotate application karpenter argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd get application karpenter -o wide
```

## Expected Results
The `karpenter` Argo CD Application reconciles successfully and Karpenter can provision capacity for pending pods.

## Validation
### Karpenter verification

```bash
kubectl -n argocd get application karpenter -o wide
kubectl -n karpenter get pods
kubectl get nodepool,ec2nodeclass
kubectl describe nodepool default
kubectl describe ec2nodeclass default
kubectl -n karpenter logs deployment/karpenter --since=15m --tail=300
```

Create a temporary workload that cannot fit on existing nodes, then watch provisioning:

```bash
kubectl create namespace karpenter-test
kubectl -n karpenter-test create deployment inflate --image=public.ecr.aws/eks-distro/kubernetes/pause:3.10
kubectl -n karpenter-test scale deployment inflate --replicas=20
kubectl get pods,nodes -w
```

Pass criteria:

- Controller pods are ready and authenticated to AWS.
- NodePool and EC2NodeClass conditions report ready.
- Pending test pods cause a new node claim and EC2 instance to be created.
- Test pods become ready on the new node.
- After deleting the test deployment, consolidation removes unnecessary capacity according to the configured policy.
- Controller logs contain no IAM, subnet, security-group, AMI or instance-profile errors.

Clean up the `karpenter-test` namespace after validation:

```bash
kubectl delete namespace karpenter-test
```

## Troubleshooting
Start with the Argo CD Application, Karpenter controller and provisioning resources:

```bash
kubectl -n argocd describe application karpenter
kubectl -n karpenter get pods -o wide
kubectl get nodepool,ec2nodeclass,nodeclaim
kubectl -n karpenter logs deployment/karpenter --since=15m --tail=300
```

## Commit and Push
Use a focused conventional commit such as `feat: complete lab 11`.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Delete only the temporary `karpenter-test` namespace created during validation. Keep Karpenter installed because later labs may depend on cluster autoscaling behavior.

## Next Steps
Continue with [Lab 12 - External Secrets Operator](./lab12-external-secrets-operator.md).
