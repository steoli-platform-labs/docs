# Lab 06 - GitHub Actions

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Kubernetes Platform |
| **Lab** | 06 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-45 minutes |
| **Estimated Cost** | Free |
| **Primary Tools** | GitHub Actions, Docker, Terraform, Helm |

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
- Public `sample-api` package available in GitHub Container Registry

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

1. Review the `.github/workflows` files in each repository listed above. Confirm the workflow triggers, permissions and commands match the repository responsibility. A good review checks what event starts the workflow, what permissions it receives, what commands it runs and whether it only validates/builds artifacts. Only `sample-api` should publish the application image; none of these workflows should deploy workloads directly.
2. Run the repository-level validation commands from the workspace root:

   ```bash
   cd "$WORKSPACE"
   printf '\n===== platform-modules Terraform format =====\n'
   terraform -chdir=platform-modules fmt -recursive

   printf '\n===== platform-live Terraform format =====\n'
   terraform -chdir=platform-live fmt -recursive

   printf '\n===== Helm chart lint =====\n'
   helm lint helm-charts/charts/sample-api

   printf '\n===== Namespace manifest dry-run =====\n'
   kubectl apply --dry-run=client -f platform-config/environments/namespaces.yaml
   ```

   Do not dry-run the whole `platform-config` tree in this lab. It contains future Argo CD, Karpenter and External Secrets resources whose CRDs are installed in later labs.

   `terraform fmt` may rewrite files if formatting drift exists. In the reference repos, no changed files should remain after this step; if files change, inspect why before continuing. `helm lint` should report zero failed charts, and the namespace dry-run should print resources as `created (dry run)` or `configured (dry run)`.
3. Confirm the reference workflow files are present and clean.

   This lab series uses the public repositories as reference templates. You validate the committed workflow state; you do not push workflow changes to the shared reference repositories.

   In `sample-api`:

   ```bash
   cd "$WORKSPACE/sample-api"
   printf '\n===== sample-api git status =====\n'
   git status

   printf '\n===== sample-api whitespace check =====\n'
   git diff --check

   printf '\n===== sample-api workflow file =====\n'
   test -f .github/workflows/ci.yaml
   ```

   In `helm-charts`:

   ```bash
   cd "$WORKSPACE/helm-charts"
   printf '\n===== helm-charts git status =====\n'
   git status

   printf '\n===== helm-charts whitespace check =====\n'
   git diff --check

   printf '\n===== Helm workflow file =====\n'
   test -f .github/workflows/helm.yaml
   ```

   In `platform-modules`:

   ```bash
   cd "$WORKSPACE/platform-modules"
   printf '\n===== platform-modules git status =====\n'
   git status

   printf '\n===== platform-modules whitespace check =====\n'
   git diff --check

   printf '\n===== Terraform workflow file =====\n'
   test -f .github/workflows/terraform.yaml
   ```

   In `platform-live`:

   ```bash
   cd "$WORKSPACE/platform-live"
   printf '\n===== platform-live git status =====\n'
   git status

   printf '\n===== platform-live whitespace check =====\n'
   git diff --check

   printf '\n===== Terraform workflow file =====\n'
   test -f .github/workflows/terraform.yaml
   ```

   `git diff --check` and `test -f` are silent on success. `git status` should show a clean worktree, and any output from the whitespace check or missing workflow file should be treated as a stop condition.

4. Open each repository in GitHub and inspect a recent workflow run:

   1. Open the repository, for example `helm-charts`.
   2. Select the **Actions** tab.
   3. Open the latest workflow run for the reference repository.
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
   printf '\n===== Create Python virtual environment =====\n'
   python3 -m venv .venv
   source .venv/bin/activate

   printf '\n===== Install Python dependencies =====\n'
   pip install -r requirements.txt

   printf '\n===== Python tests =====\n'
   pytest -q

   printf '\n===== Docker build =====\n'
   docker build -t sample-api:lab06 .

   deactivate

   printf '\n===== Helm chart lint =====\n'
   cd ../helm-charts && helm lint charts/sample-api

   printf '\n===== platform-modules Terraform format =====\n'
   cd ../platform-modules && terraform fmt -check -recursive

   printf '\n===== platform-live Terraform format =====\n'
   cd ../platform-live && terraform fmt -check -recursive
   ```

   Expected output: `pytest -q` reports passing tests, Docker finishes with `Successfully tagged sample-api:lab06`, Helm lint reports zero failed charts and Terraform format checks print no filenames. A filename from `terraform fmt -check` means that repository is not formatted as CI expects.

6. Verify the initial `sample-api` release image used by GitOps in the next lab. The workflow publishes Docker image tags from Git tags. The committed reference release `v1.0.0` publishes `ghcr.io/${GITHUB_ORG}/sample-api:1.0.0`.

   The Development cluster pulls `ghcr.io/${GITHUB_ORG}/sample-api:1.0.0` in Lab 07. The reference package is public, so no Docker or Kubernetes registry credentials are required for this image.

   Verify the image tag:

   ```bash
   printf '\n===== Pull release image =====\n'
   docker pull ghcr.io/${GITHUB_ORG}/sample-api:1.0.0

   printf '\n===== Inspect release image digest =====\n'
   docker inspect ghcr.io/${GITHUB_ORG}/sample-api:1.0.0 --format '{{.RepoDigests}}'
   ```

   The `docker pull` command confirms that the release image exists and is readable. The `docker inspect` command should print a digest such as `ghcr.io/<github-organization>/sample-api@sha256:...`, which proves the tag resolves to a concrete image artifact. Later rollout and promotion labs compare GitOps release tags, for example `1.0.0` and `1.0.1`.

   If `RepoDigests` is empty or does not include `@sha256:`, the image tag did not resolve to the expected immutable artifact. Recheck the organization, package visibility and tag before continuing.

   You can also inspect the public package metadata with GitHub CLI:

   ```bash
   gh api "/orgs/${GITHUB_ORG}/packages/container/sample-api" --jq '{name,visibility,url}'
   ```

   If `docker pull` returns `unauthorized`, confirm the package is still public and that the image tag exists under the expected organization.

   This lab does not apply infrastructure or deploy workloads. GitHub Actions validate, test and publish artifacts only; deployment remains a GitOps responsibility in later labs.

## Expected Results

Local validation commands pass, GitHub Actions workflows run successfully, pull requests validate without publishing images and Git release tags publish readable image tags such as `1.0.0`.

## Validation

- Pull requests run tests and validation without publishing an image.
- A Git tag such as `v1.0.0` publishes a matching release-style image tag such as `1.0.0`.
- The image tags can be pulled without registry authentication.
- The `sample-api` package is public for reference/demo use.
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
| Workflow is missing | Workflow file is missing from `.github/workflows` | Pull the latest reference repository and confirm the file exists |
| `terraform fmt -check -recursive` fails | Terraform files are not formatted | Run `terraform -chdir=platform-live fmt -recursive` or `terraform -chdir=platform-modules fmt -recursive`, then commit the formatting changes |
| `helm lint` fails | Chart metadata, values or templates are invalid | Run `helm lint charts/sample-api` locally in `helm-charts` and fix the reported chart issue |
| Python tests fail | Application dependency or test failure | Run the local `sample-api` virtualenv commands and fix the failing test |
| Docker build fails | Dockerfile or dependency issue | Run `docker build -t sample-api:lab06 .` locally with Docker running |
| GHCR pull returns `unauthorized` | Package visibility is not public or the package path is wrong | Confirm the package is public and the image path is `ghcr.io/steoli-platform-labs/sample-api` |
| `gh api` package lookup returns `403` | GitHub CLI cannot read package metadata | Confirm GitHub CLI authentication or use the GitHub web UI to inspect the public package |

## Final Repository State

At completion, the implementation repositories have validation workflows, Git tags publish release-style `sample-api` image tags to GHCR, and no workflow deploys directly to Kubernetes.

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
