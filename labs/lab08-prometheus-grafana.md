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
   kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090
   ```

5. Validate metrics ingestion through Prometheus and Grafana. In another terminal, query Prometheus:

   ```bash
   curl -fsS http://localhost:9090/-/ready
   curl -fsS 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool
   ```

   For Grafana, port-forward the Grafana service, log in using the chart-generated credentials and verify that Kubernetes dashboards display current data.

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
```

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
