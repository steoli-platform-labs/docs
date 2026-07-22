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

## Outcome

Implement and validate Loki and Alloy in the complete platform reference implementation.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 08 completed
- Prometheus and Grafana operational
- AWS CLI, Terraform, kubectl, Helm and repository URLs configured

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

### GitOps Deployment

All logging components are deployed through ArgoCD.

No manual Helm installations are performed.

### Loki

Grafana Loki is selected as the centralized logging platform because it integrates natively with Grafana and is optimized for Kubernetes environments.

### Grafana Alloy

Grafana Alloy is used as the log collection agent.

Alloy replaces Promtail and provides a unified telemetry collector capable of collecting logs, metrics and traces.

### Unified Observability

Grafana provides a single interface for metrics and logs.

Distributed tracing will be integrated in the next lab.

### Label-Based Indexing

Loki indexes labels rather than full log contents, reducing storage requirements and improving scalability.

### Platform-First Deployment

Logging is enabled for both platform services and application workloads.

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

Primary implementation: `platform-config/clusters/dev/loki.yaml and alloy.yaml`.

## Files to Review

Review the Loki and log collection desired-state files and update any environment-specific values before validation.

## Step-by-Step Implementation

1. Review `platform-config/clusters/dev/loki.yaml` and `platform-config/clusters/dev/alloy.yaml`.
2. Confirm both Applications target the expected namespace and chart repositories.
3. Commit and push any required `platform-config` changes.
4. Let Argo CD reconcile Loki and Alloy from Git:

   ```bash
   cd "$WORKSPACE"
   kubectl -n argocd get application loki alloy -o wide
   kubectl -n argocd annotate application loki argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd annotate application alloy argocd.argoproj.io/refresh=hard --overwrite
   kubectl -n argocd get application loki alloy -o wide
   ```

5. Validate Loki readiness and confirm Alloy is forwarding Kubernetes logs:

   ```bash
   kubectl -n argocd get application loki alloy -o wide
   kubectl -n monitoring get pods -l app.kubernetes.io/name=loki
   kubectl -n monitoring get pods -l app.kubernetes.io/name=alloy
   kubectl -n monitoring logs -l app.kubernetes.io/name=alloy --since=10m --tail=200
   kubectl -n monitoring port-forward svc/loki 3100:3100
   ```

   In another terminal:

   ```bash
   curl -fsS http://localhost:3100/ready
   curl -G -fsS http://localhost:3100/loki/api/v1/query_range \
     --data-urlencode 'query={namespace="sample-api-dev"}' \
     --data-urlencode "start=$(date -u -v-10M +%s)000000000" \
     --data-urlencode "end=$(date -u +%s)000000000"
   ```

   Generate a known log line:

   ```bash
   kubectl -n sample-api-dev logs deploy/sample-api --tail=5
   ```

## Expected Results

The `loki` and `alloy` Argo CD Applications reconcile successfully and log data begins flowing into Loki.

## Validation

Pass criteria:

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

## Commit and Push

Use a focused conventional commit such as `feat: complete lab 09`.

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
