# Platform Architecture

## Overview

The project builds a production-inspired AWS platform incrementally. Infrastructure is provisioned with Terraform, workloads run on Amazon EKS, application delivery is managed through GitOps and platform telemetry is collected through a unified observability stack.

## Logical Architecture

```text
Developer
    |
    v
GitHub Organization
    |
    +--> platform-bootstrap ----> Terraform state foundation
    +--> platform-modules ------> Reusable Terraform modules
    +--> platform-live ---------> Shared AWS infrastructure and EKS
    +--> helm-charts -----------> Application packaging
    +--> sample-api ------------> Reference workload and CI
    +--> platform-config -------> Argo CD desired state
    +--> docs ------------------> Architecture and labs

AWS
    |
    +--> IAM
    +--> Amazon S3
    +--> Amazon VPC
    +--> Amazon EKS
    +--> AWS Secrets Manager

Amazon EKS
    |
    +--> Argo CD
    +--> Prometheus and Grafana
    +--> Loki and Grafana Alloy
    +--> Tempo and OpenTelemetry Collector
    +--> Karpenter
    +--> External Secrets Operator
    +--> Argo Rollouts
    +--> Sample API
```

## Architectural Boundaries

- `platform-bootstrap` creates resources required before the main Terraform state can exist.
- `platform-modules` contains reusable, environment-independent Terraform modules.
- `platform-live` composes modules into the shared AWS infrastructure used by the lab environments.
- `platform-config` is the GitOps source of truth for Kubernetes platform and workload configuration.
- `helm-charts` contains custom charts owned by the project.
- `sample-api` contains application source code and Continuous Integration workflows.
- `docs` contains documentation only and does not provision infrastructure.

## Environment Model

The portfolio implementation uses one shared EKS cluster with dev, staging and production namespaces to control cost. This is an educational compromise. A production implementation would normally evaluate separate AWS accounts and separate clusters for stronger isolation.
