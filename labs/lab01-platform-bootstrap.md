# Lab 01 - Platform Bootstrap

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Foundation |
| **Lab** | 01 |
| **Difficulty** | Beginner |
| **Estimated Time** | 20–30 minutes |
| **Primary Tools** | Git, GitHub, AWS CLI, Terraform |

## Introduction

This lab prepares the local development environment and AWS account for the Platform Engineering project.

No cloud infrastructure is provisioned during this lab. Instead, the required development tools, AWS access and local clones of the public reference repositories are prepared for the remainder of the project.

This is the only lab that requires manual setup of the local workstation.

Concepts introduced in this lab include the multi-repository platform layout, local toolchain, AWS CLI authentication and reference repositories. See the [Concepts Reference](../concepts/README.md) for definitions used across the lab series.

## Outcome

After completing this guide, you will have a verified local toolchain, authenticated AWS CLI access and a local workspace containing all reference repository clones.

This guide does not provision AWS infrastructure.

## Prerequisites

Before starting this lab, ensure you have:

- An AWS account
- A GitHub account
- Administrator permissions within the AWS account
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
4. Verify access to the public reference repositories
5. Clone the repositories locally
6. Verify the development environment

## Files to Review

This lab prepares local access to the public reference repositories used by later labs.

| File | Why it matters |
|------|----------------|
| `docs/README.md` | Entry point for the project documentation |
| `docs/architecture/repository-strategy.md` | Defines repository ownership and boundaries |
| `.gitignore` in each implementation repository | Prevents local state, credentials and generated files from being committed |
| `README.md` in each implementation repository | Records the initial purpose of each repository |

## Values Used in This Guide

Use these values before running commands:

```bash
export GITHUB_ORG="steoli-platform-labs"
export WORKSPACE="$HOME/dev/platform-labs"
export AWS_PROFILE="<your-aws-profile>"
export AWS_REGION="<your-aws-region>"
```

Use an AWS Region available to your account and compatible with later labs. Keep these values generic in committed documentation; use local shell exports or ignored local files for your personal values.

Do not commit account IDs, credentials or profile files to Git.

## Step-by-Step Implementation

Complete the setup steps below in order. This is the only lab that requires manual workstation setup.

1. Install and verify Git.

   Install Git using the package manager for your operating system, then verify it:

   ```bash
   git --version
   ```

   Configure the default branch name used by local Git repositories:

   ```bash
   git config --global init.defaultBranch main
   ```

   This makes new local Git repositories use `main` as their first branch name. The reference repositories on GitHub also use `main`, so this avoids branch-name differences later when you compare local files with the published reference state.

   Validate:

   ```bash
   git config --global --get init.defaultBranch
   ```

   Expected result: the command returns `main`.

2. Install Visual Studio Code.

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

3. Install AWS CLI v2.

   Install AWS CLI v2 using the official installer for your operating system.

   Verify:

   ```bash
   aws --version
   ```

   Expected result: the output starts with `aws-cli/2`.

4. Configure AWS authentication.

   Preferred method: AWS IAM Identity Center.

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

   Continue only after the browser login completes successfully and the profile exists locally. If account or role selection fails, stop and fix AWS access before continuing; later labs assume this profile can create infrastructure.

   The `export` values used in these labs are temporary shortcuts for the current terminal session. The AWS profile tells the AWS CLI which account and role to use; the Region tells AWS where to create regional resources such as VPCs and EKS clusters.

   Alternative: existing short-lived credentials.

   When an approved mechanism already exports temporary credentials, keep the named profile and follow your organization's authentication process. Avoid creating long-lived access keys solely for this project.

5. Verify AWS identity.

   Run:

   ```bash
   export AWS_PAGER=""
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

   `AWS_PAGER=""` disables the AWS CLI pager so identity checks return directly to the terminal. Record the account ID privately for later configuration, but do not add it to public documentation unless it is intentionally anonymized.

   Confirm the selected region:

   ```bash
   aws configure get region --profile "$AWS_PROFILE"
   ```

6. Install Terraform.

   Install Terraform using the official HashiCorp package repository or a version manager.

   Verify:

   ```bash
   terraform version
   ```

   Expected result: Terraform prints its installed version and platform.

   The project will introduce explicit version constraints when Terraform code is added. Do not assume that an arbitrary old Terraform release is compatible.

7. Install Docker.

   Install Docker Desktop or a compatible local Docker Engine.

   Start Docker and verify:

   ```bash
   docker version
   docker run --rm hello-world
   ```

   Expected result: both the client and server are reported and the test container completes successfully.

8. Install `kubectl`.

   Install `kubectl` using the official Kubernetes installation method for your operating system.

   Verify:

   ```bash
   kubectl version --client
   ```

   No cluster connection is expected in this lab.

9. Install Helm.

   Install Helm 3 using its official package or installation method.

   Verify:

   ```bash
   helm version
   ```

   Expected result: the version output reports Helm 3.

10. Install GitHub CLI.

   GitHub CLI is strongly recommended because it makes repository and package access validation repeatable.

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

   Expected result: GitHub CLI reports that you are logged in to `github.com`, shows the intended GitHub username and has access through HTTPS. Stop if authentication is missing or points at the wrong account.

11. Verify access to the reference GitHub organization.

   The public `steoli-platform-labs/*` repositories are reference templates for this lab series. Learners inspect, apply and validate the committed reference state rather than pushing changes to shared repositories.

   Confirm the reference organization value:

   ```bash
   export GITHUB_ORG="steoli-platform-labs"
   ```

   Validate that the expected repositories are visible:

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
     gh repo view "$GITHUB_ORG/$repo" --json name,url --jq '.name + " -> " + .url'
   done
   ```

   Expected result: all seven repository names and URLs are printed.

12. Create the local workspace.

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

   Keep these repositories as siblings under one workspace directory. Later Terraform, Helm and validation commands use relative paths between repositories, so the folder layout is part of the lab setup rather than just personal preference.

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

   The `find` command prints local directory paths, so the exact prefix may differ from the tree shown above. Proceed when the output includes seven directories ending in the expected repository names.

13. Verify common repository files.

   Each reference repository already contains baseline repository files. Confirm the local clones include `README.md` and `.gitignore` where expected:

   ```bash
   for repo in platform-bootstrap platform-modules platform-live platform-config helm-charts sample-api
   do
     test -f "$WORKSPACE/$repo/README.md"
     test -f "$WORKSPACE/$repo/.gitignore"
   done
   ```

   The ignore files are intentionally broad enough to keep local secrets, generated files and Terraform state out of Git.

   The `test -f` commands are silent on success. If the block stops or returns an error, one of the expected files is missing; reclone or pull the affected repository before continuing.

14. Confirm the local clones are clean before continuing:

   ```bash
   for repo in platform-bootstrap platform-modules platform-live platform-config helm-charts sample-api
   do
      cd "$WORKSPACE/$repo"
      git status --short
      test -f README.md
      test -f .gitignore
   done
   ```

   `git status --short` should print nothing for each repository. Any listed file means the checkout has local changes or generated files; inspect that repository before continuing so later labs start from a known clean reference state.

   Return to the workspace:

   ```bash
   cd "$WORKSPACE"
   ```

   Run the complete local validation:

   ```bash
   set -e
   export AWS_PAGER=""

   printf '\n===== Git version =====\n'
   git --version
   printf '\n===== AWS CLI version =====\n'
   aws --version
   printf '\n===== Terraform version =====\n'
   terraform version
   printf '\n===== Docker version =====\n'
   docker version
   printf '\n===== kubectl client version =====\n'
   kubectl version --client
   printf '\n===== Helm version =====\n'
   helm version
   printf '\n===== GitHub CLI auth status =====\n'
   gh auth status
   printf '\n===== AWS caller identity =====\n'
   aws sts get-caller-identity --profile "$AWS_PROFILE"
   printf '\n===== GitHub repositories =====\n'
   gh repo list "$GITHUB_ORG" --limit 20
   ```

   Validate that every local repository has a clean working tree:

   ```bash
   for repo in docs platform-bootstrap platform-modules platform-live platform-config helm-charts sample-api
   do
     printf '\n===== %s git status =====\n' "$repo"
     git -C "$WORKSPACE/$repo" status --short
   done
   ```

## Expected Results

The workstation has the required tools installed, AWS CLI authentication works, all seven reference repositories exist locally and each implementation repository contains a `README.md` and `.gitignore`.

## Validation

- Every required tool returns a version.
- Docker can communicate with its engine.
- AWS STS returns the intended account and principal.
- GitHub CLI reports an authenticated session.
- All seven reference repositories are accessible and cloned locally.
- `git status --short` produces no output for committed repositories.

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|--------------|------------|
| `aws sts get-caller-identity` fails | SSO session expired or wrong profile | Run `aws sso login --profile "$AWS_PROFILE"` and verify the profile name |
| `docker version` shows client only | Docker engine is not running | Start Docker Desktop or the Docker service |
| `gh repo view` fails | GitHub CLI is not authenticated or cannot access the reference organization | Run `gh auth status` and confirm access to `steoli-platform-labs` |
| `gh repo clone` fails | Authentication, network or local directory issue | Run `gh auth status`, confirm repository access and remove any incomplete local clone before retrying |
| `terraform: command not found` | Installation path is missing | Reinstall using the official package method and restart the shell |
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
