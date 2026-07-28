# Lab XX - Title

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | |
| **Lab** | XX |
| **Difficulty** | Beginner/Intermediate/Advanced |
| **Estimated Time** | |
| **Estimated Cost** | Free/Low/Medium |
| **Primary Tools** | |

## Introduction

Describe what this lab is about and why it matters in two or three short paragraphs.
Use `Introduction` consistently; do not add a separate `Summary` section.
When the lab introduces important concepts, include a short sentence such as `Concepts introduced in this lab include...` and link to [Concepts](../concepts/README.md) where deeper context helps.

## Outcome

State what the lab produces in one or two sentences.
Do not add separate `Objectives` or `Learning Objectives` sections; use `Outcome`, `Expected Results` and `Validation` instead.

## Prerequisites

List the previous lab range, required tools and required platform state.

## Files to Review

List the important files and explain why each one matters. Include repository ownership context here when it helps the reader understand where the reviewed resources live.

## Step-by-Step Implementation

Use a top-level numbered list for lab-specific steps. Each step should include the relevant context and commands needed to complete that step.
Do not add a separate top-level `Commands` section; commands belong inside the step they support.
Include verification actions as explicit steps instead of hiding the procedure in `Validation`.
Write learner steps for committed reference repositories: learners inspect, apply and validate existing reference state. Do not include learner-facing `git commit` or `git push` steps.
If demonstrating a GitOps change, use precommitted desired state or an isolated temporary demo resource instead of asking learners to push to shared repositories.
For GitOps-dependent steps, state whether desired state is already committed, whether the root Argo CD Application must be refreshed, whether child Applications need refresh and how to recognize stale desired state.
When chart, Terraform module or Kubernetes manifest behavior depends on versions or CRDs, include pinned version context, local render or dry-run validation and expected success or failure output.
When a copy/paste command block contains multiple output-producing checks, label each distinct check with `printf '\n===== Description =====\n'` immediately before the command.

```bash
cd "$WORKSPACE"

printf '\n===== First example check =====\n'
tool command --first-example

printf '\n===== Second example check =====\n'
tool command --second-example
```

## Expected Results

Describe what should be true after the commands complete.

## Validation

List concise pass/fail criteria only. Detailed validation commands and negative tests belong in `Step-by-Step Implementation`.

## Troubleshooting

Use troubleshooting that matches this lab's component. Avoid generic Kubernetes text unless the lab actually deploys Kubernetes resources.

## Final Repository State

Describe the expected committed reference state and any local or ignored artifacts. Do not tell learners to commit or push.
For GitOps-managed labs, prefer concise wording such as `The implementation remains GitOps-driven and mergeable to main`, plus the owning repository or resources when useful.

## Cleanup

State whether cleanup is required. If later labs depend on the result, say so explicitly.

## Next Steps

Link to the next lab.

## Author Note: Optional Deep-Dive Sections

Use these only when they add practical clarity to a foundation lab. Prefer moving reusable conceptual material to [Concepts](../concepts/README.md).

- `## Architecture`
- `## AWS Resources`
- `## Design Decisions`
- `## Network Layout`
- `## Implementation Overview`
- `## Values Used in This Guide`
- `## Best Practices`
- `## References`
