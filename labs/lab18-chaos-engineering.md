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

Concepts introduced in this lab include chaos engineering, controlled failure injection, steady state, recovery objectives, Kubernetes Jobs and least-privilege RBAC for test automation. See the [Concepts Reference](../concepts/README.md) for how chaos validation fits into platform operations.

## Outcome
Implement and validate Chaos Engineering in the complete platform reference implementation.

## Prerequisites
Complete Lab 01 - Lab 17. AWS CLI, Terraform, kubectl and Helm must be installed, with repository URLs configured.

## Repository Changes
Primary implementation: `platform-config/chaos/delete-pod.yaml`, including the chaos Job and least-privilege RBAC used to delete one sample API pod.

## Files to Review
Review these files before validation:

- `platform-config/chaos/delete-pod.yaml`: one-off chaos Job, ServiceAccount, Role and RoleBinding.
- `platform-config/clusters/dev/sample-api.yaml`: workload under test.
- `helm-charts/charts/sample-api/templates/pdb.yaml`: availability expectation during disruption.

## Step-by-Step Implementation

1. Confirm the chaos manifest exists before starting:

   ```bash
   cd "$WORKSPACE"
   test -f platform-config/chaos/delete-pod.yaml
   ```

   If the file does not exist, create the chaos experiment manifest first. It should include a ServiceAccount, Role, RoleBinding and one Job that deletes only one matching sample API pod.

2. Review the chaos manifest target and RBAC:

   ```bash
   yq '.kind, .metadata.name' platform-config/chaos/delete-pod.yaml
   grep -nE 'kind: (ServiceAccount|Role|RoleBinding|Job)|name: chaos-runner|delete|pods|sample-api' platform-config/chaos/delete-pod.yaml
   ```

   Confirm the Job targets only `sample-api` pods in `sample-api-dev`. The Role should allow the minimum actions needed for the experiment and should not grant broad workload mutation permissions.

3. Validate the chaos manifest and establish the steady state before injecting failure:

   ```bash
   kubectl apply --dry-run=client -f platform-config/chaos/delete-pod.yaml
   kubectl -n sample-api-dev get rollout,pod,pdb
   kubectl -n argocd get applications.argoproj.io -o wide
   ```

   Do not inject failure unless the sample API starts healthy and Argo CD is already synced.

4. Verify the chaos identity before execution:

   ```bash
   kubectl -n sample-api-dev get serviceaccount chaos-runner
   kubectl -n sample-api-dev auth can-i delete pods \
     --as=system:serviceaccount:sample-api-dev:chaos-runner
   kubectl -n sample-api-dev auth can-i delete deployments \
     --as=system:serviceaccount:sample-api-dev:chaos-runner
   ```

   The first answer should be `yes`; the second should be `no`.

5. Start a simple availability check in a separate terminal:

   ```bash
   kubectl -n sample-api-dev port-forward svc/sample-api 8080:80
   ```

   In another terminal:

   ```bash
   while true; do date -u; curl -fsS http://localhost:8080/health || echo "request failed"; sleep 2; done
   ```

   This establishes the steady state and lets you see whether the controlled failure causes user-visible errors.

6. Run the one-off chaos Job and watch Kubernetes replace the deleted pod:

   ```bash
   kubectl create -f platform-config/chaos/delete-pod.yaml
   kubectl -n sample-api-dev logs -f job/delete-sample-api-pod
   kubectl -n sample-api-dev get pods -w
   kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
   ```

   Expected behavior: one pod is deleted, the Rollout/ReplicaSet creates a replacement and the service returns to the expected ready replica count.

7. Validate recovery through platform signals:

   ```bash
   kubectl -n sample-api-dev get rollout,pod,pdb -o wide
   kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
   kubectl -n argocd get application sample-api -o wide
   ```

   In Grafana, check Prometheus metrics, Loki logs and Tempo traces for the test window if those signals are available. The key question is whether the platform recovered within the expected time and whether the observability stack made the disruption visible.

8. Remove the one-off chaos Job after validation:

   ```bash
   kubectl -n sample-api-dev delete job delete-sample-api-pod
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
kubectl -n sample-api-dev describe job delete-sample-api-pod
kubectl -n sample-api-dev get serviceaccount,role,rolebinding | grep chaos
kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
kubectl -n sample-api-dev get pods -o wide
```

If the chaos Job cannot start:

- Confirm the `chaos-runner` ServiceAccount exists.
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
