# Lab 02 - Terraform Backend

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Foundation |
| **Lab** | 02 |
| **Difficulty** | Beginner |
| **Estimated Time** | 20-30 minutes |
| **Estimated Cost** | Low |
| **Terraform** | Yes |
| **Kubernetes** | No |
| **GitOps** | No |

## Introduction

This lab creates the S3 bucket used as the Terraform remote backend for later labs.

`platform-bootstrap` starts with local state because it is responsible for creating the backend bucket. After the bucket exists, the bootstrap state is migrated into that bucket.

## Outcome

After this lab, `platform-bootstrap` manages the permanent S3 Terraform backend bucket and its own state has been migrated from local state to that backend.

## Prerequisites

- Lab 01 completed.
- AWS CLI authenticated.
- Terraform 1.10 or later installed.
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

## Repository Changes

| Repository | Responsibility |
|------------|----------------|
| `platform-bootstrap` | Creates and protects the backend bucket |
| `docs` | Documents the lab workflow |

`platform-bootstrap` does not commit `backend.tf`. The migration script creates a local ignored `backend.tf` only after the bucket exists.

## Files to Review

| File | Why it matters |
|------|----------------|
| `platform-bootstrap/main.tf` | Defines the backend bucket resources |
| `platform-bootstrap/variables.tf` | Captures configurable account and naming inputs |
| `platform-bootstrap/outputs.tf` | Exposes the backend bucket information used by later labs |
| `platform-bootstrap/scripts/migrate-state.sh` | Creates the local backend configuration and migrates state |
| `platform-bootstrap/terraform.tfvars.example` | Shows the local values to copy into ignored `terraform.tfvars` |

## Step-by-Step Implementation

Set your shell values:

```bash
export WORKSPACE="$HOME/dev/platform-labs"
export AWS_PROFILE="<your-aws-profile>"
export AWS_REGION="<your-aws-region>"
export PROJECT_NAME="<project-name>"
export AWS_DEFAULT_REGION="$AWS_REGION"
```

Confirm AWS access:

```bash
aws sts get-caller-identity --profile "$AWS_PROFILE"
```

Open the bootstrap repository:

```bash
cd "$WORKSPACE/platform-bootstrap"
```

Create local variables:

```bash
cp terraform.tfvars.example terraform.tfvars
```

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

Create the backend bucket using local state:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Migrate the bootstrap state to S3:

```bash
./scripts/migrate-state.sh
```

Validate the backend:

```bash
./scripts/validate.sh
terraform plan -detailed-exitcode
```

Expected result:

```text
Validation passed.
Remote state: s3://<bucket>/bootstrap/terraform.tfstate
```

`terraform plan -detailed-exitcode` should exit with code `0` when there are no pending changes.

Commit only source files and scripts. Do not commit local backend, state, variable or plan files:

```bash
git status
git diff --check
git add \
  .editorconfig \
  .gitignore \
  .terraform.lock.hcl \
  Makefile \
  README.md \
  data.tf \
  locals.tf \
  main.tf \
  outputs.tf \
  providers.tf \
  variables.tf \
  versions.tf \
  scripts/ \
  terraform.tfvars.example
git commit -m "complete lab 02 terraform backend"
git push
```

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

### Backend Initialization Required

If Terraform reports `Backend initialization required` before the bucket exists, remove any old local backend file and initialize again:

```bash
rm -f backend.tf
terraform init
```

`backend.tf` should only exist locally after `./scripts/migrate-state.sh` has run.

### Bucket Name Already Exists

S3 bucket names are globally unique. Set a custom name in `terraform.tfvars`:

```hcl
state_bucket_name = "<project-name>-<unique-suffix>-tfstate"
```

Then rerun:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

### State Migration Was Interrupted

Do not delete either state copy.

Use this recovery flow:

1. Stop all Terraform runs and confirm no other operator is using the backend.
2. Back up the local `terraform.tfstate` and the remote S3 object before changing anything.
3. Compare state `lineage` and `serial` values to identify the latest valid state.
4. Reinitialize Terraform with the intended backend using `terraform init -reconfigure`.
5. Use `terraform state push <verified-file>` only as a final controlled recovery step after reviewing `terraform state push -dry-run <verified-file>`.

Never use `-lock=false` during recovery and never delete a state object before a verified backup exists.

For native S3 lock issues, confirm no active Terraform process owns the lock before running:

```bash
terraform force-unlock <LOCK_ID>
```

## Final Repository State

At completion, `platform-bootstrap` contains the Terraform code and scripts for the backend foundation, while `terraform.tfvars`, `backend.tf`, `backend.hcl`, state files, plan files and `.terraform/` remain local or ignored.

## Cleanup

No cleanup is required.

The backend bucket is permanent platform infrastructure and is protected from normal Terraform destruction.

Do not commit local generated files:

- `terraform.tfvars`
- `terraform.tfstate`
- `terraform.tfstate.*`
- `tfplan`
- `backend.tf`
- `backend.hcl`
- `.terraform/`

## Next Steps

Continue with [Lab 03 - AWS Networking](./lab03-aws-networking.md). Lab 03 uses this S3 bucket as its remote Terraform backend.
