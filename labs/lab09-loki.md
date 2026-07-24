# Lab 09 - Loki and Alloy

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Observability & Operations |
| **Lab** | 09 |
| **Difficulty** | Advanced |
| **Estimated Time** | 30–60 minutes |
| **Estimated Cost** | Low |
| **Terraform** | No |
| **Kubernetes** | Yes |
| **GitOps** | Yes |

## Introduction

This lab introduces centralized logging using Grafana Loki.

Loki stores Kubernetes logs while Grafana Alloy collects logs from the cluster and forwards them to Loki. Grafana is extended with Loki as an additional data source, providing a unified interface for metrics and logs.

Concepts introduced in this lab include logs, log aggregation, Loki, Alloy, DaemonSets, labels and Grafana data sources. See the [Concepts Reference](../concepts/README.md) for how logs differ from metrics and traces.

## Outcome

Implement and validate Loki and Alloy in the complete platform reference implementation.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 08 completed
- Prometheus and Grafana operational
- AWS CLI, Terraform, kubectl and Helm installed, with repository URLs configured

## Architecture

```text
             Kubernetes Pods
                    │
               Container Logs
                    │
             Grafana Alloy
                    │
                 Grafana Loki
                    │
               Log Storage
                    │
                 Grafana
                    │
            Metrics + Logs
```

## AWS Resources

No additional AWS infrastructure is provisioned during this lab.

Loki and Grafana Alloy are deployed into the existing Amazon EKS cluster using ArgoCD and Helm.

## Design Decisions

The logging platform follows cloud-native observability best practices.

- **GitOps deployment:** All logging components are deployed through ArgoCD. No manual Helm installations are performed.

- **Loki:** Grafana Loki is selected as the centralized logging platform because it integrates natively with Grafana and is optimized for Kubernetes environments.

- **Grafana Alloy:** Grafana Alloy is used as the log collection agent. Alloy replaces Promtail and provides a unified telemetry collector capable of collecting logs, metrics and traces.

- **Unified observability:** Grafana provides a single interface for metrics and logs. Distributed tracing will be integrated in the next lab.

- **Label-based indexing:** Loki indexes labels rather than full log contents, reducing storage requirements and improving scalability.

- **Platform-first deployment:** Logging is enabled for both platform services and application workloads.

## Implementation Overview

This lab consists of the following high-level tasks.

1. Configure the Loki Helm chart
2. Configure Grafana Alloy
3. Create ArgoCD Applications
4. Synchronize applications
5. Configure Grafana data sources
6. Verify log collection
7. Query Kubernetes logs
8. Validate end-to-end logging

## Repository Changes

Primary implementation: `platform-config/clusters/dev/loki.yaml` and `platform-config/clusters/dev/alloy.yaml`.

`loki.yaml` deploys Loki in single-binary mode with filesystem-backed ephemeral storage for this development lab. This keeps Lab 09 lightweight and avoids creating object storage or persistent volumes before the later AWS storage and production-hardening labs.

`alloy.yaml` deploys Alloy as a DaemonSet and configures a Kubernetes API-based log pipeline from pod discovery to Loki.

## Files to Review

Review these files before validation:

- `platform-config/clusters/dev/loki.yaml`: Loki Helm chart version, single-binary mode, filesystem storage and replica settings.
- `platform-config/clusters/dev/alloy.yaml`: Alloy Helm chart version, node-local pod discovery and log forwarding pipeline.
- `platform-config/bootstrap/root-application.yaml`: root Argo CD Application that discovers `clusters/dev/*.yaml`.

## Step-by-Step Implementation

1. Review the Loki desired state:

   ```bash
   cd "$WORKSPACE/platform-config"
   yq '.spec.source' clusters/dev/loki.yaml
   ```

   Confirm these values are intentional for the lab:

   - `repoURL` is `https://grafana.github.io/helm-charts`.
   - `chart` is `loki`.
   - `targetRevision` is pinned instead of using `*`, so the lab does not drift when Grafana publishes a new chart.
   - `deploymentMode` is `SingleBinary`, which runs Loki as one stateful workload for a small development cluster.
   - `loki.storage.type` is `filesystem`, so this lab does not need S3 or another object store.
   - `singleBinary.persistence.enabled` is `false`, so Loki does not create a PVC or require a cluster `StorageClass`.
   - `singleBinary.extraVolumes` and `singleBinary.extraVolumeMounts` mount an `emptyDir` at `/var/loki`, giving Loki writable ephemeral storage while keeping the lab lightweight.
   - `gateway`, `lokiCanary` and Helm `test` are disabled to keep the lab small enough for the current development cluster.
   - `loki.useTestSchema` is enabled for this non-production lab. Production Loki deployments should use an explicit schema and object storage.

2. Review the Alloy desired state:

   ```bash
   yq '.spec.source' clusters/dev/alloy.yaml
   ```

   Confirm these values are intentional for the lab:

   - `chart` is `alloy`.
   - `targetRevision` is pinned.
   - `discovery.kubernetes "pods"` discovers pods from the Kubernetes API.
   - The pod field selector limits each Alloy DaemonSet pod to logs from workloads on its own node, avoiding duplicate collection.
   - `discovery.relabel "pods"` keeps the internal pod identity labels required by `loki.source.kubernetes` and adds query-friendly Loki labels such as `namespace`, `pod`, `container` and `app`.
   - `loki.source.kubernetes "pods"` reads Kubernetes pod logs through the Kubernetes API.
   - `loki.write "default"` forwards logs to `http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push`.

3. Compare the pinned chart versions with the latest available chart versions:

   ```bash
   echo "Pinned Loki chart:  $(yq -r '.spec.source.targetRevision' clusters/dev/loki.yaml)"
   helm show chart loki --repo https://grafana.github.io/helm-charts | yq '.version'

   echo "Pinned Alloy chart: $(yq -r '.spec.source.targetRevision' clusters/dev/alloy.yaml)"
   helm show chart alloy --repo https://grafana.github.io/helm-charts | yq '.version'
   ```

   The pinned versions in `clusters/dev/loki.yaml` and `clusters/dev/alloy.yaml` are the versions tested by this lab. Newer chart versions may exist by the time you run the lab. Do not change the pinned versions just because newer versions are available; Helm charts can change required values between releases.

   If you intentionally update a chart version, update the YAML, render the chart locally, review the rendered manifests and commit the tested change. Treat chart upgrades as deliberate maintenance, not as an automatic part of the lab.

4. Render both Helm charts locally before relying on Argo CD:

   ```bash
   yq -r '.spec.source.helm.values' clusters/dev/loki.yaml \
     | helm template loki loki \
       --repo https://grafana.github.io/helm-charts \
       --version "$(yq -r '.spec.source.targetRevision' clusters/dev/loki.yaml)" \
       --namespace monitoring \
       --values - \
       >/dev/null

   yq -r '.spec.source.helm.values' clusters/dev/alloy.yaml \
     | helm template alloy alloy \
       --repo https://grafana.github.io/helm-charts \
       --version "$(yq -r '.spec.source.targetRevision' clusters/dev/alloy.yaml)" \
       --namespace monitoring \
       --values - \
       >/dev/null
   ```

   These commands catch chart value errors before Argo CD tries to render the Applications. If Loki reports a missing bucket or missing schema here, Argo CD will also fail and no Loki pods will be created.

   No output is expected when both commands succeed because the rendered manifests are redirected to `/dev/null`. A successful command returns to the shell prompt with exit code `0`.

   To confirm the exit code after a render command, run:

   ```bash
   echo $?
   ```

   Expected result:

   ```text
   0
   ```

   Any Helm render error prints to the terminal and returns a non-zero exit code.

5. Commit and push the desired state if you changed it:

   ```bash
   git status --short
   ```

   If this command prints no files, your local repository already matches Git and there is nothing to commit for this step.

   If you edited `loki.yaml`, `alloy.yaml` or chart versions during this lab, commit and push those changes:

   ```bash
   git add clusters/dev/loki.yaml clusters/dev/alloy.yaml
   git commit -m "feat: configure loki and alloy"
   git push
   ```

   Argo CD reconciles from Git. Local uncommitted changes are not deployed by Argo CD.

6. Let Argo CD reconcile Loki and Alloy from Git:

   ```bash
   kubectl -n argocd get application loki alloy -o wide
   kubectl -n argocd annotate application loki argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd annotate application alloy argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application loki alloy -o wide
   ```

   `SYNC STATUS` should move to `Synced`. If an Application shows `Unknown`, Argo CD could not compare the live cluster to the target manifests. The most common cause is a Helm render error, and pods will not exist until that is fixed.

7. If either Application is not `Synced`, inspect the Argo CD condition before checking pods:

   ```bash
   kubectl -n argocd describe application loki
   kubectl -n argocd describe application alloy
   ```

   Look for `Status.Conditions`. A message such as `Failed to load target state` or `failed to generate manifest` means the Helm chart did not render. Fix the values in Git, push the change, then refresh the Application again.

8. Validate that the workloads exist and are ready:

   ```bash
   kubectl -n argocd get application loki alloy -o wide
   kubectl -n monitoring get pods -l app.kubernetes.io/name=loki
   kubectl -n monitoring get pods -l app.kubernetes.io/name=alloy
   kubectl -n monitoring get svc loki
   ```

   Expected result:

   - Loki has a `loki-0` pod from the single-binary StatefulSet.
   - Alloy has one pod per schedulable node because it runs as a DaemonSet.
   - The `loki` service exposes port `3100` inside the cluster.

9. Check Alloy logs for collection and forwarding activity:

   ```bash
   kubectl -n monitoring logs -l app.kubernetes.io/name=alloy --since=10m --tail=200
   ```

   The logs should not show repeated connection failures to Loki. Short startup messages are normal while Loki is becoming ready.

10. Port-forward Loki and check readiness:

   ```bash
   kubectl -n monitoring port-forward svc/loki 3100:3100
   ```

   In another terminal:

   ```bash
   curl -fsS http://localhost:3100/ready
   ```

   A successful response confirms the Loki HTTP API is reachable through the local port-forward.

11. Generate or locate a known application log line:

   ```bash
   kubectl -n sample-api-dev logs -l app.kubernetes.io/name=sample-api --tail=5
   ```

   This command reads recent application logs from Kubernetes. Alloy should collect the same pod logs and send them to Loki.

12. Query Loki for recent application logs:

   ```bash
   curl -G -fsS http://localhost:3100/loki/api/v1/query_range \
     --data-urlencode 'query={namespace="sample-api-dev"}' \
     --data-urlencode "start=$(date -u -v-10M +%s)000000000" \
     --data-urlencode "end=$(date -u +%s)000000000"
   ```

   The response should include a `status` of `success`. If the `result` array is empty, wait a minute and retry. Log ingestion is usually quick, but Alloy must discover the pod and send the log stream before Loki can return it.

13. Add Loki as a Grafana data source through the Grafana UI:

   ```bash
   kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
   ```

   In Grafana:

   - Open `http://localhost:3000`.
   - Go to `Connections` then `Data sources`.
   - Add a Loki data source.
   - Use `http://loki.monitoring.svc.cluster.local:3100` as the URL.
   - Save and test the data source.

14. Query logs in Grafana Explore:

   Open `Explore`, choose the Loki data source and run:

   ```logql
   {namespace="sample-api-dev"}
   ```

   This confirms logs are usable from the same Grafana interface that already shows Prometheus metrics.

## Expected Results

The `loki` and `alloy` Argo CD Applications reconcile successfully and log data begins flowing into Loki.

## Validation

- Both Argo CD applications are healthy.
- Loki reports ready.
- Alloy runs on every intended node or as the configured workload mode.
- Alloy logs show successful discovery and writes, without authentication or connection failures.
- A log line from `sample-api-dev` becomes queryable in Loki/Grafana within the expected ingestion delay.
- Labels such as namespace, pod and container are present and not excessively high-cardinality.

## Troubleshooting

Start with the Argo CD Applications and monitoring namespace:

```bash
kubectl -n argocd describe application loki
kubectl -n argocd describe application alloy
kubectl -n monitoring get pods -o wide
kubectl -n monitoring get events --sort-by=.lastTimestamp
```

If `loki` shows `Unknown`:

- Read `kubectl -n argocd describe application loki` before checking pods.
- `Unknown` often means Argo CD could not render the Helm chart, so Kubernetes resources were never created.
- A missing `loki.storage.bucketNames.chunks` message means the chart is trying to run in object-storage mode without bucket names.
- A missing `schema_config` message means the chart needs either an explicit Loki schema or `loki.useTestSchema: true` for a temporary lab deployment.

If `kubectl -n monitoring get pods -l app.kubernetes.io/name=loki` returns no resources:

- Confirm the Argo CD Application is `Synced` first.
- Confirm the `loki` Application points to the `monitoring` namespace.
- Confirm the chart rendered successfully with the local `helm template` command from the implementation steps.

If `loki-0` stays `Pending` because of `storage-loki-0`:

- Check the PVC with `kubectl -n monitoring get pvc storage-loki-0`.
- A message such as `no persistent volumes available for this claim and no storage class is set` means the cluster has no default dynamic volume provisioner.
- For this lab, `singleBinary.persistence.enabled: false` avoids that dependency. Later production-oriented labs can add durable object storage and retention.

If `loki-0` enters `CrashLoopBackOff` with `mkdir /var/loki: read-only file system`:

- Confirm `singleBinary.extraVolumes` defines an `emptyDir` named `storage`.
- Confirm `singleBinary.extraVolumeMounts` mounts that volume at `/var/loki`.
- Loki needs `/var/loki` to be writable even when persistence is disabled.

If Alloy is healthy but Loki has no application logs:

- Confirm the Alloy pod discovery selector matches the node name exposed through `HOSTNAME`.
- Confirm Alloy logs do not show connection errors to `loki.monitoring.svc.cluster.local:3100`.
- Confirm the application namespace has recent logs with `kubectl -n sample-api-dev logs -l app.kubernetes.io/name=sample-api --tail=20`.
- Retry the Loki query with a wider time range, such as 30 minutes.

## Final Repository State

The implementation remains GitOps-driven and mergeable to `main`.

## Best Practices

This lab follows cloud-native logging best practices.

- Deploy logging components using GitOps.
- Use Grafana Alloy for telemetry collection.
- Collect logs from both platform and application workloads.
- Use labels consistently.
- Avoid unnecessary log retention.

## Cleanup

No cleanup is required.

Loki and Grafana Alloy remain permanent platform services.

## References

- [Grafana Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/latest/)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Kubernetes Logging Architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/)
- [CNCF Observability Landscape](https://landscape.cncf.io/card-mode?category=observability-and-analysis)

## Next Steps

Continue with [Lab 10 - Tempo and OpenTelemetry](./lab10-tempo.md).
