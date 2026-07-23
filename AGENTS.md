# AWS Platform Labs AI Instructions

This file is the canonical project instruction file for AI agents working in this workspace. Read it before making changes.

## Work Sequence

Follow this sequence for every task:

1. Read this file.
2. Inspect the relevant repository or repositories.
3. Confirm repository ownership and boundaries.
4. Review existing implementation and documentation patterns.
5. Make the smallest correct change.
6. Validate the change.
7. Update documentation when behavior or learning flow changes.
8. Summarize what changed and what was validated.

If repository ownership, architecture, or user intent is unclear, stop and ask. Do not guess.

## Project Overview

AWS Platform Labs is a public, multi-repository lab series that incrementally builds a production-inspired Internal Developer Platform on AWS.

Core technologies include Terraform, Amazon EKS, Kubernetes, Helm, GitHub Actions, GitOps, Argo CD, IRSA, Karpenter, External Secrets Operator, Prometheus, Grafana, Loki and Tempo.

Every completed lab should leave the platform in a deployable and understandable state.

## Repository Ownership

Respect repository boundaries. Make changes in the repository that owns the behavior.

| Repository | Owns | Must not own |
|------------|------|--------------|
| `platform-bootstrap` | Initial bootstrap resources, Terraform backend bucket, state locking setup | VPC, EKS, GitOps, Helm charts, applications |
| `platform-modules` | Reusable Terraform modules | Provider config, backend config, tfvars, environment-specific values |
| `platform-live` | Deployable Terraform environments, providers, backend config examples, tfvars examples, module composition | Reusable Terraform module logic |
| `platform-config` | Kubernetes desired state, Argo CD Applications, namespaces, platform services, security and observability configuration | Terraform, application source code |
| `helm-charts` | Reusable Helm charts and chart templates | Terraform, GitHub Actions deployment logic |
| `sample-api` | Reference application and application CI | Infrastructure provisioning |
| `docs` | Project documentation, labs, concepts and architecture context | Application or infrastructure implementation |

## Engineering Principles

- Prefer simple, incremental, consistent changes.
- Preserve existing architecture unless the user explicitly asks for redesign.
- Reuse existing patterns before introducing new ones.
- Keep repositories independent and responsibilities clear.
- Do not add TODO placeholders in committed docs or code.
- Do not modify unrelated files.
- Never commit secrets, tokens, kubeconfigs, certificates, Terraform state, plan files, local backend files or personal defaults.

## Terraform Rules

- Run `terraform fmt` for edited Terraform code.
- Run `terraform validate` where practical for edited root modules or modules.
- Prefer variables, outputs and reusable modules over hardcoded environment values.
- Keep backend config and tfvars examples generic; real `backend.hcl` and `terraform.tfvars` remain local and ignored.
- `platform-bootstrap` may start with local state only to create the backend bucket; later state should use the remote S3 backend.

## Kubernetes, Helm and GitOps Rules

- Kubernetes resources should use standard labels, resource requests and health probes where applicable.
- Prefer immutable image tags. `latest` is acceptable only when a lab explicitly treats it as a Development convenience tag and CI publishes it.
- Helm charts must be reusable and configurable through values.
- GitHub Actions validate, test, build and publish artifacts; they must not deploy workloads directly.
- Argo CD owns Kubernetes application deployment after Lab 07.
- Do not use manual `kubectl apply`, `helm install` or `helm upgrade` for GitOps-managed applications, except for documented bootstrap, dry-run validation, temporary test resources or local-only troubleshooting.
- Lab 07 requires hands-on Argo CD UI access through local port-forwarding so users learn the UI exists; do not require public exposure of Argo CD.
- Private GHCR pulls are the default for `sample-api`; use a least-privilege `read:packages` token and a Kubernetes image pull secret until later secret-management labs replace that pattern.

## Documentation Rules

Documentation is part of the implementation. Update docs when behavior, validation, user flow or learning context changes.

Use this canonical lab section order:

- `## Lab Information`
- `## Introduction`
- `## Outcome`
- `## Prerequisites`
- `## Repository Changes`
- `## Files to Review`
- `## Step-by-Step Implementation`
- `## Expected Results`
- `## Validation`
- `## Troubleshooting`
- `## Final Repository State`
- `## Cleanup`
- `## Next Steps`

Lab writing rules:

- Keep lab steps practical and concise.
- Use a top-level numbered list in `Step-by-Step Implementation`.
- Put commands, validation commands, negative tests and commit/push actions inside the relevant implementation step.
- Keep `Validation` as concise pass/fail bullet criteria.
- Use clear `Troubleshooting` entries for common failure modes and explain likely root causes in plain language.
- Add short concept explanations when they help users understand what they are deploying.
- Put deeper explanations in `docs/concepts/README.md` and link to it from labs.
- When a lab introduces important concepts, add a brief `Concepts introduced in this lab...` paragraph in `Introduction`.
- Use generic public placeholders and relative links.

## Known Lab Decisions

- Lab 02 should not commit `backend.tf`; migration scripts may create ignored local backend config after the backend bucket exists.
- Lab 03 network examples use a small primary CIDR plus optional EKS-ready private subnets from `100.64.0.0/18`; this must be treated as planned, non-overlapping shared address space.
- Lab 06 publishes both commit-SHA and `latest` tags for `sample-api`; `latest` is for Development convenience only.
- Lab 07 uses private GHCR image pulls through `sample-api-dev/ghcr-pull` until later secret-management labs improve the pattern.
- Lab 08 deploys kube-prometheus-stack through Argo CD. Large Prometheus Operator CRDs require the chart CRD upgrade job plus sync options that avoid client-side apply annotation limits.

## Validation Expectations

- Run the narrowest meaningful validation for the change.
- For docs-only changes, run `git diff --check` and verify lab heading structure when lab files changed.
- For Terraform changes, run formatting and validation in the affected module or root when practical.
- For Helm changes, run `helm lint` and render relevant templates when practical.
- For Kubernetes manifest changes, run client-side dry-run where CRDs are available or document why not.
- If validation cannot be completed, state exactly what was not run and why.

## Communication

Respond as a senior Platform Engineer:

- Be concise and factual.
- Explain assumptions and uncertainty.
- Do not fabricate results.
- Summarize changed files, validation and any remaining risk.
