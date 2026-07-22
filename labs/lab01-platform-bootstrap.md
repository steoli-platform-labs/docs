# Lab 01 - Platform Bootstrap

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Foundation |
| **Lab** | 01 |
| **Difficulty** | Beginner |
| **Estimated Time** | 20–30 minutes |
| **Estimated Cost** | Free |
| **Terraform** | No |
| **Kubernetes** | No |
| **GitOps** | No |

## Introduction

This lab prepares the local development environment and AWS account for the Platform Engineering project.

No cloud infrastructure is provisioned during this lab. Instead, the required development tools, AWS access and Git repositories are prepared for the remainder of the project.

This is the only lab that requires manual setup of the local workstation.

## Outcome

After completing this guide, you will have a verified local toolchain, authenticated AWS CLI access, a GitHub organization with seven repositories and a local workspace containing all repository clones.

This guide does not provision AWS infrastructure.

## Prerequisites

Before starting this lab, ensure you have:

- An AWS account
- A GitHub account
- Administrator permissions within the AWS account
- Permission to create a GitHub organization and repositories
- A workstation with administrative rights for software installation
- A terminal using Bash, Zsh or a compatible shell

Use short-lived AWS credentials where possible. AWS IAM Identity Center is preferred over long-lived IAM user access keys.

## Required Software

| Software | Purpose |
|----------|---------|
| Git | Source Control |
| Visual Studio Code | Code Editor |
| AWS CLI v2 | AWS Management |
| Terraform | Infrastructure as Code |
| Docker Desktop | Container Runtime |
| kubectl | Kubernetes CLI |
| Helm | Kubernetes Package Manager |

## Project Repository Structure

The project is organized into multiple repositories.

| Repository | Purpose |
|------------|---------|
| docs | Project documentation |
| platform-live | Platform infrastructure |
| platform-modules | Reusable Terraform modules |
| platform-bootstrap | Bootstrap infrastructure |
| platform-config | GitOps configuration |
| helm-charts | Helm charts |
| sample-api | Example application |

## Local Workspace

The recommended local directory structure is:

```text
platform-labs/

├── docs
├── platform-live
├── platform-modules
├── platform-bootstrap
├── platform-config
├── helm-charts
└── sample-api
```

## Architecture

At this stage no AWS infrastructure has been deployed.

The architecture currently consists of:

```text
Developer Workstation

│

├── Git

├── Visual Studio Code

├── AWS CLI

├── Terraform

├── Docker

├── kubectl

└── Helm

↓

GitHub

↓

AWS Account
```

## Implementation Overview

This lab consists of the following high-level tasks.

1. Install required software
2. Configure AWS CLI
3. Verify AWS connectivity
4. Create the GitHub repositories
5. Clone the repositories locally
6. Verify the development environment

## Repository Changes

| Repository | Change |
|------------|--------|
| docs | Existing documentation repository is prepared for the project |
| platform-bootstrap | Empty repository created for Lab 02 bootstrap infrastructure |
| platform-modules | Empty repository created for reusable Terraform modules |
| platform-live | Empty repository created for environment compositions |
| platform-config | Empty repository created for GitOps desired state |
| helm-charts | Empty repository created for custom Helm charts |
| sample-api | Empty repository created for the reference application |

## Files to Review

| File | Why it matters |
|------|----------------|
| `docs/README.md` | Entry point for the project documentation |
| `docs/architecture/repository-strategy.md` | Defines repository ownership and boundaries |
| `.gitignore` in each implementation repository | Prevents local state, credentials and generated files from being committed |
| `README.md` in each implementation repository | Records the initial purpose of each repository |

## Values Used in This Guide

Choose your values before running commands:

```bash
export GITHUB_ORG="<your-github-organization>"
export WORKSPACE="$HOME/dev/platform-labs"
export AWS_PROFILE="<your-aws-profile>"
export AWS_REGION="<your-aws-region>"
```

Use an AWS Region available to your account and compatible with later labs. Keep these values generic in committed documentation; use local shell exports or ignored local files for your personal values.

Do not commit account IDs, credentials or profile files to Git.

## Step-by-Step Implementation

Complete the setup steps below in order. This is the only lab that requires manual workstation and repository bootstrapping.

### Step 1 - Install and Verify Git

Install Git using the package manager for your operating system, then verify it:

```bash
git --version
```

Configure the identity that will appear in commits:

```bash
git config --global user.name "<your-name>"
git config --global user.email "<your-email>"
git config --global init.defaultBranch main
```

Validate:

```bash
git config --global --get user.name
git config --global --get user.email
git config --global --get init.defaultBranch
```

Expected result: all three commands return the values you configured.

### Step 2 - Install Visual Studio Code

Install Visual Studio Code from its official distribution channel.

Recommended extensions:

- HashiCorp Terraform
- YAML
- Docker
- Kubernetes
- GitHub Pull Requests
- Markdown All in One

Verify the command-line launcher when available:

```bash
code --version
```

If `code` is unavailable but the editor starts normally, enable the shell command from Visual Studio Code or continue using the graphical application.

### Step 3 - Install AWS CLI v2

Install AWS CLI v2 using the official installer for your operating system.

Verify:

```bash
aws --version
```

Expected result: the output starts with `aws-cli/2`.

### Step 4 - Configure AWS Authentication

### Preferred Method - AWS IAM Identity Center

Configure a named profile:

```bash
aws configure sso --profile "$AWS_PROFILE"
```

Provide the Start URL, SSO region, AWS account and role supplied by your AWS configuration.

Authenticate:

```bash
aws sso login --profile "$AWS_PROFILE"
```

Set the default region for the profile:

```bash
aws configure set region "$AWS_REGION" --profile "$AWS_PROFILE"
aws configure set output json --profile "$AWS_PROFILE"
```

### Alternative - Existing Short-Lived Credentials

When an approved mechanism already exports temporary credentials, keep the named profile and follow your organization's authentication process. Avoid creating long-lived access keys solely for this project.

### Step 5 - Verify AWS Identity

Run:

```bash
aws sts get-caller-identity --profile "$AWS_PROFILE"
```

Expected result:

```json
{
  "UserId": "...",
  "Account": "<your-aws-account-id>",
  "Arn": "arn:aws:..."
}
```

Record the account ID privately for later configuration, but do not add it to public documentation unless it is intentionally anonymized.

Confirm the selected region:

```bash
aws configure get region --profile "$AWS_PROFILE"
```

### Step 6 - Install Terraform

Install Terraform using the official HashiCorp package repository or a version manager.

Verify:

```bash
terraform version
```

Expected result: Terraform prints its installed version and platform.

The project will introduce explicit version constraints when Terraform code is added. Do not assume that an arbitrary old Terraform release is compatible.

### Step 7 - Install Docker

Install Docker Desktop or a compatible local Docker Engine.

Start Docker and verify:

```bash
docker version
docker run --rm hello-world
```

Expected result: both the client and server are reported and the test container completes successfully.

### Step 8 - Install kubectl

Install `kubectl` using the official Kubernetes installation method for your operating system.

Verify:

```bash
kubectl version --client
```

No cluster connection is expected in this lab.

### Step 9 - Install Helm

Install Helm 3 using its official package or installation method.

Verify:

```bash
helm version
```

Expected result: the version output reports Helm 3.

### Step 10 - Install GitHub CLI

GitHub CLI is strongly recommended because it makes repository creation and validation repeatable.

Verify:

```bash
gh --version
```

Authenticate:

```bash
gh auth login
```

Choose GitHub.com, HTTPS and browser-based authentication unless your environment requires a different approved method.

Validate:

```bash
gh auth status
```

### Step 11 - Create the GitHub Organization

Create or choose a GitHub organization for your lab repositories. The organization name must be globally unique on GitHub.

When using another name, update the shell variable:

```bash
export GITHUB_ORG="<your-github-organization>"
```

Recommended initial settings:

- Base permissions: Read
- Repository creation: restricted to organization owners during bootstrap
- Two-factor authentication: required when practical
- Discussions and projects: optional

### Step 12 - Create the Repositories

Create seven public repositories. Omit `--public` and use `--private` during development when you are not ready to publish.

```bash
for repo in \
  docs \
  platform-bootstrap \
  platform-modules \
  platform-live \
  platform-config \
  helm-charts \
  sample-api
do
  gh repo create "$GITHUB_ORG/$repo" \
    --public \
    --description "AWS Platform Engineering project - $repo" \
    --add-readme
 done
```

If the `docs` repository already exists, remove it from the loop or accept the expected error for that one repository.

Validate:

```bash
gh repo list "$GITHUB_ORG" --limit 20
```

Expected result: all seven repository names are listed.

### Step 13 - Create the Local Workspace

```bash
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"
```

Clone each repository:

```bash
for repo in \
  docs \
  platform-bootstrap \
  platform-modules \
  platform-live \
  platform-config \
  helm-charts \
  sample-api
do
  gh repo clone "$GITHUB_ORG/$repo"
done
```

Validate the directory structure:

```bash
find "$WORKSPACE" -maxdepth 1 -mindepth 1 -type d -print | sort
```

Expected state:

```text
platform-labs/
├── docs/
├── helm-charts/
├── platform-bootstrap/
├── platform-config/
├── platform-live/
├── platform-modules/
└── sample-api/
```

### Step 14 - Add Common Repository Files

For each new implementation repository, create a minimal `.gitignore` that prevents accidental commits of local secrets and generated files.

```bash
for repo in platform-bootstrap platform-modules platform-live platform-config helm-charts sample-api
do
  cat > "$WORKSPACE/$repo/.gitignore" <<'IGNORE'
.DS_Store
.vscode/
.idea/
.env
.env.*
*.local
*.log

# Terraform
.terraform/
*.tfstate
*.tfstate.*
crash.log
crash.*.log
*.tfplan

# Kubernetes and credentials
kubeconfig
*.kubeconfig

# Keys and certificates
*.pem
*.key
*.p12
IGNORE
done
```

The ignore file is intentionally broad at bootstrap. Repositories may refine it when their implementation is introduced.

### Step 15 - Add Initial Repository READMEs

Create a simple purpose statement in each empty repository. Example for `platform-bootstrap`:

```bash
cat > "$WORKSPACE/platform-bootstrap/README.md" <<'EOF_BOOTSTRAP'
# Platform Bootstrap

This repository contains the Terraform configuration used to create the remote state foundation for the AWS Platform Engineering project.

Implementation begins in Lab 02.
EOF_BOOTSTRAP
```

Use equivalent purpose statements for the remaining repositories based on [`../architecture/repository-strategy.md`](../architecture/repository-strategy.md).

Commit and push the initial files in each implementation repository:

```bash
for repo in platform-bootstrap platform-modules platform-live platform-config helm-charts sample-api
do
  cd "$WORKSPACE/$repo"
  git add README.md .gitignore
  git commit -m "bootstrap repository structure"
  git push origin main
done
```

Return to the workspace:

```bash
cd "$WORKSPACE"
```

Run the complete local validation:

```bash
set -e

git --version
aws --version
terraform version
docker version
kubectl version --client
helm version
gh auth status
aws sts get-caller-identity --profile "$AWS_PROFILE"
gh repo list "$GITHUB_ORG" --limit 20
```

Validate that every local repository has a clean working tree:

```bash
for repo in docs platform-bootstrap platform-modules platform-live platform-config helm-charts sample-api
do
  echo "--- $repo ---"
  git -C "$WORKSPACE/$repo" status --short
done
```

## Expected Results

The workstation has the required tools installed, AWS CLI authentication works, all seven repositories exist locally and remotely, and each implementation repository contains an initial `README.md` and `.gitignore`.

## Validation

Passing result:

- Every required tool returns a version.
- Docker can communicate with its engine.
- AWS STS returns the intended account and principal.
- GitHub CLI reports an authenticated session.
- All seven repositories exist remotely and locally.
- `git status --short` produces no output for committed repositories.

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|--------------|------------|
| `aws sts get-caller-identity` fails | SSO session expired or wrong profile | Run `aws sso login --profile "$AWS_PROFILE"` and verify the profile name |
| `docker version` shows client only | Docker engine is not running | Start Docker Desktop or the Docker service |
| `gh repo create` returns already exists | Repository was created previously | Continue and verify it with `gh repo view` |
| `gh repo clone` fails | Authentication or organization permissions | Run `gh auth status` and confirm organization access |
| `terraform: command not found` | Installation path is missing | Reinstall using the official package method and restart the shell |
| Git commit rejects identity | Git name or email is not configured | Configure `user.name` and `user.email` globally or locally |
| Repository contains secret files | Ignore rules were added too late | Remove files from Git tracking and rotate any exposed credential |

## Final Repository State

```text
$HOME/dev/platform-labs/
├── docs/
├── helm-charts/
│   ├── .gitignore
│   └── README.md
├── platform-bootstrap/
│   ├── .gitignore
│   └── README.md
├── platform-config/
│   ├── .gitignore
│   └── README.md
├── platform-live/
│   ├── .gitignore
│   └── README.md
├── platform-modules/
│   ├── .gitignore
│   └── README.md
└── sample-api/
    ├── .gitignore
    └── README.md
```

## Best Practices

This lab follows several Platform Engineering best practices.

- Use Infrastructure as Code whenever possible.
- Keep development environments consistent.
- Store all source code in Git.
- Use version control from the beginning of the project.
- Separate documentation from implementation repositories.

## Cleanup

No cleanup is required.

Everything created during this lab will be used throughout the remainder of the project.

## References

- [AWS CLI User Guide](https://docs.aws.amazon.com/cli/latest/userguide/)
- [Terraform Documentation](https://developer.hashicorp.com/terraform/docs)
- [Git Documentation](https://git-scm.com/doc)
- [Helm Documentation](https://helm.sh/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## Next Steps

Continue with [Lab 02 - Terraform Backend](./lab02-terraform-backend.md).
