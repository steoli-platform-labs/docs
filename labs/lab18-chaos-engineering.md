# Lab 18 - Chaos Engineering

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Operations |
| **Lab** | 18 |
| **Difficulty** | Advanced |
| **Estimated Time** | 30-45 minutes |
| **Estimated Cost** | Free |
| **Terraform** | No |
| **Kubernetes** | Yes |
| **GitOps** | Yes |

## Introduction

This lab introduces lightweight chaos validation for the platform.

The goal is to run controlled failure tests against the sample application and verify that the platform's deployment, observability and resilience settings recover as expected.

## Outcome
Implement and validate Chaos Engineering in the complete platform reference implementation.

## Prerequisites
Complete Lab 01 - Lab 17, configure AWS CLI, Terraform, kubectl, Helm and repository URLs.

## Repository Changes
Primary implementation: `platform-config/chaos/delete-pod.yaml`.

## Files to Review
Review the chaos experiment manifests and update any environment-specific values before validation.

## Step-by-Step Implementation

1. Review `platform-config/chaos/delete-pod.yaml` and confirm it targets only the sample API test workload.
2. Confirm the chaos ServiceAccount, Role and RoleBinding grant only the permissions needed for this experiment.
3. Validate the chaos manifest and establish the steady state before injecting failure:

   ```bash
   cd "$WORKSPACE"
   kubectl apply --dry-run=client -f platform-config/chaos/delete-pod.yaml
   kubectl -n sample-api-dev get rollout,pod,pdb
   kubectl -n argocd get applications.argoproj.io -o wide
   ```

4. Verify the chaos identity before execution:

   ```bash
   kubectl -n sample-api-dev get serviceaccount chaos-runner
   kubectl -n sample-api-dev auth can-i delete pods \
     --as=system:serviceaccount:sample-api-dev:chaos-runner
   kubectl -n sample-api-dev auth can-i delete deployments \
     --as=system:serviceaccount:sample-api-dev:chaos-runner
   ```

   The first answer should be `yes`; the second should be `no`.

5. Run the one-off chaos Job and watch Kubernetes replace the deleted pod:

   ```bash
   kubectl create -f platform-config/chaos/delete-pod.yaml
   kubectl -n sample-api-dev logs -f job/delete-sample-api-pod
   kubectl -n sample-api-dev get pods -w
   kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
   ```

6. Validate recovery through pod status, metrics, logs and traces. At the same time, continuously call the API and observe Prometheus/Grafana, Loki and Tempo.
7. Remove the one-off chaos Job after validation:

   ```bash
   kubectl -n sample-api-dev delete job delete-sample-api-pod
   ```

## Expected Results
The chaos manifest is valid, the sample API starts from a healthy steady state, and the platform recovers after a controlled pod deletion.

## Validation
Pass criteria:

- The experiment deletes only a matching sample-api pod.
- Kubernetes creates a replacement automatically.
- Available replicas remain within the PDB/SLO expectation.
- Argo CD remains healthy and does not fight normal controller reconciliation.
- Metrics show the disruption and recovery.
- Logs contain the deletion/restart sequence.
- Traces show whether user requests failed or slowed.
- The API recovers within the documented recovery objective.
- The chaos Job and its RBAC are removed or reset after the test.

A Job that references `chaos-runner` without a ServiceAccount, Role and RoleBinding cannot run and is a repository blocker, not a successful chaos test.

## Troubleshooting
Start with the chaos Job, RBAC and workload events:

```bash
kubectl -n sample-api-dev describe job delete-sample-api-pod
kubectl -n sample-api-dev get serviceaccount,role,rolebinding | grep chaos
kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
kubectl -n sample-api-dev get pods -o wide
```

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Delete the one-off chaos Job and confirm the sample API has returned to its steady state.

## Next Steps
Project capstone and operational validation.
