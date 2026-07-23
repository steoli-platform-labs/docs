# Lab 06 - GitHub Actions

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Kubernetes Platform |
| **Lab** | 06 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-45 minutes |
| **Estimated Cost** | Free |
| **Terraform** | No |
| **Kubernetes** | No |
| **GitOps** | No |

## Introduction

This lab introduces repository-local GitHub Actions workflows.

The workflows validate changes and publish build artifacts. They do not deploy infrastructure or Kubernetes workloads. Deployment remains manual Terraform for infrastructure until GitOps is introduced, and Kubernetes workload deployment is handled by Argo CD in later labs.

Concepts introduced in this lab include CI, GitHub Actions workflows, container images, image tags, image digests, GHCR and image pull permissions. See the [Concepts Reference](../concepts/README.md) for how these pieces connect to later deployments.

## Outcome

After this lab, the project repositories have GitHub Actions workflows that validate Terraform, lint Helm charts, test the sample API and publish an immutable sample API image to GHCR on pushes to `main`.

## Prerequisites

- Lab 01 - Lab 05 completed
- Git, Terraform, Helm, kubectl, Python 3 and Docker Desktop or another Docker daemon installed
- GitHub repositories connected to the local workspace
- `sample-api` repository allowed to publish packages to GitHub Container Registry using `GITHUB_TOKEN`

## Repository Changes

| Repository | Responsibility |
|------------|----------------|
| `sample-api` | Runs application tests, builds the container image and publishes to GHCR |
| `helm-charts` | Lints the reusable Helm chart |
| `platform-modules` | Checks Terraform formatting for reusable modules |
| `platform-live` | Checks Terraform formatting for live environments |
| `platform-config` | Provides namespace manifests used for a client-side dry run |
| `docs` | Documents the lab workflow |

## Files to Review

GitHub Actions are defined inside a `.github/workflows` directory at the root of each repository. Each YAML file in that directory becomes a workflow in that repository's **Actions** tab.

Review these files:

| Repository | Workflow file | Purpose |
|------------|---------------|---------|
| `sample-api` | `.github/workflows/ci.yaml` | Runs Python tests, builds the container image and publishes it to GHCR on pushes to `main` |
| `helm-charts` | `.github/workflows/helm.yaml` | Installs Helm and lints the reusable `sample-api` chart |
| `platform-modules` | `.github/workflows/terraform.yaml` | Checks Terraform formatting for reusable modules |
| `platform-live` | `.github/workflows/terraform.yaml` | Checks Terraform formatting for deployable live environments |
| `platform-config` | `environments/namespaces.yaml` | Provides a built-in Kubernetes manifest for client-side dry-run validation |

These workflows are repository-local. For example, `helm-charts/.github/workflows/helm.yaml` appears only in the `helm-charts` repository Actions tab, not in `sample-api` or `platform-live`.

## Step-by-Step Implementation

1. Review the `.github/workflows` files in each repository listed above. Confirm the workflow triggers, permissions and commands match the repository responsibility.
2. Run the repository-level validation commands from the workspace root:

   ```bash
   cd "$WORKSPACE"
   terraform -chdir=platform-modules fmt -recursive
   terraform -chdir=platform-live fmt -recursive
   helm lint helm-charts/charts/sample-api
   kubectl apply --dry-run=client -f platform-config/environments/namespaces.yaml
   ```

   Do not dry-run the whole `platform-config` tree in this lab. It contains future Argo CD, Karpenter and External Secrets resources whose CRDs are installed in later labs.
3. Commit and push workflow changes only if you changed a workflow file. No commit is required if the workflow files already exist and the validation commands pass.

   If you changed a workflow file while completing this lab, commit only the changed workflow file in the repository that owns it. Do not commit virtual environments, local Docker artifacts, tokens or generated files.

   In `sample-api`:

   ```bash
   cd "$WORKSPACE/sample-api"
   git status
   git diff --check
   git add .github/workflows/ci.yaml
   git commit -m "add sample api ci workflow"
   git push
   ```

   In `helm-charts`:

   ```bash
   cd "$WORKSPACE/helm-charts"
   git status
   git diff --check
   git add .github/workflows/helm.yaml
   git commit -m "add helm chart validation workflow"
   git push
   ```

   In `platform-modules`:

   ```bash
   cd "$WORKSPACE/platform-modules"
   git status
   git diff --check
   git add .github/workflows/terraform.yaml
   git commit -m "add terraform module validation workflow"
   git push
   ```

   In `platform-live`:

   ```bash
   cd "$WORKSPACE/platform-live"
   git status
   git diff --check
   git add .github/workflows/terraform.yaml
   git commit -m "add terraform live validation workflow"
   git push
   ```

4. Open each repository in GitHub and inspect the workflow run triggered by the push:

   1. Open the repository, for example `helm-charts`.
   2. Select the **Actions** tab.
   3. Open the latest workflow run triggered by your push or pull request.
   4. Confirm the run status is green.
   5. Open each job and expand the command steps.
   6. Confirm the expected validation command ran successfully.

   Expected workflows:

   | Repository | Workflow | Expected check |
   |------------|----------|----------------|
   | `sample-api` | `ci` | `pytest -q` passes, Docker build succeeds and the image is published on pushes to `main` |
   | `helm-charts` | `helm` | `helm lint charts/sample-api` passes |
   | `platform-modules` | `terraform` | `terraform fmt -check -recursive` passes |
   | `platform-live` | `terraform` | `terraform fmt -check -recursive` passes |

   Warnings are not automatically failures. Treat deprecation warnings, such as a GitHub Actions Node.js runtime warning, as maintenance work if the job is still green. Treat red steps, non-zero exits, missing workflow runs, or skipped required checks as failures to fix before moving on.
5. Run the same application checks locally. The `sample-api` checks require the Python virtual environment shown below because `pytest` is a project dependency, not a global requirement. The Docker build check also requires Docker Desktop or another Docker daemon to be running.

   ```bash
   cd "$WORKSPACE/sample-api"
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   pytest -q
   docker build -t sample-api:lab06 .

   deactivate
   cd ../helm-charts && helm lint charts/sample-api
   cd ../platform-modules && terraform fmt -check -recursive
   cd ../platform-live && terraform fmt -check -recursive
   ```

6. Verify that the `sample-api` image is published to GHCR after a successful push to `main`. The workflow publishes two tags: an immutable commit-SHA tag for traceability and `latest` for the simple Development GitOps path used in the next lab. Use the GitHub organization and the commit SHA from the workflow run. The commit SHA is visible at the top of the GitHub Actions run, or locally with `git rev-parse HEAD` after you have pulled the same commit.

   The Development cluster pulls `ghcr.io/${GITHUB_ORG}/sample-api:latest` in Lab 07. Keep the GHCR package private and configure Kubernetes image pull credentials in Lab 07.

   If the package is private, authenticate Docker to GHCR first. Prefer a short-lived, least-privilege GitHub token with `read:packages` permission:

   > **Info:** Store the token only in your shell session or a local password manager. Do not write it to repository files, shell history snippets, screenshots or CI logs. Revoke it when local package access is no longer required.

   ```bash
   export GITHUB_USER="<your-github-username>"
   read -r -s GITHUB_TOKEN

   printf '%s' "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USER" --password-stdin
   unset GITHUB_TOKEN
   ```

   Paste the token at the hidden prompt. Do not store it in a committed file.

   ```bash
   cd "$WORKSPACE/sample-api"
   COMMIT_SHA="$(git rev-parse HEAD)"

   docker pull ghcr.io/${GITHUB_ORG}/sample-api:${COMMIT_SHA}
   docker inspect ghcr.io/${GITHUB_ORG}/sample-api:${COMMIT_SHA} --format '{{.RepoDigests}}'
   docker pull ghcr.io/${GITHUB_ORG}/sample-api:latest
   ```

   The `docker pull` commands confirm that both the immutable tag and `latest` exist and are readable. The `docker inspect` command should print a digest such as `ghcr.io/<github-organization>/sample-api@sha256:...`, which proves the commit-SHA tag resolves to a concrete image artifact.

   If you use GitHub CLI to inspect the package, your `gh` token must include package scopes. Unset `GITHUB_TOKEN` first because that environment variable overrides the credentials stored by `gh auth login`:

   ```bash
   unset GITHUB_TOKEN
   gh auth refresh --hostname github.com --scopes read:packages,write:packages
   gh api "/orgs/${GITHUB_ORG}/packages/container/sample-api" --jq '{name,visibility,url}'
   ```

   If `docker pull` returns `unauthorized`, confirm that the token has `read:packages`, that your GitHub user can access the `sample-api` package, and that the package exists under the expected organization.

   This lab does not apply infrastructure or deploy workloads. GitHub Actions validate, test and publish artifacts only; deployment remains a GitOps responsibility in later labs.

## Expected Results

Local validation commands pass, GitHub Actions workflows run successfully, pull requests validate without publishing images and pushes to `main` publish immutable commit-SHA and `latest` `sample-api` image tags to GHCR.

## Validation

- Pull requests run tests and validation without publishing an image.
- A push to `main` publishes immutable commit-SHA and `latest` image tags to GHCR.
- The image tags can be pulled using the expected package permissions.
- The `sample-api` package is private by default, and Kubernetes image pull credentials are planned for Lab 07.
- CI does not deploy directly to Kubernetes.
- Workflow permissions are limited to what each job requires.
- A published image alone does not update GitOps desired state; verify that the documented image-update process exists before calling end-to-end delivery complete.

## Troubleshooting

Start with the failed GitHub Actions run:

1. Open the repository in GitHub.
2. Go to **Actions**.
3. Open the failed workflow run.
4. Expand the failed job and failed step.
5. Compare the command output with the local validation command from this lab.

Common issues:

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Workflow does not run | Workflow file is missing from `.github/workflows` or the change was not pushed | Confirm the file exists in the repository and push to the branch again |
| `terraform fmt -check -recursive` fails | Terraform files are not formatted | Run `terraform -chdir=platform-live fmt -recursive` or `terraform -chdir=platform-modules fmt -recursive`, then commit the formatting changes |
| `helm lint` fails | Chart metadata, values or templates are invalid | Run `helm lint charts/sample-api` locally in `helm-charts` and fix the reported chart issue |
| Python tests fail | Application dependency or test failure | Run the local `sample-api` virtualenv commands and fix the failing test |
| Docker build fails | Dockerfile or dependency issue | Run `docker build -t sample-api:lab06 .` locally with Docker running |
| GHCR pull returns `unauthorized` | Docker is not logged in to GHCR or token lacks `read:packages` | Run `docker login ghcr.io` with a token that has `read:packages` |
| `gh auth refresh` says `GITHUB_TOKEN` is being used | `GITHUB_TOKEN` is set in the current shell and overrides stored GitHub CLI credentials | Run `unset GITHUB_TOKEN`, then rerun `gh auth refresh --hostname github.com --scopes read:packages,write:packages` |
| `gh api` package lookup returns `403` | GitHub CLI token lacks package scopes | Unset `GITHUB_TOKEN`, then run `gh auth refresh --hostname github.com --scopes read:packages,write:packages` and approve the browser/device prompt |

## Final Repository State

At completion, the implementation repositories have validation workflows, `sample-api` publishes commit-SHA and `latest` image tags to GHCR on pushes to `main`, and no workflow deploys directly to Kubernetes.

## Cleanup

Remove the local Python virtual environment created during validation if you no longer need it:

```bash
rm -rf "$WORKSPACE/sample-api/.venv"
```

Remove the local Docker image if desired:

```bash
docker image rm sample-api:lab06
```

## Next Steps

Continue with [Lab 07 - Argo CD](./lab07-argocd.md).
