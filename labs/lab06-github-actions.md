# Lab 06 - GitHub Actions

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Kubernetes Platform |
| **Lab** | 06 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-45 minutes |
| **Primary Tools** | GitHub Actions, Docker, Terraform, Helm |

## Introduction

This lab introduces repository-local GitHub Actions workflows.

The workflows validate changes and publish build artifacts. They do not deploy infrastructure or Kubernetes workloads. Deployment remains manual Terraform for infrastructure until GitOps is introduced, and Kubernetes workload deployment is handled by Argo CD in later labs.

Concepts introduced in this lab include CI, GitHub Actions workflows, container images, image tags, image digests, GHCR and image pull permissions. See the [Concepts Reference](../concepts/README.md) for how these pieces connect to later deployments.

## Outcome

After this lab, the project repositories have GitHub Actions workflows that validate Terraform, lint Helm charts, test the sample API and publish immutable sample API release images to GHCR from Git release tags.

## Prerequisites

- Lab 01 - Lab 05 completed
- Git, Terraform, Helm, Python 3 and Docker Desktop or another Docker daemon installed
- GitHub repositories connected to the local workspace
- Public `sample-api` package available in GitHub Container Registry

## Files to Review

GitHub Actions are defined inside a `.github/workflows` directory at the root of each repository. Each YAML file in that directory becomes a workflow in that repository's **Actions** tab.

Review these files:

| Repository | Workflow file | Purpose |
|------------|---------------|---------|
| `sample-api` | `.github/workflows/ci.yaml` | Runs Python tests, builds the container image and publishes release images to GHCR from Git tags |
| `helm-charts` | `.github/workflows/helm.yaml` | Installs Helm and lints the reusable `sample-api` chart |
| `platform-modules` | `.github/workflows/terraform.yaml` | Checks Terraform formatting for reusable modules |
| `platform-live` | `.github/workflows/terraform.yaml` | Checks Terraform formatting for deployable live environments |

These workflows are repository-local. For example, `helm-charts/.github/workflows/helm.yaml` appears only in the `helm-charts` repository Actions tab, not in `sample-api` or `platform-live`.

## Step-by-Step Implementation

1. Review the `.github/workflows` files in each repository listed above.

   A GitHub Actions workflow is a YAML file that tells GitHub what automation to run for that repository. The important parts to understand are:

   | Workflow field | What it controls | What to check in this lab |
   |----------------|------------------|---------------------------|
   | `name` | The workflow name shown in the repository **Actions** tab | Names are short and repository-specific, such as `ci`, `helm` or `terraform` |
   | `on` | The events that start the workflow | Pull requests validate changes; pushes validate merged changes; `sample-api` tags publish release images |
   | `permissions` | The default token permissions available to the workflow | `sample-api` needs `packages: write` to publish to GHCR; validation-only workflows do not need package publishing permissions |
   | `jobs` | One or more independent units of work | Each current workflow has one focused job |
   | `runs-on` | The GitHub-hosted runner image | The labs use `ubuntu-latest` runners |
   | `steps` | The commands or reusable actions executed by the job | Steps install tools, run checks, build images or publish images |

   Check the workflow boundaries carefully:

   | Repository | Trigger behavior | Job behavior | Deployment boundary |
   |------------|------------------|--------------|---------------------|
   | `sample-api` | Pull requests and pushes run tests/builds; tags like `v1.0.0` also publish | Checks out code, installs Python, runs `pytest`, computes an image tag, logs in to GHCR only for release tags and builds the image | Publishes an image artifact only; it does not update Kubernetes |
   | `helm-charts` | Pushes and pull requests run chart validation | Checks out code, installs Helm and runs `helm lint charts/sample-api` | Validates chart packaging only; it does not install the chart |
   | `platform-modules` | Pushes and pull requests run Terraform formatting validation | Checks out code, installs Terraform and runs `terraform fmt -check -recursive` | Validates reusable module formatting only; it does not run `terraform apply` |
   | `platform-live` | Pushes and pull requests run Terraform formatting validation | Checks out code, installs Terraform and runs `terraform fmt -check -recursive` | Validates live Terraform formatting only; it does not provision AWS resources |

   This distinction is the purpose of the lab: CI should make changes safer before they are merged or released, but CI should not silently mutate infrastructure or Kubernetes workloads. Terraform deployment remains explicit, and Kubernetes delivery moves to Argo CD in Lab 07.

2. Run the same checks locally that GitHub Actions runs remotely.

   These commands are not separate lab goals. They exist so you can connect a green workflow run to the exact tool invocation inside the workflow. If one of these commands fails locally, the matching GitHub Actions step should fail for the same reason.

   Start with the application workflow checks. The Python virtual environment isolates this application's dependencies from your system Python. The Docker build creates a local test image only; it does not publish anything to GHCR.

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

   printf '\n===== platform-modules Terraform format check =====\n'
   cd ../platform-modules && terraform fmt -check -recursive

   printf '\n===== platform-live Terraform format check =====\n'
   cd ../platform-live && terraform fmt -check -recursive
   ```

   Expected output: `pytest -q` reports passing tests, Docker finishes with `Successfully tagged sample-api:lab06`, Helm lint reports zero failed charts and Terraform format checks print no filenames. A filename from `terraform fmt -check` means that repository is not formatted as CI expects.

   Notice the difference between `terraform fmt -check` and `terraform fmt`. The workflow uses `-check` because CI should report formatting drift without rewriting files. Developers can run `terraform fmt -recursive` locally when they intentionally want Terraform to rewrite formatting.

3. Open each repository in GitHub and inspect a recent workflow run:

   1. Open the repository, for example `helm-charts`.
   2. Select the **Actions** tab.
   3. Open the latest workflow run for the reference repository.
   4. Confirm the run status is green.
   5. Open each job and expand the command steps.
   6. Confirm the expected validation command ran successfully.

   Expected workflows:

   | Repository | Workflow | Expected check |
   |------------|----------|----------------|
   | `sample-api` | `ci` | `pytest -q` passes, Docker build succeeds and release tags publish images |
   | `helm-charts` | `helm` | `helm lint charts/sample-api` passes |
   | `platform-modules` | `terraform` | `terraform fmt -check -recursive` passes |
   | `platform-live` | `terraform` | `terraform fmt -check -recursive` passes |

   Warnings are not automatically failures. Treat deprecation warnings, such as a GitHub Actions Node.js runtime warning, as maintenance work if the job is still green. Treat red steps, non-zero exits, missing workflow runs, or skipped required checks as failures to fix before moving on.

4. Verify the initial `sample-api` release image used by GitOps in the next lab. The workflow publishes Docker image tags from Git tags. The committed reference release `v1.0.0` publishes `ghcr.io/${GITHUB_ORG}/sample-api:1.0.0`.

   The shared EKS cluster pulls `ghcr.io/${GITHUB_ORG}/sample-api:1.0.0` in Lab 07. The reference package is public, so no Docker or Kubernetes registry credentials are required for this image.

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
| `terraform fmt -check -recursive` fails | Terraform files are not formatted | Run the matching local `terraform fmt -recursive` command to understand the drift, then compare with the latest reference repository state before continuing |
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
