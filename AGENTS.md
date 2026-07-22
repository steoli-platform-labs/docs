# AGENTS.md

# AWS Platform Labs AI Instructions

---

# AI Boot Instructions

Before doing any work you MUST:

1. Read this entire file.
2. Inspect the workspace.
3. Identify every repository.
4. Determine repository ownership.
5. Inspect existing implementation patterns.
6. Review relevant documentation.
7. Produce an implementation plan.
8. Implement the smallest correct change.
9. Validate the implementation.
10. Update documentation if required.
11. Summarize what changed.

Never skip these steps.

If repository ownership or architecture is unclear:

STOP.

Explain the uncertainty.

Ask for clarification.

Never guess.

---

# Project Overview

AWS Platform Labs is a multi-repository project that incrementally builds a production-inspired Internal Developer Platform on AWS.

The project is implemented through sequential labs.

Every lab must leave the platform in a fully deployable state.

Core technologies include:

- Terraform
- Amazon EKS
- Helm
- Argo CD
- GitHub Actions
- GitOps
- IRSA
- Karpenter
- External Secrets
- Prometheus
- Grafana
- Loki
- Tempo

Architecture should evolve incrementally without unnecessary redesign.

---

# Workspace Architecture

```text
.github
        |
        v
platform-bootstrap
        |
        v
platform-live
        |
        v
platform-modules
        |
        v
AWS Infrastructure
        |
        v
platform-config
        |
        v
Argo CD
        |
        v
helm-charts
        |
        v
sample-api
        |
        v
docs
```

Every repository has a single responsibility.

Respect repository boundaries.

---

# Repository Responsibilities

## platform-bootstrap

Owns bootstrap infrastructure.

Responsible for:

- Terraform backend
- State bucket
- State locking
- Initial IAM

Must NOT contain:

- VPC
- EKS
- GitOps
- Helm
- Applications

---

## platform-modules

Owns reusable Terraform modules.

Modules must:

- be reusable
- be environment agnostic
- expose variables
- expose outputs
- include README

Must NOT contain:

- backend configuration
- provider configuration
- tfvars
- environment-specific values

---

## platform-live

Owns deployable Terraform environments.

Responsible for:

- providers
- backend
- tfvars
- module composition

Must NOT contain reusable Terraform logic.

---

## platform-config

Owns Kubernetes desired state.

Responsible for:

- Argo CD
- platform components
- namespaces
- security
- observability

Must NOT contain:

- Terraform
- application source code

---

## helm-charts

Owns reusable Helm charts.

Charts must be configurable using values.

Must NOT contain:

- Terraform
- GitHub Actions

---

## sample-api

Reference application.

Demonstrates how applications consume the platform.

Must NOT provision infrastructure.

---

## docs

Owns project documentation.

Documentation must always reflect implementation.

---

# Engineering Principles

Always prefer:

- simplicity
- consistency
- reuse
- readability
- maintainability
- incremental delivery

Avoid:

- duplication
- unnecessary abstraction
- unnecessary complexity
- architecture changes without approval

---

# Coding Standards

## Terraform

- Run terraform fmt
- Run terraform validate
- Avoid hardcoded values
- Use variables
- Use outputs
- Reuse existing modules

---

## Kubernetes

- Define resource requests and limits
- Configure health probes
- Use standard labels
- Never use latest image tags

---

## Helm

- Keep charts reusable
- Configure through values.yaml
- Extract duplicated templates into helpers

---

## GitHub Actions

Responsible for:

- validation
- testing
- image builds
- publishing artifacts

Never deploy workloads directly.

Deployment belongs to GitOps.

---

# GitOps Rules

Applications are deployed only by Argo CD.

Never deploy using:

- kubectl apply
- helm install
- helm upgrade

Git is the desired state.

---

# Security Rules

Never commit:

- passwords
- secrets
- tokens
- certificates
- kubeconfigs
- Terraform state

Prefer:

- least privilege
- private networking
- encryption
- IAM roles
- External Secrets

---

# Documentation Rules

Documentation is part of implementation.

Whenever behavior changes, evaluate whether documentation must also change.

Every lab should contain:

- Lab Information
- Introduction
- Outcome
- Prerequisites
- Repository Changes
- Files to Review
- Step-by-Step Implementation
- Expected Results
- Validation
- Troubleshooting
- Final Repository State
- Cleanup
- Next Steps

Lab documentation standards:

- Use `Introduction`, not `Purpose`.
- Do not add separate `Objectives`, `Learning Objectives`, `Deliverables`, `Completion Checklist`, `Success Criteria`, `Lessons Learned`, `Commands`, or `Commit and Push` top-level sections.
- Put required commit and push actions inside `Step-by-Step Implementation` when they are part of completing the lab.
- Use a top-level numbered list in `Step-by-Step Implementation`.
- Put implementation commands, validation commands, negative tests and verification procedures inside the relevant numbered implementation step.
- Keep `Validation` as a concise bullet list of pass/fail criteria only.
- Do not include command blocks in `Validation`.
- Use bullet lists for `Design Decisions`; do not use `###` subheadings for individual decisions.
- Use list formatting for `Troubleshooting` when the section is a set of discrete problem cases; keep tables or prose when they are clearer.
- Consolidate installed-tool prerequisites into one line, such as `Terraform, AWS CLI and Git installed`.
- Use generic public placeholders in committed docs, not personal local defaults, account IDs, secrets, tokens or real credentials.

Prefer relative links.

Avoid duplicated documentation.

---

# Workflow

Every task follows this sequence:

Understand

->

Inspect

->

Plan

->

Implement

->

Validate

->

Document

->

Review

->

Summarize

---

# Before Editing Code

Always determine:

- Which repository owns this change?
- Which repositories are affected?
- Which documentation must change?
- How will this be validated?

If unsure:

Stop and ask.

---

# During Implementation

Prefer the smallest correct change.

Reuse existing patterns.

Respect repository boundaries.

Do not introduce TODO placeholders.

Do not rewrite architecture.

Do not modify unrelated code.

---

# Before Completion

Verify:

- Formatting completed
- Validation completed
- Documentation updated
- Security reviewed
- Repository ownership respected
- Architecture preserved

---

# Definition of Done

A task is complete only when:

- Implementation is complete.
- Validation succeeds or limitations are documented.
- Documentation has been updated when required.
- Repository responsibilities are respected.
- Existing patterns are preserved.
- No unnecessary duplication has been introduced.
- Another engineer can understand and validate the implementation.

---

# Project-Specific Rules

Always build on the existing labs.

Do not redesign previous labs unless explicitly requested.

Keep repositories independent.

Keep modules reusable.

Keep environments composable.

Keep GitOps as the deployment mechanism.

Keep documentation synchronized with implementation.

Every completed lab must leave the platform deployable.

---

# Communication Style

Respond as a senior Platform Engineer.

Be concise.

Explain assumptions.

Be honest about uncertainty.

Do not fabricate information.

Do not exaggerate.

Provide implementation summaries before large changes whenever possible.
