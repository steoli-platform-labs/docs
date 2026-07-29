# Lab 08 - Prometheus and Grafana

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Services |
| **Lab** | 08 |
| **Difficulty** | Advanced |
| **Estimated Time** | 45–75 minutes |
| **Primary Tools** | Helm, kubectl, Argo CD, Prometheus, Grafana |

## Introduction

This lab introduces Prometheus and Grafana to provide observability for the Kubernetes platform.

Prometheus collects metrics from Kubernetes and platform components, while Grafana visualizes those metrics through dashboards. Together they establish the monitoring foundation for the platform.

This observability platform will be extended with centralized logging in Lab 09 and distributed tracing in Lab 10.

Concepts introduced in this lab include metrics, Prometheus, Grafana, dashboards, Prometheus Operator, CRDs, ServiceMonitors, PrometheusRules and StatefulSets. See the [Concepts Reference](../concepts/README.md) for deeper explanations.

## Outcome

Validate the Prometheus and Grafana observability foundation in the complete platform reference implementation.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 07 completed
- Argo CD operational
- Amazon EKS operational
- AWS CLI, Terraform, kubectl and Helm installed, with repository URLs configured

## Architecture

```text
                Kubernetes Cluster
                        │
         ┌──────────────┼──────────────┐
         │              │              │
     kubelet      kube-state-metrics   cAdvisor
         │              │              │
         └──────────────┼──────────────┘
                        │
                  Prometheus
                        │
                 Time Series Database
                        │
                    Grafana
                        │
                  Platform Dashboards
```

## AWS Resources

No additional AWS infrastructure is provisioned during this lab.

Prometheus and Grafana are deployed into the existing Amazon EKS cluster using Argo CD and Helm.

## Design Decisions

The observability platform follows cloud-native best practices.

- **GitOps deployment:** Prometheus and Grafana are deployed through Argo CD. No manual Helm installations are performed.

- **kube-prometheus-stack:** The platform uses the community-maintained **kube-prometheus-stack** Helm chart, which includes Prometheus Operator and recommended Kubernetes monitoring components.

- **Prometheus Operator:** Prometheus Operator manages Prometheus instances and monitoring resources such as ServiceMonitors and PodMonitors.

- **Custom Resource Definitions:** A Custom Resource Definition, or CRD, teaches Kubernetes a new resource type. Kubernetes already understands built-in types such as `Pod`, `Service` and `Deployment`; Prometheus Operator adds monitoring-specific types such as `Prometheus`, `Alertmanager`, `ServiceMonitor`, `PodMonitor`, `PrometheusRule` and `ScrapeConfig`. The CRDs must exist before Kubernetes can accept resources that use those kinds.

- **Grafana as the observability portal:** Grafana serves as the primary interface for platform observability. Additional data sources introduced in later labs will integrate into the existing Grafana instance.

- **Standard dashboards:** Community-maintained Kubernetes dashboards are used as the initial monitoring dashboards. Custom dashboards may be added later as the platform evolves.

- **Metrics first:** Metrics provide the first layer of observability. Logging and distributed tracing will be introduced in subsequent labs.

## Implementation Overview

This lab consists of the following high-level tasks.

1. Configure the kube-prometheus-stack Helm chart
2. Create an Argo CD Application
3. Synchronize the application
4. Verify Prometheus deployment
5. Verify Grafana deployment
6. Configure data sources
7. Import Kubernetes dashboards
8. Verify metrics collection
9. Explore the Grafana interface

## Files to Review

Review the Prometheus and Grafana desired state in `platform-config/clusters/dev/prometheus.yaml` and update any environment-specific values before validation.

## Step-by-Step Implementation

1. Review `platform-config/clusters/dev/prometheus.yaml` and confirm the chart, namespace and values match the lab environment.

   The Application should use a pinned `targetRevision`, `skipCrds: true`, `crds.upgradeJob.enabled: true`, `SkipDryRunOnMissingResource=true`, `ServerSideApply=true` and `Replace=true`. This lets the chart's CRD upgrade job apply Prometheus Operator CRDs server-side before Argo CD validates Prometheus custom resources, avoiding oversized client-side apply annotations on large CRDs and the CRD bundle ConfigMap.

   In this lab, CRDs are the API extensions that make resources such as `kind: Prometheus` and `kind: ServiceMonitor` valid Kubernetes objects. If those CRDs are missing, Kubernetes cannot create the Prometheus custom resource, the Prometheus Operator cannot create the Prometheus StatefulSet and the Prometheus service will have no endpoints.

2. Compare the configured chart version with the latest available chart version:

   ```bash
   cd "$WORKSPACE/platform-config"
   printf '\n===== Configured Prometheus chart =====\n'
   yq -r '.spec.source.targetRevision' clusters/dev/prometheus.yaml
   printf '\n===== Latest available Prometheus chart =====\n'
   helm show chart kube-prometheus-stack --repo https://prometheus-community.github.io/helm-charts | yq '.version'
   ```

   The pinned version in `clusters/dev/prometheus.yaml` is the version tested by this lab. Newer chart versions may exist by the time you run the lab. Do not change the pinned version just because a newer version is available; Helm charts can change required values between releases.
3. Render the chart before relying on Argo CD:

   ```bash
   helm template prometheus kube-prometheus-stack \
     --repo https://prometheus-community.github.io/helm-charts \
     --version "$(yq -r '.spec.source.targetRevision' clusters/dev/prometheus.yaml)" \
     --namespace monitoring \
     --values <(yq -r '.spec.source.helm.values' clusters/dev/prometheus.yaml) \
     >/dev/null
   ```

   No output means the chart rendered successfully. Any Helm error here will also fail in Argo CD.

   This is a preflight check. It proves Helm can combine the chart and committed values into Kubernetes YAML before Argo CD attempts the same render in the cluster workflow. Output goes to `/dev/null` because you only need to know whether rendering succeeds.
4. Let Argo CD reconcile the `prometheus` Application from Git:

   ```bash
   cd "$WORKSPACE"
   printf '\n===== Prometheus Application before refresh =====\n'
   kubectl -n argocd get application prometheus -o wide
   printf '\n===== Refresh Prometheus Application =====\n'
   kubectl -n argocd annotate application prometheus argocd.argoproj.io/refresh=hard --overwrite
   printf '\n===== Prometheus Application after refresh =====\n'
   kubectl -n argocd get application prometheus -o wide
   ```

   The refresh command should report that the `prometheus` Application was annotated. After refresh, `SYNC STATUS` should move toward `Synced`; if it stays `OutOfSync` or `Degraded`, describe the Application before checking pods.

   The annotation is a signal to Argo CD to re-read Git and chart state. It is not a manual deployment of Prometheus; Argo CD still performs the reconciliation from the committed desired state.

5. Verify that Prometheus, Grafana and the monitoring CRDs become healthy:

   ```bash
   printf '\n===== Prometheus Application =====\n'
   kubectl -n argocd get application prometheus -o wide
   printf '\n===== Monitoring pods =====\n'
   kubectl -n monitoring get pods
   printf '\n===== Prometheus custom resources =====\n'
   kubectl -n monitoring get servicemonitors,podmonitors,prometheusrules
   printf '\n===== Monitoring CRDs =====\n'
   kubectl get crd | grep monitoring.coreos.com
   printf '\n===== Prometheus and Grafana endpoints =====\n'
   kubectl -n monitoring get endpoints prometheus-kube-prometheus-prometheus prometheus-grafana
   ```

   The Prometheus and Grafana services must have endpoints before port-forwarding works. If `prometheus-kube-prometheus-prometheus` shows `<none>`, inspect the Argo CD Application events before continuing because the Prometheus custom resource may not have been created yet.

   A missing Prometheus endpoint usually means one of two things: the Prometheus CRD is missing, so Kubernetes rejected the `Prometheus` resource, or the Prometheus Operator has not reconciled that resource into a running StatefulSet yet.

6. Start a local Prometheus port-forward in a separate terminal:

   ```bash
   kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090
   ```

7. Validate metrics ingestion through Prometheus from another terminal:

   ```bash
   printf '\n===== Prometheus readiness =====\n'
   curl -fsS http://localhost:9090/-/ready
   printf '\n===== Prometheus up query =====\n'
   curl -fsS 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool
   printf '\n===== Prometheus kube_pod_info query =====\n'
   curl -fsS 'http://localhost:9090/api/v1/query?query=kube_pod_info' | python3 -m json.tool
   ```

   Open `http://localhost:9090/targets` and confirm that Kubernetes, kube-state-metrics and node-exporter targets are present. Some managed-control-plane targets may be unavailable on EKS depending on endpoint access, but the node, kubelet and kube-state-metrics targets should be active.

   `/-/ready` should return `Prometheus Server is Ready`. The API query responses should contain `"status": "success"`; `data.result` should not be empty for `up` once targets have been scraped.

   These checks answer different questions: `/-/ready` asks whether Prometheus itself is usable, `up` asks whether scrape targets are reachable and `kube_pod_info` proves Kubernetes object metrics are being ingested.

8. Get the chart-generated Grafana credentials:

   ```bash
   printf '\n===== Grafana admin username =====\n'
   kubectl -n monitoring get secret prometheus-grafana \
     -o jsonpath='{.data.admin-user}' | base64 --decode; printf '\n'
   printf '\n===== Grafana admin password =====\n'
   kubectl -n monitoring get secret prometheus-grafana \
     -o jsonpath='{.data.admin-password}' | base64 --decode; printf '\n'
   ```

9. Start a local Grafana port-forward in a separate terminal:

   ```bash
   kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
   ```

10. Open `http://localhost:3000` and log in with the username and password from the secret.

   Confirm the Prometheus data source is healthy from **Connections** -> **Data sources** -> **Prometheus** -> **Save & test**.

   A successful test shows a green success message such as `Successfully queried the Prometheus API`. If the test fails, confirm the Grafana pod can reach `http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090` and that Prometheus has endpoints.

11. Review the preloaded Kubernetes dashboards in Grafana.

    Open **Dashboards** and inspect dashboards such as:

    - **Kubernetes / Compute Resources / Cluster**
    - **Kubernetes / Compute Resources / Namespace (Pods)**
    - **Node Exporter / Nodes**

    Confirm that the dashboards show current cluster, namespace, pod, CPU, memory and node data. If a dashboard has empty panels, check the time range first, then confirm the Prometheus `up` query and target status.

## Expected Results

The `prometheus` Argo CD Application reconciles successfully and creates the monitoring stack in the configured namespace.

## Validation

- The Argo CD application is `Synced / Healthy`.
- Prometheus and Grafana pods are ready.
- Prometheus `/-/ready` returns success.
- The `up` query returns active targets and no unexpected large group of failed targets.
- Grafana can query the Prometheus data source.
- At least one dashboard shows current cluster CPU, memory and pod data.
- Alerting rules load without evaluation errors.

## Troubleshooting

Start with the Argo CD Application and monitoring pods:

```bash
printf '\n===== Prometheus Application details =====\n'
kubectl -n argocd describe application prometheus
printf '\n===== Monitoring pods =====\n'
kubectl -n monitoring get pods -o wide
printf '\n===== Monitoring events =====\n'
kubectl -n monitoring get events --sort-by=.lastTimestamp
printf '\n===== Prometheus and Grafana endpoints =====\n'
kubectl -n monitoring get endpoints prometheus-kube-prometheus-prometheus prometheus-grafana
```

If Prometheus port-forwarding times out, the Prometheus service probably has no ready endpoints. Check whether Argo CD failed to apply the Prometheus Operator CRDs:

```bash
printf '\n===== Prometheus Application details =====\n'
kubectl -n argocd describe application prometheus
printf '\n===== Monitoring CRDs =====\n'
kubectl get crd | grep monitoring.coreos.com
```

If the Application events mention `metadata.annotations: Too long`, Argo CD is trying to apply large Prometheus Operator CRDs or the chart's CRD bundle ConfigMap with client-side apply. Confirm the Prometheus Application already skips direct Helm CRD rendering, enables the chart's CRD upgrade job and uses `ServerSideApply=true` with `Replace=true`. If Argo CD blocks the sync because the Prometheus or Alertmanager resource types are missing, confirm `SkipDryRunOnMissingResource=true` is present so the CRD job can run first. If those settings are missing, stop and reconcile the desired state through the normal GitOps review path before refreshing the Application again.

If the Application events mention `no matches for kind "Prometheus"` or `no matches for kind "Alertmanager"`, Kubernetes has not registered those CRDs yet. Wait for the `prometheus-crds-upgrade` hook Job to complete, confirm the CRDs exist and let Argo CD retry the sync.

## Final Repository State

The implementation remains GitOps-driven and mergeable to `main`.

## Best Practices

This lab follows observability best practices.

- Deploy observability components using GitOps.
- Use the kube-prometheus-stack Helm chart.
- Avoid modifying community dashboards directly.
- Organize dashboards by platform domain.
- Monitor both Kubernetes and platform services.

## Cleanup

No cleanup is required.

Prometheus and Grafana remain core platform services for the remainder of the project.

## References

- [Prometheus Documentation](https://prometheus.io/docs/introduction/overview/)
- [Prometheus Operator Documentation](https://prometheus-operator.dev/docs/)
- [kube-prometheus-stack Documentation](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [CNCF Observability Landscape](https://landscape.cncf.io/card-mode?category=observability-and-analysis)

## Next Steps

Continue with [Lab 09 - Loki and Alloy](./lab09-loki.md).
