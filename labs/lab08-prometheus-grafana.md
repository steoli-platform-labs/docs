# Lab 08 - Prometheus and Grafana

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Services |
| **Lab** | 08 |
| **Difficulty** | Advanced |
| **Estimated Time** | 45–75 minutes |
| **Estimated Cost** | Low |
| **Terraform** | No |
| **Kubernetes** | Yes |
| **GitOps** | Yes |

## Introduction

This lab introduces Prometheus and Grafana to provide observability for the Kubernetes platform.

Prometheus collects metrics from Kubernetes and platform components, while Grafana visualizes those metrics through dashboards. Together they establish the monitoring foundation for the platform.

This observability platform will be extended with centralized logging in Lab 09 and distributed tracing in Lab 10.

## Outcome

Implement and validate Prometheus and Grafana in the complete platform reference implementation.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 07 completed
- ArgoCD operational
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

Prometheus and Grafana are deployed into the existing Amazon EKS cluster using ArgoCD and Helm.

## Design Decisions

The observability platform follows cloud-native best practices.

- **GitOps deployment:** Prometheus and Grafana are deployed through ArgoCD. No manual Helm installations are performed.

- **kube-prometheus-stack:** The platform uses the community-maintained **kube-prometheus-stack** Helm chart, which includes Prometheus Operator and recommended Kubernetes monitoring components.

- **Prometheus Operator:** Prometheus Operator manages Prometheus instances and monitoring resources such as ServiceMonitors and PodMonitors.

- **Grafana as the observability portal:** Grafana serves as the primary interface for platform observability. Additional data sources introduced in later labs will integrate into the existing Grafana instance.

- **Standard dashboards:** Community-maintained Kubernetes dashboards are used as the initial monitoring dashboards. Custom dashboards may be added later as the platform evolves.

- **Metrics first:** Metrics provide the first layer of observability. Logging and distributed tracing will be introduced in subsequent labs.

## Implementation Overview

This lab consists of the following high-level tasks.

1. Configure the kube-prometheus-stack Helm chart
2. Create an ArgoCD Application
3. Synchronize the application
4. Verify Prometheus deployment
5. Verify Grafana deployment
6. Configure data sources
7. Import Kubernetes dashboards
8. Verify metrics collection
9. Explore the Grafana interface

## Repository Changes

Primary implementation: `platform-config/clusters/dev/prometheus.yaml`.

## Files to Review

Review the observability desired-state files and update any environment-specific values before validation.

## Step-by-Step Implementation

1. Review `platform-config/clusters/dev/prometheus.yaml` and confirm the chart, namespace and values match the lab environment.
2. Commit and push any required `platform-config` changes.
3. Let Argo CD reconcile the `prometheus` Application from Git:

   ```bash
   cd "$WORKSPACE"
   kubectl -n argocd get application prometheus -o wide
   kubectl -n argocd annotate application prometheus argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application prometheus -o wide
   ```

4. Verify that Prometheus, Grafana and the monitoring CRDs become healthy:

   ```bash
   kubectl -n argocd get application prometheus -o wide
   kubectl -n monitoring get pods
   kubectl -n monitoring get servicemonitors,podmonitors,prometheusrules
   kubectl get crd | grep monitoring.coreos.com
   kubectl -n monitoring get endpoints prometheus-kube-prometheus-prometheus prometheus-grafana
   ```

   The Prometheus and Grafana services must have endpoints before port-forwarding works. If `prometheus-kube-prometheus-prometheus` shows `<none>`, inspect the Argo CD Application events before continuing because the Prometheus custom resource may not have been created yet.

5. Start a local Prometheus port-forward in a separate terminal:

   ```bash
   kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090
   ```

6. Validate metrics ingestion through Prometheus from another terminal:

   ```bash
   curl -fsS http://localhost:9090/-/ready
   curl -fsS 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool
   curl -fsS 'http://localhost:9090/api/v1/query?query=kube_pod_info' | python3 -m json.tool
   ```

   Open `http://localhost:9090/targets` and confirm that Kubernetes, kube-state-metrics and node-exporter targets are present. Some managed-control-plane targets may be unavailable on EKS depending on endpoint access, but the node, kubelet and kube-state-metrics targets should be active.

7. Get the chart-generated Grafana credentials:

   ```bash
   kubectl -n monitoring get secret prometheus-grafana \
     -o jsonpath='{.data.admin-user}' | base64 --decode; printf '\n'
   kubectl -n monitoring get secret prometheus-grafana \
     -o jsonpath='{.data.admin-password}' | base64 --decode; printf '\n'
   ```

8. Start a local Grafana port-forward in a separate terminal:

   ```bash
   kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
   ```

9. Open `http://localhost:3000` and log in with the username and password from the secret.

   Confirm the Prometheus data source is healthy from **Connections** -> **Data sources** -> **Prometheus** -> **Save & test**.

10. Review the preloaded Kubernetes dashboards in Grafana.

    Open **Dashboards** and inspect dashboards such as **Kubernetes / Compute Resources / Cluster**, **Kubernetes / Compute Resources / Namespace (Pods)** and **Node Exporter / Nodes**.

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
kubectl -n argocd describe application prometheus
kubectl -n monitoring get pods -o wide
kubectl -n monitoring get events --sort-by=.lastTimestamp
kubectl -n monitoring get endpoints prometheus-kube-prometheus-prometheus prometheus-grafana
```

If Prometheus port-forwarding times out, the Prometheus service probably has no ready endpoints. Check whether Argo CD failed to apply the Prometheus Operator CRDs:

```bash
kubectl -n argocd describe application prometheus
kubectl get crd | grep monitoring.coreos.com
```

If the Application events mention `metadata.annotations: Too long`, the Prometheus Application needs server-side apply enabled with the `ServerSideApply=true` sync option.

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
