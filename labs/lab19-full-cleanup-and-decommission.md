# Lab 19 - Full Cleanup and Decommission

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Operations |
| **Lab** | 19 |
| **Difficulty** | Advanced |
| **Estimated Time** | 45-90 minutes |
| **Primary Tools** | kubectl, Argo CD, AWS CLI, Terraform |

## Introduction

This lab decommissions the complete platform built in Labs 01-18.

Cleanup is part of platform engineering. It proves you know what was created, which system owns each resource and how to remove it without leaving cost-generating infrastructure behind.

This lab removes Kubernetes workloads, Argo CD Applications, lab secrets, the shared AWS infrastructure and the Terraform bootstrap backend.

Concepts reinforced in this lab include ownership, GitOps shutdown order, Terraform destroy, remote state, finalizers and safe decommissioning. See the [Concepts Reference](../concepts/README.md) for the platform components you are removing.

## Outcome

Remove the lab platform resources from the AWS account and verify that the Terraform-managed shared AWS infrastructure is gone.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 18 completed.
- AWS CLI, Terraform, kubectl, Helm and GitHub CLI installed.
- Access to the same AWS account, Region and local workspace used for the earlier labs.
- No other Terraform root modules depend on the bootstrap backend bucket.

## Files to Review

Review these files before cleanup:

- `platform-live/environments/shared`: Terraform root module for the shared VPC, EKS cluster, IAM roles and supporting resources.
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
     platform-labs/sample-api \
     platform-labs/sample-api-dev \
     platform-labs/sample-api-staging \
     platform-labs/sample-api-production
   do
     if aws secretsmanager describe-secret --secret-id "$secret" --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
       aws secretsmanager delete-secret \
         --secret-id "$secret" \
         --recovery-window-in-days 7 \
         --region "$AWS_REGION" \
         --profile "$AWS_PROFILE"
     else
       printf 'Secret not found, skipping: %s\n' "$secret"
     fi
   done

   printf '\n===== Secret deletion status =====\n'
   aws secretsmanager list-secrets \
     --include-planned-deletion \
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

5. Delete workload namespaces first, then platform namespaces that do not own node lifecycle:

   ```bash
   printf '\n===== Delete workload namespaces =====\n'
   kubectl delete namespace \
     sample-api-production \
     sample-api-staging \
     sample-api-dev \
     --ignore-not-found \
     --wait=false

   printf '\n===== Wait for workload namespaces to disappear =====\n'
   kubectl wait --for=delete namespace/sample-api-production --timeout=10m || true
   printf '\n===== Wait for staging namespace to disappear =====\n'
   kubectl wait --for=delete namespace/sample-api-staging --timeout=10m || true
   printf '\n===== Wait for dev namespace to disappear =====\n'
   kubectl wait --for=delete namespace/sample-api-dev --timeout=10m || true

   printf '\n===== Delete platform namespaces =====\n'
   kubectl delete namespace \
     monitoring \
     external-secrets \
     argo-rollouts \
     argocd \
     ingress-nginx \
     --ignore-not-found

   printf '\n===== Remaining lab namespaces =====\n'
   kubectl get namespaces
   ```

   Delete workload namespaces before `external-secrets` so External Secrets Operator and its webhook are still available to clean up `ExternalSecret` finalizers. Keep the `karpenter` namespace for the next step because the Karpenter controller owns Karpenter node termination. Namespace deletion can take time because Kubernetes must remove namespaced resources and finalizers. If a namespace stays `Terminating`, inspect it before destroying the cluster so you understand what is blocking cleanup.

6. Remove Karpenter-created capacity while Karpenter is still running:

   ```bash
   printf '\n===== Remaining NodeClaims =====\n'
   kubectl get nodeclaim || true

   nodeclaims="$(kubectl get nodeclaim -o name 2>/dev/null || true)"
   if [ -n "$nodeclaims" ]; then
     printf '\n===== Delete Karpenter NodeClaims =====\n'
     kubectl delete $nodeclaims

     printf '\n===== Wait for Karpenter NodeClaims to disappear =====\n'
     kubectl wait --for=delete $nodeclaims --timeout=10m
   else
     printf 'No Karpenter NodeClaims found.\n'
   fi

   printf '\n===== Delete Karpenter namespace =====\n'
   kubectl delete namespace karpenter --ignore-not-found

   printf '\n===== Current nodes =====\n'
   kubectl get nodes -o wide
   ```

   Karpenter-created nodes may remain briefly while workloads terminate. Delete any remaining `NodeClaim` objects before deleting the `karpenter` namespace so the Karpenter controller can drain the node, terminate the EC2 instance and remove its finalizers. After this step, the node list should show only the managed node group nodes that Terraform will destroy in the next step.

7. Destroy the shared Terraform infrastructure:

   ```bash
   cd "$WORKSPACE/platform-live/environments/shared"

   printf '\n===== Terraform init =====\n'
   terraform init -backend-config=backend.hcl
   printf '\n===== Terraform destroy plan =====\n'
   terraform plan -destroy
   printf '\n===== Terraform destroy apply =====\n'
   terraform destroy
   ```

   Review the destroy plan carefully before applying. It should remove the shared VPC, EKS cluster, managed node group, IAM roles and related resources created by the live environment. This is intentionally destructive.

8. Verify the shared infrastructure state is empty and the AWS resources are gone:

   ```bash
   printf '\n===== Terraform state after destroy =====\n'
   terraform state list
   printf '\n===== EKS clusters in region =====\n'
   aws eks list-clusters --region "$AWS_REGION" --profile "$AWS_PROFILE"
   printf '\n===== NAT gateways in region =====\n'
   aws ec2 describe-nat-gateways \
     --region "$AWS_REGION" \
     --profile "$AWS_PROFILE" \
     --query 'NatGateways[].{Id:NatGatewayId,State:State,VpcId:VpcId}' \
     --output table
   ```

   `terraform state list` should print no managed resources after a clean destroy. A normal `terraform plan` after destroy will usually show resources to create again because the configuration still describes the desired shared AWS infrastructure; that does not mean destroy failed. Use AWS checks to confirm the previously managed resources are actually gone. AWS may return recently deleted NAT gateways for a short time; `State` should be `deleted` if the lab NAT gateway has already been removed.

9. Remove the Terraform bootstrap backend:

   The bootstrap backend needs one extra safeguard because it stores Terraform's own state. Migrate the bootstrap state back to local state first so Terraform does not try to write its final state into the same S3 bucket it is destroying.

   `force_destroy_state_bucket` defaults to `true` in the reference bootstrap configuration so Terraform can remove the versioned state bucket and its object versions during this final cleanup. If your local `terraform.tfvars` was created before that setting existed, add `force_destroy_state_bucket = true` before planning the destroy.

   ```bash
   cd "$WORKSPACE/platform-bootstrap"

   printf '\n===== Disable remote backend for final teardown =====\n'
   mv backend.tf backend.tf.disabled

   printf '\n===== Migrate bootstrap state back to local state =====\n'
   terraform init -migrate-state -force-copy

   printf '\n===== Confirm bootstrap state is local and readable =====\n'
   terraform state list
   ```

   Empty all object versions and delete markers from the versioned backend bucket before destroying it:

   ```bash
   bucket="$(
     terraform state show -no-color aws_s3_bucket.terraform_state \
       | awk -F' = ' '/^[[:space:]]*bucket[[:space:]]*=/{gsub(/"/, "", $2); print $2; exit}'
   )"

   if [ -z "$bucket" ]; then
     printf 'Could not determine backend bucket name from Terraform state.\n'
     exit 1
   fi

   printf '\n===== Delete current and previous state object versions =====\n'
   while read -r key version_id; do
     if [ -n "$key" ] && [ "$key" != "None" ]; then
       aws s3api delete-object \
         --bucket "$bucket" \
         --key "$key" \
         --version-id "$version_id" \
         --region "$AWS_REGION" \
         --profile "$AWS_PROFILE"
     fi
   done < <(aws s3api list-object-versions \
     --bucket "$bucket" \
     --query 'Versions[].[Key,VersionId]' \
     --output text \
     --region "$AWS_REGION" \
     --profile "$AWS_PROFILE")

   printf '\n===== Delete state bucket delete markers =====\n'
   while read -r key version_id; do
     if [ -n "$key" ] && [ "$key" != "None" ]; then
       aws s3api delete-object \
         --bucket "$bucket" \
         --key "$key" \
         --version-id "$version_id" \
         --region "$AWS_REGION" \
         --profile "$AWS_PROFILE"
     fi
   done < <(aws s3api list-object-versions \
     --bucket "$bucket" \
     --query 'DeleteMarkers[].[Key,VersionId]' \
     --output text \
     --region "$AWS_REGION" \
     --profile "$AWS_PROFILE")

   printf '\n===== Confirm state bucket is empty =====\n'
   aws s3api list-object-versions \
     --bucket "$bucket" \
     --query '{Versions:Versions,DeleteMarkers:DeleteMarkers}' \
     --output table \
     --region "$AWS_REGION" \
     --profile "$AWS_PROFILE"
   ```

   Then destroy the bootstrap resources:

   ```bash
   printf '\n===== Bootstrap destroy plan =====\n'
   terraform plan -destroy
   printf '\n===== Bootstrap destroy apply =====\n'
   terraform destroy
   ```

   Removing the backend bucket can make future state inspection impossible unless you saved the information elsewhere. The local `terraform.tfstate` and disabled backend file are local teardown artifacts; keep or remove the local workspace according to your preference after the AWS resources are gone.

## Expected Results

The shared AWS infrastructure is removed, GitOps is no longer reconciling lab workloads, lab-only secrets are scheduled for deletion and the Terraform bootstrap backend is removed.

## Validation

- Temporary namespaces and chaos resources are removed.
- Argo CD root Applications are deleted before cluster teardown.
- Terraform destroy for `platform-live/environments/shared` completes successfully.
- `terraform state list` prints no managed resources after destroy.
- The shared EKS cluster and active lab NAT gateways are absent.
- Lab Secrets Manager values are scheduled for deletion or already deleted.
- Bootstrap backend cleanup removes the final Terraform state bucket.

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
- If bootstrap backend destroy fails because the S3 bucket is not empty, run the Step 9 bucket-emptying commands and then create a new destroy plan.
- If `terraform output -raw state_bucket_name` reports `No outputs found` after a partial bootstrap destroy, use the Step 9 state-based bucket lookup instead. The bucket resource can still be in state even when outputs are no longer available.
- Do not delete Terraform state files to make errors disappear. Fix the underlying resource or import/remove state deliberately only if you understand the consequence.

If namespaces are stuck terminating:

- Inspect finalizers and events for the namespace.
- Confirm the API server is still reachable before destroying EKS.
- Delete GitOps roots first so controllers do not recreate resources while cleanup is in progress.
- If the namespace condition mentions `external-secrets-webhook.external-secrets.svc` not found, the External Secrets webhook was removed before workload `ExternalSecret` objects finished deleting. During final decommission, remove the stale webhook configurations and then remove the orphaned `ExternalSecret` finalizers:

```bash
printf '\n===== Remove stale External Secrets webhooks =====\n'
kubectl delete validatingwebhookconfiguration externalsecret-validate secretstore-validate --ignore-not-found

printf '\n===== Remove orphaned ExternalSecret finalizers =====\n'
for ns in sample-api-dev sample-api-staging sample-api-production; do
  printf '\n===== Remove ExternalSecret finalizer in %s =====\n' "$ns"
  kubectl -n "$ns" patch externalsecret sample-api --type=merge -p '{"metadata":{"finalizers":[]}}' || true
done

printf '\n===== Namespace status after finalizer cleanup =====\n'
kubectl get namespaces
```

If a Karpenter `NodeClaim` is stuck terminating after the `karpenter` namespace was already deleted:

- This means the controller that normally removes the `karpenter.sh/termination` finalizer is gone.
- Confirm the node is only running system DaemonSet pods before manual cleanup.
- During final decommission, terminate the EC2 instance shown in the `NodeClaim` provider ID, then remove the orphaned Kubernetes finalizers:

```bash
nodeclaim="$(kubectl get nodeclaim -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [ -z "$nodeclaim" ]; then
  printf 'No Karpenter NodeClaim found.\n'
  exit 0
fi

node="$(kubectl get nodeclaim "$nodeclaim" -o jsonpath='{.status.nodeName}' 2>/dev/null || true)"
provider_id="$(kubectl get nodeclaim "$nodeclaim" -o jsonpath='{.status.providerID}' 2>/dev/null || true)"
instance_id="${provider_id##*/}"
if [ -z "$instance_id" ] || [ "$instance_id" = "$provider_id" ]; then
  printf 'Could not determine the EC2 instance ID from provider ID: %s\n' "$provider_id"
  exit 1
fi

printf '\n===== Pods on Karpenter node =====\n'
kubectl get pods -A -o wide --field-selector spec.nodeName="$node"

printf '\n===== Terminate orphaned Karpenter EC2 instance =====\n'
aws ec2 terminate-instances \
  --instance-ids "$instance_id" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE"

printf '\n===== Remove orphaned Karpenter finalizers =====\n'
kubectl patch nodeclaim "$nodeclaim" --type=merge -p '{"metadata":{"finalizers":[]}}'
kubectl patch node "$node" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
kubectl delete node "$node" --ignore-not-found
```

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
