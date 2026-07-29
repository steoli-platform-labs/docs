# Lab 02 - Terraform Backend

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Foundation |
| **Lab** | 02 |
| **Difficulty** | Beginner |
| **Estimated Time** | 20-30 minutes |
| **Primary Tools** | Terraform, AWS CLI |

## Introduction

This lab creates the S3 bucket used as the Terraform remote backend for later labs.

This lab starts AWS billing for the backend bucket and stored state objects. The resources are small, but they remain in the account until the final cleanup lab removes the bootstrap backend.

`platform-bootstrap` starts with local state because it is responsible for creating the backend bucket. After the bucket exists, the bootstrap state is migrated into that bucket.

Concepts introduced in this lab include Terraform state, remote backends, S3 backend buckets and state locking. See the [Concepts Reference](../concepts/README.md) for the background behind these terms.

## Outcome

After this lab, `platform-bootstrap` manages the S3 Terraform backend bucket and its own state has been migrated from local state to that backend.

## Prerequisites

- Lab 01 completed.
- Terraform 1.10 or later and AWS CLI installed.
- AWS CLI authenticated.
- Access to create S3 resources in the target AWS account.
- Confirm you are using the intended AWS account, AWS profile and Region before creating the backend bucket.

## Architecture

```text
platform-bootstrap
  -> local terraform.tfstate
  -> creates S3 backend bucket
  -> migrates bootstrap state to S3

later labs
  -> use the S3 backend bucket
```

## Files to Review

`platform-bootstrap` owns the backend bucket for these labs. It does not commit `backend.tf`; the migration script creates a local ignored `backend.tf` only after the bucket exists.

| File | Why it matters |
|------|----------------|
| `platform-bootstrap/main.tf` | Defines the backend bucket resources |
| `platform-bootstrap/variables.tf` | Captures configurable account and naming inputs |
| `platform-bootstrap/outputs.tf` | Exposes the backend bucket information used by later labs |
| `platform-bootstrap/scripts/migrate-state.sh` | Creates the local backend configuration and migrates state |
| `platform-bootstrap/terraform.tfvars.example` | Shows the local values to copy into ignored `terraform.tfvars` |

## Step-by-Step Implementation

1. Set your shell values:

   ```bash
   export WORKSPACE="$HOME/dev/platform-labs"
   export AWS_PROFILE="<your-aws-profile>"
   export AWS_REGION="<your-aws-region>"
   export PROJECT_NAME="<project-name>"
   export AWS_DEFAULT_REGION="$AWS_REGION"
   export AWS_PAGER=""
   ```

2. Confirm AWS access:

   ```bash
   aws sts get-caller-identity --profile "$AWS_PROFILE"
   ```

   Expected output includes the AWS account ID and ARN for the account you intend to use for the labs. Stop if the account ID or profile is wrong; Terraform provider account guards will fail later, and creating resources in the wrong account is harder to unwind.

3. Open the bootstrap repository:

   ```bash
   cd "$WORKSPACE/platform-bootstrap"
   ```

4. Create local variables:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

   The `.example` file is a safe template committed to Git. `terraform.tfvars` is your local copy with account-specific values, and it is ignored by Git so you do not publish personal account IDs, names or tags.

   Edit `terraform.tfvars`:

   ```hcl
   aws_region          = "<your-aws-region>"
   allowed_account_ids = "<your-aws-account-id>"
   project_name        = "<project-name>"

   additional_tags = {
     Owner      = "<owner-or-team>"
     CostCenter = "<cost-center>"
   }
   ```

   Set `allowed_account_ids` to the AWS account ID returned by `aws sts get-caller-identity`.

5. Create the backend bucket using local state:

   ```bash
   printf '\n===== Terraform init =====\n'
   terraform init
   printf '\n===== Terraform format =====\n'
   terraform fmt -recursive
   printf '\n===== Terraform validate =====\n'
   terraform validate
   printf '\n===== Terraform plan =====\n'
   terraform plan
   printf '\n===== Terraform apply =====\n'
   terraform apply
   ```

   In this Terraform flow, `init` prepares the working directory and downloads providers, `fmt` normalizes formatting, `validate` checks the configuration syntax, `plan` previews what Terraform will change and `apply` performs the reviewed plan.

   Review the plan before applying. It should create only the bootstrap backend resources, such as the S3 bucket and related configuration, in the intended Region and account. Stop on any destroy action, unexpected bucket name or wrong account/Region.

6. Migrate the bootstrap state to S3:

   ```bash
   ./scripts/migrate-state.sh
   ```

   Expected behavior: the script creates local backend configuration, reinitializes Terraform with the S3 backend and migrates the bootstrap state. If migration is interrupted or Terraform reports backend/state errors, stop and inspect before deleting any local or remote state files.

   Terraform state is Terraform's inventory of the infrastructure it manages. This step moves that inventory from your laptop into S3 so later runs use the same source of truth instead of depending on one local file.

7. Validate the backend:

   ```bash
   printf '\n===== Backend validation script =====\n'
   ./scripts/validate.sh
   printf '\n===== Terraform drift check =====\n'
   terraform plan -detailed-exitcode
   ```

   Expected result:

   ```text
   Validation passed.
   Remote state: s3://<bucket>/bootstrap/terraform.tfstate
   ```

   `terraform plan -detailed-exitcode` should exit with code `0` when there are no pending changes.

   Exit code `0` means no drift and you can continue. Exit code `2` means Terraform sees changes; review the plan and stop before moving on. Exit code `1` means an error occurred and should be troubleshot first.

8. Confirm backend safety boundaries.

   The backend bootstrap creates local helper files and Terraform state artifacts while it is setting up the remote state bucket. Those files must not become source-controlled inputs. Check only the risk-bearing filenames:

   ```bash
   printf '\n===== Ignored local files check =====\n'
   git ls-files backend.hcl terraform.tfvars terraform.tfstate terraform.tfstate.backup
   ```

   This command should print nothing. If it prints a filename, Git is tracking a local backend, variable or state file and you should stop before continuing. The learning point is state safety: Terraform state belongs in the configured S3 backend, and personal input files belong outside version control.

## Expected Results

The backend bucket exists with versioning, encryption and Block Public Access enabled. Terraform state for `platform-bootstrap` is stored remotely at `bootstrap/terraform.tfstate`, while local generated files remain ignored.

## Validation

- `terraform validate` succeeds.
- The S3 backend bucket exists.
- Bucket versioning is enabled.
- Bucket encryption is enabled.
- Block Public Access is enabled.
- Remote state exists at `bootstrap/terraform.tfstate`.
- `terraform plan -detailed-exitcode` returns `0`.

## Troubleshooting

- **Backend initialization required:** If Terraform reports `Backend initialization required` before the bucket exists, remove any old local backend file and initialize again:

   ```bash
   rm -f backend.tf
   terraform init
   ```

   `backend.tf` should only exist locally after `./scripts/migrate-state.sh` has run.

- **Bucket name already exists:** S3 bucket names are globally unique. Set a custom name in `terraform.tfvars`:

   ```hcl
   state_bucket_name = "<project-name>-<unique-suffix>-tfstate"
   ```

   Then rerun:

   ```bash
   printf '\n===== Terraform plan =====\n'
   terraform plan
   printf '\n===== Terraform apply =====\n'
   terraform apply
   ```

- **State migration was interrupted:** Do not delete either state copy.

   Use this recovery flow:

   1. Stop all Terraform runs and confirm no other operator is using the backend.
   2. Back up the local `terraform.tfstate` and the remote S3 object before changing anything.
   3. Compare state `lineage` and `serial` values to identify the latest valid state.
   4. Reinitialize Terraform with the intended backend using `terraform init -reconfigure`.
   5. Use `terraform state push <verified-file>` only as a final controlled recovery step after reviewing `terraform state push -dry-run <verified-file>`.

   Never use `-lock=false` during recovery and never delete a state object before a verified backup exists.

   For native S3 lock issues, confirm no active Terraform process owns the lock before running:

   ```bash
   LOCK_ID="<copy-from-terraform-error-after-confirming-no-active-run>"
   terraform force-unlock "$LOCK_ID"
   ```

## Final Repository State

At completion, `platform-bootstrap` contains the Terraform code and scripts for the backend foundation, while `terraform.tfvars`, `backend.tf`, `backend.hcl`, state files and `.terraform/` remain local or ignored.

## Cleanup

No cleanup is required.

The backend bucket is shared lab infrastructure. It remains in place for later Terraform labs and is removed during final cleanup in Lab 19.

Do not commit local generated files:

- `terraform.tfvars`
- `terraform.tfstate`
- `terraform.tfstate.*`
- `backend.tf`
- `backend.hcl`
- `.terraform/`

## Next Steps

Continue with [Lab 03 - AWS Networking](./lab03-aws-networking.md). Lab 03 uses this S3 bucket as its remote Terraform backend.
