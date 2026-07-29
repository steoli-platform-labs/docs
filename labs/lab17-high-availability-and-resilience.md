# Lab 17 - High Availability and Resilience

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Operations |
| **Lab** | 17 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-60 minutes |
| **Estimated Cost** | Free |
| **Primary Tools** | Helm, kubectl, Argo CD |

## Introduction

This lab validates the sample application's availability and resilience configuration.

The lab validates probes, disruption handling and scheduling rules so the workload behaves predictably during node maintenance, pod restarts and normal cluster changes.

Concepts introduced in this lab include high availability, resilience, readiness probes, liveness probes, startup probes, PodDisruptionBudgets, anti-affinity and topology spread constraints. See the [Concepts Reference](../concepts/README.md) for why each setting matters.

## Outcome
Validate the sample API's availability and resilience controls in the complete platform reference implementation.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 16 completed
- AWS CLI, Terraform, kubectl and Helm installed
- Repository URLs configured

## Files to Review
Review these files before validation:

- `helm-charts/charts/sample-api/templates/rollout.yaml` and `deployment.yaml`: probes, resources and pod template settings.
- `helm-charts/charts/sample-api/templates/pdb.yaml`: disruption protection.
- `helm-charts/charts/sample-api/values.yaml`: replica count, autoscaling and resource defaults.
- `platform-config/clusters/dev/sample-api-dev.yaml`: dev-specific replica and autoscaling values.

## Step-by-Step Implementation

This lab tests resilience in layers. The Rollout keeps the desired number of pods running, probes decide when a pod is safe to receive traffic, the PodDisruptionBudget controls voluntary evictions and node placement affects how much a single node or zone problem can hurt the app. Each step below looks at one of those layers before you intentionally disrupt the workload.

1. Review the currently configured replica, autoscaling and disruption-budget values:

   ```bash
   cd "$WORKSPACE"

   printf '\n===== Default sample-api replica and autoscaling values =====\n'
   yq '.replicaCount, .autoscaling' helm-charts/charts/sample-api/values.yaml
   printf '\n===== Default sample-api PodDisruptionBudget values =====\n'
   yq '.pdb' helm-charts/charts/sample-api/values.yaml
   printf '\n===== Dev sample-api Helm values =====\n'
   yq '.spec.source.helm.values' platform-config/clusters/dev/sample-api-dev.yaml
   ```

   Expected output: chart defaults should show `replicaCount: 3`, autoscaling enabled with `minReplicas: 3`, and `pdb: {enabled: true, maxUnavailable: 1}`. The dev environment values should override the steady-state size to `replicaCount: 2` and autoscaling `minReplicas: 2`, while not overriding `pdb`.

   Because dev does not override `pdb`, it inherits the chart's `PodDisruptionBudget` with `maxUnavailable: 1`. With two ready dev replicas, Kubernetes should allow one voluntary disruption at a time, such as one pod eviction during node drain, while preventing both replicas from being voluntarily evicted together.

2. Review the sample API chart templates for probes and disruption protection:

   ```bash
   printf '\n===== sample-api Rollout template =====\n'
   sed -n '1,200p' helm-charts/charts/sample-api/templates/rollout.yaml
   printf '\n===== sample-api Deployment template =====\n'
   sed -n '1,120p' helm-charts/charts/sample-api/templates/deployment.yaml
   printf '\n===== sample-api PDB template =====\n'
   sed -n '1,120p' helm-charts/charts/sample-api/templates/pdb.yaml
   ```

   In the `Rollout` template, look for `kind: Rollout`, `replicas: {{ .Values.replicaCount }}`, the canary `steps`, `terminationGracePeriodSeconds: 30`, `readinessProbe` on `/ready`, `livenessProbe` on `/health`, resource requests/limits and `APP_VERSION` from the image tag. This is the template used by the GitOps-managed dev workload because the chart default has `rollout.enabled: true`.

   In the `Deployment` template, look for the same basic pod controls plus `startupProbe`, preferred pod anti-affinity on `kubernetes.io/hostname` and `topologySpreadConstraints` across `topology.kubernetes.io/zone`. This template is reviewed because it shows the non-Rollout workload pattern, but those Deployment-only scheduling fields are not active when the workload is rendered as an Argo Rollout.

   This distinction matters: a chart can contain more than one rendering path. In dev, the live workload uses the Rollout path. The Deployment path is still useful to review because it shows reusable chart behavior, but reviewing it does not mean those fields are currently applied to the live Rollout.

   In the `PodDisruptionBudget` template, confirm `maxUnavailable` is rendered from `.Values.pdb.maxUnavailable` and the selector uses `app.kubernetes.io/name: sample-api`. That selector is what connects the PDB to the sample API pods.

3. Render the chart locally and confirm the HA settings are present:

   ```bash
   printf '\n===== sample-api Helm lint =====\n'
   helm lint helm-charts/charts/sample-api
   printf '\n===== Render sample-api chart =====\n'
   helm template sample-api helm-charts/charts/sample-api \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/dev/sample-api-dev.yaml) \
     --set rollout.enabled=false \
     > /tmp/sample-api-ha.yaml
   printf '\n===== Rendered HA settings =====\n'
   grep -nE 'readinessProbe|livenessProbe|startupProbe|PodDisruptionBudget|topologySpreadConstraints|podAntiAffinity' /tmp/sample-api-ha.yaml
   ```

   `helm lint` should end with `1 chart(s) linted, 0 chart(s) failed`. The render command intentionally sets `rollout.enabled=false` so you can inspect the Deployment form of the chart, including `startupProbe`, `podAntiAffinity` and `topologySpreadConstraints`.

   Local rendering is a safe preview, not a deployment. This step validates chart capability and generated YAML; it does not change the live cluster.

   Expected grep output should include lines for `readinessProbe`, `livenessProbe`, `startupProbe`, `PodDisruptionBudget`, `podAntiAffinity` and `topologySpreadConstraints`. If any of those are missing, check whether the chart changed or whether the render command used different values. Do not claim that the lab validates a setting that is not rendered.

4. Refresh Argo CD and confirm `sample-api` is healthy:

   ```bash
   printf '\n===== Refresh dev root =====\n'
   kubectl -n argocd annotate application platform-root-dev argocd.argoproj.io/refresh=hard --overwrite
   printf '\n===== sample-api-dev Application =====\n'
   kubectl -n argocd get application sample-api-dev -o wide
   ```

   The refresh annotation asks Argo CD to re-read the current Git revision. The `kubectl get application` output should show `sample-api-dev` moving toward `Synced` and `Healthy`. If it remains `OutOfSync`, wait briefly and run the command again. If it shows `Degraded`, describe the Application before continuing because the workload may not be safe to disrupt.

5. Inspect the deployed workload before testing recovery:

   ```bash
   printf '\n===== sample-api workload resources =====\n'
   kubectl -n sample-api-dev get rollout,pod,pdb -o wide
   printf '\n===== sample-api PDB details =====\n'
   kubectl -n sample-api-dev describe pdb sample-api
   printf '\n===== sample-api pod placement =====\n'
   kubectl -n sample-api-dev get pods \
     -o 'custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,READY:.status.containerStatuses[0].ready'
   printf '\n===== Node zones =====\n'
   kubectl get nodes -L topology.kubernetes.io/zone
   ```

   Expected workload output: one `rollout.argoproj.io/sample-api`, at least two ready pods and one `poddisruptionbudget.policy/sample-api`. The PDB details should show `Max unavailable: 1`, current healthy pods and allowed disruptions. With two ready replicas, `Allowed disruptions` should normally be `1`; if it is `0`, Kubernetes does not currently think one pod can be safely evicted.

   Use the pod placement and node zone output to understand the blast radius of the next tests. If pods are on different nodes, pod deletion and node drain better represent high availability. If all replicas are on one node, pod deletion can still be tested, but node failure and zone-spread claims cannot be fully validated in that cluster shape.

   Read these outputs as three layers: the Rollout should maintain replica count, the PDB should limit voluntary disruption and pod placement shows whether one node problem could affect all replicas.

6. Run continuous traffic while testing recovery:

   ```bash
   kubectl -n sample-api-dev port-forward svc/sample-api 8080:80
   ```

   In another terminal:

   ```bash
   while true; do date -u; curl -fsS http://localhost:8080/health || echo "request failed"; sleep 2; done
   ```

   Keep the first terminal open for the port-forward. The second terminal should print a UTC timestamp followed by a successful health response every two seconds. If port-forwarding is not ready yet, the first one or two requests may fail; wait until the loop is consistently successful before starting disruption tests.

   Do not delete or drain anything until the health loop has at least three consecutive successful responses. If the port-forward exits, restart it and re-establish a steady baseline first.

   The health loop establishes steady state before failure. If the app is already unhealthy before you delete anything, you cannot tell whether later failures were caused by your test or by an existing problem.

   During pod deletion or node drain, occasional connection resets can happen if the local port-forward target disappears. `kubectl port-forward svc/sample-api` still attaches to a specific backend connection; if that backend pod is the one deleted, the port-forward process can exit. In that case the health loop will keep printing `Failed to connect to localhost port 8080` until you restart the port-forward. That means the local tunnel died, not necessarily that the Kubernetes Service is down.

7. Run controlled pod deletion and measure recovery:

   ```bash
   POD=$(kubectl -n sample-api-dev get pod -l app.kubernetes.io/name=sample-api -o jsonpath='{.items[0].metadata.name}')
   printf '\n===== Delete pod %s =====\n' "$POD"
   kubectl -n sample-api-dev delete pod "$POD"
   printf '\n===== Watch replacement pods =====\n'
   kubectl -n sample-api-dev get pods -w
   ```

   Expected behavior: the selected pod should move to `Terminating`, and Kubernetes should create a replacement pod. The replacement normally moves through `Pending`, `ContainerCreating` and then `Running` with `READY` becoming `1/1`. Press `Ctrl-C` after the replacement pod is running and ready.

   This is safe because pods are disposable members of a higher-level workload. The Rollout and ReplicaSet notice that one replica disappeared and create a replacement; readiness then controls when the new pod can receive Service traffic.

   While the pod is being replaced, the continuous health loop should keep returning successful responses once the port-forward is attached to a live endpoint. If requests fail continuously with `Failed to connect to localhost port 8080`, check the first terminal. If the port-forward exited, restart `kubectl -n sample-api-dev port-forward svc/sample-api 8080:80` and continue observing. If the port-forward is still running but requests fail, then inspect pod readiness, Service endpoints and events before moving on.

8. Drain one worker only when the lab environment has enough spare capacity:

   ```bash
   SAMPLE_POD=$(kubectl -n sample-api-dev get pod -l app.kubernetes.io/name=sample-api -o jsonpath='{.items[0].metadata.name}')
   TEST_NODE=$(kubectl -n sample-api-dev get pod "$SAMPLE_POD" -o jsonpath='{.spec.nodeName}')

   printf '\n===== Drain node %s =====\n' "$TEST_NODE"
   kubectl drain "$TEST_NODE" --ignore-daemonsets --delete-emptydir-data
   printf '\n===== Wait for sample-api readiness =====\n'
   kubectl -n sample-api-dev wait --for=condition=Ready pod \
     -l app.kubernetes.io/name=sample-api \
     --timeout=5m
   printf '\n===== sample-api pods after drain =====\n'
   kubectl -n sample-api-dev get pods -o wide
   printf '\n===== Uncordon node %s =====\n' "$TEST_NODE"
   kubectl uncordon "$TEST_NODE"
   ```

   This step tests voluntary disruption handling. `kubectl drain` cordons the node, evicts eligible pods and waits for replacements. The PDB should allow only one sample API pod eviction at a time. If the command blocks with a PDB-related message, that can be correct protection: Kubernetes is refusing to reduce availability below the budget.

   Before running the drain, confirm there are at least two schedulable nodes or enough autoscaling capacity for a replacement, no sample API pods are already `Pending` and the PDB `Allowed disruptions` value is `1`. If `Allowed disruptions` is `0`, skip the drain and use pod deletion as the controlled recovery test.

   Draining simulates planned node maintenance. Kubernetes cordons the node so no new pods land there, then evicts eligible pods. A PDB protects voluntary evictions like drain operations, but it cannot prevent every unplanned failure such as a node suddenly disappearing.

   Only run this in a lab cluster with enough spare capacity or autoscaling capacity to place replacements. If the replacement pod stays `Pending`, stop and inspect scheduling events; do not keep draining additional nodes. After the test, `kubectl uncordon` returns the node to scheduling service. Confirm the continuous health loop has recovered before ending the lab.

## Expected Results
The sample API has health probes and disruption protection that keep it available during controlled failures. The lab also verifies the Deployment rendering path for startup probes and scheduling preferences, while the live dev workload remains an Argo Rollout.

## Validation
- At least the documented number of replicas are available.
- The live Rollout renders and runs readiness and liveness probes.
- The Deployment render path includes startup probes, pod anti-affinity and topology spread constraints.
- Deleting a pod causes automatic replacement without sustained service failure.
- PDB allows one voluntary disruption at a time and blocks disruption beyond `maxUnavailable`.
- Graceful termination completes within the configured grace period.
- Autoscaling, disruption budgets and available capacity do not conflict during the controlled tests.

## Troubleshooting
Start with workload status, events and scheduling placement:

```bash
printf '\n===== sample-api PDB details =====\n'
kubectl -n sample-api-dev describe pdb sample-api
printf '\n===== sample-api pods =====\n'
kubectl -n sample-api-dev get pods -o wide
printf '\n===== sample-api events =====\n'
kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
printf '\n===== Node zones =====\n'
kubectl get nodes -L topology.kubernetes.io/zone
```

If the PDB blocks a drain:

- Confirm the current replica count and ready pod count.
- Confirm `maxUnavailable` still allows the intended maintenance action.
- This may be correct behavior; a PDB should block voluntary disruption that would reduce availability too far.

If all pods schedule on one node:

- Confirm whether the live workload is a Rollout or Deployment. In this lab, the Rollout path is active for dev and does not currently include the Deployment-only anti-affinity and topology spread fields.
- Confirm the cluster has enough nodes and zones before making any availability claims based on node or zone spread.
- Pod deletion still validates replacement behavior even when all replicas are on one node.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Uncordon any node drained during validation and remove temporary rendered files such as `/tmp/sample-api-ha.yaml`.

```bash
printf '\n===== Confirm nodes are schedulable =====\n'
kubectl get nodes
printf '\n===== Remove temporary HA render =====\n'
rm -f /tmp/sample-api-ha.yaml
```

## Next Steps
Continue with [Lab 18 - Chaos Engineering](./lab18-chaos-engineering.md).
