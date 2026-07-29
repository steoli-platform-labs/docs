# Lab 18 - Chaos Engineering

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Operations |
| **Lab** | 18 |
| **Difficulty** | Advanced |
| **Estimated Time** | 30-45 minutes |
| **Estimated Cost** | Free |
| **Primary Tools** | kubectl, Argo CD |

## Introduction

This lab introduces lightweight chaos validation for the platform.

The goal is to run controlled failure tests against the sample application and verify that the platform's deployment, observability and resilience settings recover as expected.

Concepts introduced in this lab include chaos engineering, controlled failure injection, steady state, recovery objectives, Kubernetes Jobs and least-privilege RBAC for test automation. See the [Concepts Reference](../concepts/README.md) for how chaos validation fits into platform operations.

## Outcome
Validate controlled chaos engineering in the complete platform reference implementation.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 17 completed
- AWS CLI, Terraform, kubectl and Helm installed
- Repository URLs configured

## Files to Review
Review these files before validation:

- `platform-config/chaos/delete-pod.yaml`: one-off chaos Job, ServiceAccount, Role and RoleBinding.
- `platform-config/clusters/dev/sample-api-dev.yaml`: dev workload under test.
- `helm-charts/charts/sample-api/templates/pdb.yaml`: availability expectation during disruption.

## Step-by-Step Implementation

1. Confirm the chaos manifest exists before starting:

   ```bash
   cd "$WORKSPACE"
   test -f platform-config/chaos/delete-pod.yaml
   ```

   If the file does not exist, stop and pull the latest `platform-config` repository before continuing. This lab expects the chaos experiment manifest to already exist.

2. Review the chaos manifest target and RBAC:

   ```bash
   printf '\n===== Chaos manifest identity =====\n'
   yq '.kind, .metadata.name' platform-config/chaos/delete-pod.yaml
   printf '\n===== Chaos manifest RBAC and target references =====\n'
   grep -nE 'kind: (ServiceAccount|Role|RoleBinding|Job)|name: chaos-runner|delete|pods|sample-api' platform-config/chaos/delete-pod.yaml
   ```

   Confirm the Job targets only `sample-api` pods in `sample-api-dev`. The Role should allow the minimum actions needed for the experiment and should not grant broad workload mutation permissions.

3. Validate the chaos manifest and establish the steady state before injecting failure:

   ```bash
   printf '\n===== Chaos manifest dry-run =====\n'
   kubectl apply --dry-run=client -f platform-config/chaos/delete-pod.yaml
   printf '\n===== sample-api steady state =====\n'
   kubectl -n sample-api-dev get rollout,pod,pdb
   printf '\n===== Argo CD Applications =====\n'
   kubectl -n argocd get applications.argoproj.io -o wide
   ```

   Do not inject failure unless the sample API starts healthy and Argo CD is already synced.

   Proceed only if the sample API Rollout has the expected ready replicas, the PDB exists and `sample-api-dev` is `Synced / Healthy`. Stop if the Rollout is degraded, has fewer ready pods than expected or has been `Progressing` for several minutes.

4. Verify the chaos identity before execution:

   ```bash
   printf '\n===== Chaos service account =====\n'
   kubectl -n sample-api-dev get serviceaccount chaos-runner
   printf '\n===== Can chaos-runner delete pods? =====\n'
   kubectl -n sample-api-dev auth can-i delete pods \
     --as=system:serviceaccount:sample-api-dev:chaos-runner
   printf '\n===== Can chaos-runner delete deployments? =====\n'
   kubectl -n sample-api-dev auth can-i delete deployments \
     --as=system:serviceaccount:sample-api-dev:chaos-runner
   ```

   The first answer should be `yes`; the second should be `no`.

   `kubectl auth can-i --as=...` impersonates the chaos ServiceAccount for the permission check. This proves the automation can do the narrow action it needs, deleting pods, without granting broader permissions such as deleting Deployments.

5. Start a simple availability check in a separate terminal:

   ```bash
   kubectl -n sample-api-dev port-forward svc/sample-api 8080:80
   ```

   In another terminal:

   ```bash
   while true; do date -u; curl -fsS http://localhost:8080/health || echo "request failed"; sleep 2; done
   ```

   This establishes the steady state and lets you see whether the controlled failure causes user-visible errors.

   Wait for at least three consecutive successful health responses before creating the chaos Job. If the port-forward exits or health checks fail before the experiment, fix the baseline first.

6. Run the one-off chaos Job and watch Kubernetes replace the deleted pod:

   ```bash
   printf '\n===== Create chaos Job =====\n'
   kubectl create -f platform-config/chaos/delete-pod.yaml
   printf '\n===== Chaos Job logs =====\n'
   kubectl -n sample-api-dev logs -f job/delete-sample-api-pod
   printf '\n===== Watch sample-api pods =====\n'
   kubectl -n sample-api-dev get pods -w
   printf '\n===== Recent sample-api events =====\n'
   kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
   ```

   Expected behavior: one pod is deleted, the Rollout/ReplicaSet creates a replacement and the service returns to the expected ready replica count.

   The Job log should show which pod was selected and deleted, then complete. Press `Ctrl-C` after the log reaches completion if the follow command remains attached. In the pod watch, continue until the replacement pod is `Running` and `READY 1/1`, then press `Ctrl-C`.

   A Kubernetes Job is one-off automation. It runs the chaos command to completion once; after it succeeds, you delete the Job so a later lab run can create a fresh one with the same name.

7. Validate recovery through platform signals:

   ```bash
   printf '\n===== sample-api recovery state =====\n'
   kubectl -n sample-api-dev get rollout,pod,pdb -o wide
   printf '\n===== Recent sample-api events =====\n'
   kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
   printf '\n===== sample-api-dev Application =====\n'
   kubectl -n argocd get application sample-api-dev -o wide
   ```

   In Grafana, check Prometheus metrics, Loki logs and Tempo traces for the test window if those signals are available. The key question is whether the platform recovered within the expected time and whether the observability stack made the disruption visible.

   For this lab, recovery is acceptable when ready replicas return to the starting count within five minutes and the health loop has no sustained failure longer than a few consecutive checks. If recovery takes longer, keep the evidence and inspect events, Rollout status and PDB status before rerunning the experiment.

8. Remove the one-off chaos Job after validation:

   ```bash
   printf '\n===== Delete chaos Job =====\n'
   kubectl -n sample-api-dev delete job delete-sample-api-pod
   printf '\n===== Remaining jobs and pods =====\n'
   kubectl -n sample-api-dev get job,pod
   ```

   Keep the workload healthy before moving on. Do not leave active chaos Jobs running.

## Expected Results
The chaos manifest is valid, the sample API starts from a healthy steady state, and the platform recovers after a controlled pod deletion.

## Validation
- The experiment deletes only a matching sample-api pod.
- Kubernetes creates a replacement automatically.
- Available replicas remain within the PDB/SLO expectation.
- Argo CD remains healthy and does not fight normal controller reconciliation.
- Metrics show the disruption and recovery.
- Logs contain the deletion/restart sequence.
- Traces show whether user requests failed or slowed.
- The API recovers within the documented recovery objective.
- The chaos Job and its RBAC are removed or reset after the test.
- A Job that references `chaos-runner` without a ServiceAccount, Role and RoleBinding cannot run and is a repository blocker, not a successful chaos test.

## Troubleshooting
Start with the chaos Job, RBAC and workload events:

```bash
printf '\n===== Chaos Job details =====\n'
kubectl -n sample-api-dev describe job delete-sample-api-pod
printf '\n===== Chaos RBAC resources =====\n'
kubectl -n sample-api-dev get serviceaccount,role,rolebinding | grep chaos
printf '\n===== sample-api events =====\n'
kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
printf '\n===== sample-api pods =====\n'
kubectl -n sample-api-dev get pods -o wide
```

If the chaos Job cannot start:

- Confirm the manifest was created with `kubectl create -f platform-config/chaos/delete-pod.yaml` before checking live RBAC resources.
- Confirm the `chaos-runner` ServiceAccount exists after the manifest is created.
- Confirm the RoleBinding points to that ServiceAccount.
- Confirm the namespace in the manifest is `sample-api-dev`.

If the Job deletes too many pods:

- Stop the test and inspect the Job command and label selector.
- Reduce the selector scope before running it again.
- Confirm the PDB and replica count still meet the availability expectation.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Delete the one-off chaos Job and confirm the sample API has returned to its steady state.

## Next Steps
Project capstone and operational validation.
