# Lab 19 - Full Cleanup and Decommission

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Operations |
| **Lab** | 19 |
| **Difficulty** | Advanced |
| **Estimated Time** | 45-90 minutes |
| **Estimated Cost** | Reduces ongoing cost |
| **Primary Tools** | kubectl, Argo CD, AWS CLI, Terraform |

## Introduction

This lab decommissions the complete platform built in Labs 01-18.

Cleanup is part of platform engineering. It proves you know what was created, which system owns each resource and how to remove it without leaving cost-generating infrastructure behind.

This lab has two cleanup levels. The standard cleanup removes Kubernetes workloads, Argo CD Applications, lab secrets and the Development infrastructure. The optional full account cleanup also removes the Terraform bootstrap backend after you no longer need any lab state.

Concepts reinforced in this lab include ownership, GitOps shutdown order, Terraform destroy, remote state, finalizers, cloud cost verification and safe decommissioning. See the [Concepts Reference](../concepts/README.md) for the platform components you are removing.

## Outcome

Remove the lab platform resources from the AWS account and verify that no expected cost-generating leftovers remain.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 18 completed.
- AWS CLI, Terraform, kubectl, Helm and GitHub CLI installed.
- Access to the same AWS account, Region and local workspace used for the earlier labs.
- A clear decision on whether you want to keep or remove the Terraform bootstrap backend.

## Files to Review

Review these files before cleanup:

- `platform-live/environments/dev`: Terraform root module for the Development VPC, EKS cluster, IAM roles and supporting resources.
- `platform-bootstrap`: Terraform backend bucket and bootstrap validation scripts.
- `platform-config/bootstrap/root-application-*.yaml`: Argo CD environment root Applications.
- `platform-config/environments/namespaces.yaml`: namespaces created for the platform environments.
- `platform-config/chaos/delete-pod.yaml`: one-off chaos resources from Lab 18.

## Step-by-Step Implementation

1. Confirm you are targeting the intended account, Region and cluster:

   ```bash
   cd "$WORKSPACE"
   export AWS_PAGER=""

   printf '\n===== AWS identity =====\n'
   aws sts get-caller-identity --profile "$AWS_PROFILE"
   printf '\n===== AWS region =====\n'
   aws configure get region --profile "$AWS_PROFILE"
   printf '\n===== kubectl context =====\n'
   kubectl config current-context
   printf '\n===== Current nodes =====\n'
   kubectl get nodes
   ```

   This is the safety check before destructive work. Continue only if the AWS account, Region and Kubernetes context match the lab environment. Stop immediately if any value points at a shared or production environment.

2. Stop temporary local activity and remove temporary Kubernetes resources:

   ```bash
   printf '\n===== Remove Lab 16 rollout demo namespace =====\n'
   kubectl delete namespace sample-api-rollout-demo --ignore-not-found
   printf '\n===== Remove Lab 11 Karpenter test namespace =====\n'
   kubectl delete namespace karpenter-test --ignore-not-found
   printf '\n===== Remove Lab 14 denied-test namespace =====\n'
   kubectl delete namespace network-denied-test --ignore-not-found
   printf '\n===== Remove Lab 18 chaos resources =====\n'
   kubectl delete -f platform-config/chaos/delete-pod.yaml --ignore-not-found
   printf '\n===== Remove temporary rendered files =====\n'
   rm -f /tmp/sample-api-rendered.yaml /tmp/sample-api-ha.yaml /tmp/sample-api-rollout.yaml /tmp/sample-api-rollout-demo.yaml /tmp/sample-api-networkpolicy.yaml
   ```

   Close any terminal still running `kubectl port-forward`, `kubectl get ... -w` or continuous curl loops. These local processes do not usually create cloud cost, but they can confuse cleanup validation if they keep printing stale errors.

3. Remove lab-only AWS Secrets Manager values:

   ```bash
   export AWS_REGION="${AWS_REGION:-$(aws configure get region --profile "$AWS_PROFILE")}"

   printf '\n===== Schedule sample-api lab secrets for deletion =====\n'
   for secret in \
     platform-labs/sample-api-dev \
     platform-labs/sample-api-staging \
     platform-labs/sample-api-production
   do
     aws secretsmanager delete-secret \
       --secret-id "$secret" \
       --recovery-window-in-days 7 \
       --region "$AWS_REGION" \
       --profile "$AWS_PROFILE" || true
   done

   printf '\n===== Secret deletion status =====\n'
   aws secretsmanager list-secrets \
     --region "$AWS_REGION" \
     --profile "$AWS_PROFILE" \
     --query 'SecretList[?starts_with(Name, `platform-labs/sample-api`)].{Name:Name,DeletedDate:DeletedDate}' \
     --output table
   ```

   These secrets contain non-sensitive lab values, but they are still account resources. AWS Secrets Manager uses a recovery window by default; seeing a `DeletedDate` means deletion is scheduled.

4. Delete Argo CD root Applications so GitOps stops reconciling workloads:

   ```bash
   printf '\n===== Delete environment root Applications =====\n'
   kubectl -n argocd delete application \
     platform-root-production \
     platform-root-staging \
     platform-root-dev \
     --ignore-not-found

   printf '\n===== Remaining Argo CD Applications =====\n'
   kubectl -n argocd get applications.argoproj.io || true
   ```

   Argo CD continuously tries to make the cluster match Git. Deleting the root Applications first prevents Argo CD from recreating child Applications while you are tearing down the cluster.

5. Delete workload and platform namespaces from Kubernetes:

   ```bash
   printf '\n===== Delete workload namespaces =====\n'
   kubectl delete namespace \
     sample-api-production \
     sample-api-staging \
     sample-api-dev \
     monitoring \
     external-secrets \
     karpenter \
     argo-rollouts \
     argocd \
     ingress-nginx \
     --ignore-not-found

   printf '\n===== Remaining lab namespaces =====\n'
   kubectl get namespaces
   ```

   Namespace deletion can take time because Kubernetes must remove namespaced resources and finalizers. If a namespace stays `Terminating`, inspect it before destroying the cluster so you understand what is blocking cleanup.

6. Confirm Karpenter-created capacity is gone or no longer needed:

   ```bash
   printf '\n===== Remaining NodeClaims =====\n'
   kubectl get nodeclaim || true
   printf '\n===== Current nodes =====\n'
   kubectl get nodes -o wide
   ```

   Karpenter-created nodes may remain briefly while workloads terminate. This check helps you see whether extra capacity from Lab 11 is still present before Terraform destroys the cluster and node infrastructure.

7. Destroy the Development Terraform environment:

   ```bash
   cd "$WORKSPACE/platform-live/environments/dev"

   printf '\n===== Terraform init =====\n'
   terraform init -backend-config=backend.hcl
   printf '\n===== Terraform destroy plan =====\n'
   terraform plan -destroy -out=tf-destroy-plan
   printf '\n===== Terraform destroy apply =====\n'
   terraform apply tf-destroy-plan
   ```

   Review the destroy plan carefully before applying. It should remove the Development VPC, EKS cluster, managed node group, IAM roles and related resources created by the live environment. This is intentionally destructive.

8. Verify the Development environment is destroyed:

   ```bash
   printf '\n===== Terraform post-destroy check =====\n'
   terraform plan -detailed-exitcode
   printf '\n===== EKS clusters in region =====\n'
   aws eks list-clusters --region "$AWS_REGION" --profile "$AWS_PROFILE"
   printf '\n===== NAT gateways in region =====\n'
   aws ec2 describe-nat-gateways \
     --region "$AWS_REGION" \
     --profile "$AWS_PROFILE" \
     --query 'NatGateways[].{Id:NatGatewayId,State:State,VpcId:VpcId}' \
     --output table
   ```

   `terraform plan -detailed-exitcode` should return `0` after a clean destroy. If it returns `2`, Terraform still sees resources or changes. If it returns `1`, troubleshoot the error before assuming cleanup is complete.

9. Check for common cost-generating leftovers:

   ```bash
   printf '\n===== Load balancers =====\n'
   aws elbv2 describe-load-balancers \
     --region "$AWS_REGION" \
     --profile "$AWS_PROFILE" \
     --query 'LoadBalancers[].{Name:LoadBalancerName,State:State.Code,VpcId:VpcId}' \
     --output table

   printf '\n===== Elastic IP addresses =====\n'
   aws ec2 describe-addresses \
     --region "$AWS_REGION" \
     --profile "$AWS_PROFILE" \
     --query 'Addresses[].{PublicIp:PublicIp,AllocationId:AllocationId,AssociationId:AssociationId}' \
     --output table

   printf '\n===== EBS volumes not in use =====\n'
   aws ec2 describe-volumes \
     --region "$AWS_REGION" \
     --profile "$AWS_PROFILE" \
     --filters Name=status,Values=available \
     --query 'Volumes[].{VolumeId:VolumeId,Size:Size,State:State}' \
     --output table
   ```

   Empty tables are the expected result for these checks in a dedicated lab account and Region. If resources remain, inspect tags and ownership before deleting them manually.

10. Optional: remove the Terraform bootstrap backend after all lab state is no longer needed:

   ```bash
   cd "$WORKSPACE/platform-bootstrap"

   printf '\n===== Bootstrap Terraform init =====\n'
   terraform init
   printf '\n===== Bootstrap destroy plan =====\n'
   terraform plan -destroy -out=tf-bootstrap-destroy-plan
   printf '\n===== Bootstrap destroy apply =====\n'
   terraform apply tf-bootstrap-destroy-plan
   ```

   Only run this step if you are done with the whole lab series and no other Terraform root uses the backend bucket. Removing the backend bucket can make future state inspection impossible unless you saved the information elsewhere.

## Expected Results

The Development platform is removed, GitOps is no longer reconciling lab workloads, lab-only secrets are scheduled for deletion and common cost-generating resources are gone from the target AWS account and Region.

## Validation

- Temporary namespaces and chaos resources are removed.
- Argo CD root Applications are deleted before cluster teardown.
- Terraform destroy for `platform-live/environments/dev` completes successfully.
- `terraform plan -detailed-exitcode` returns `0` after destroy.
- EKS clusters, NAT gateways, load balancers, unassociated Elastic IPs and unused EBS volumes are absent unless intentionally retained.
- Lab Secrets Manager values are scheduled for deletion or already deleted.
- Optional bootstrap backend cleanup is performed only when no longer needed.

## Troubleshooting

Start with the owner of the resource that will not delete:

```bash
printf '\n===== Terraform state =====\n'
terraform state list || true
printf '\n===== Kubernetes namespaces =====\n'
kubectl get namespaces || true
printf '\n===== AWS identity =====\n'
aws sts get-caller-identity --profile "$AWS_PROFILE"
```

If Terraform destroy fails:

- Read the first AWS error carefully; dependency errors usually mean another resource still references the object.
- Re-run `terraform plan -destroy` after deleting Kubernetes load balancer Services, because cloud load balancers can lag behind Kubernetes deletion.
- Do not delete Terraform state files to make errors disappear. Fix the underlying resource or import/remove state deliberately only if you understand the consequence.

If namespaces are stuck terminating:

- Inspect finalizers and events for the namespace.
- Confirm the API server is still reachable before destroying EKS.
- Delete GitOps roots first so controllers do not recreate resources while cleanup is in progress.

If AWS resources remain after Terraform destroy:

- Check tags and names to confirm whether they belong to this lab.
- Look for Kubernetes-created load balancers, EBS volumes or security groups that may outlive their Service briefly.
- Wait a few minutes and re-run the verification commands before manual deletion.

## Final Repository State

The reference repositories remain unchanged by learner cleanup. Local generated files such as plans, rendered manifests, backend configuration and tfvars remain ignored.

## Cleanup

This lab is the cleanup. Keep your local repository clones if you want to inspect the reference implementation later, or remove the workspace directory after confirming no secrets, state files or local credentials need to be preserved.

## Next Steps

The lab series is complete. Review the architecture, cost and operational tradeoffs before adapting the reference platform to a real organization.
