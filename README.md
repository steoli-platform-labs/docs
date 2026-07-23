# AWS Platform Engineering Documentation

This repository contains the documentation for a production-inspired AWS Platform Engineering project.

The platform is built incrementally through a series of hands-on labs, with each lab introducing new capabilities while following modern Infrastructure as Code, Kubernetes and GitOps practices.

---

# Platform Vision

The objective of this project is to design, build and operate a cloud-native platform similar to those used by modern Platform Engineering teams.

The platform emphasizes:

- Infrastructure as Code
- Kubernetes
- GitOps
- Automation
- Observability
- Security
- Operational Excellence

Every component is introduced progressively through practical labs that build upon one another.

---

# Architecture

The platform evolves through five implementation phases.

## Phase 1 – Platform Foundation

Build the AWS foundation required for the platform.

Core technologies:

- Terraform
- Amazon S3
- DynamoDB
- Amazon VPC
- IAM

---

## Phase 2 – Kubernetes Platform

Deploy and automate the Kubernetes platform.

Core technologies:

- Amazon EKS
- Helm
- GitHub Actions
- ArgoCD

---

## Phase 3 – Platform Observability & Operations

Introduce platform observability and operational capabilities.

Core technologies:

- Prometheus
- Grafana
- Loki
- Tempo
- Karpenter

---

## Phase 4 – Platform Security

Secure the Kubernetes platform and workloads.

Core technologies:

- External Secrets Operator
- IAM Roles for Service Accounts (IRSA)
- Network Policies

---

## Phase 5 – Platform Operations

Extend the platform with advanced operational capabilities.

Core technologies:

- Multi-Environment Platform
- Progressive Delivery
- High Availability & Resilience
- Chaos Engineering

---

# Documentation Structure

```text
docs/
├── README.md
├── architecture/
├── concepts/
├── labs/
├── CONTRIBUTING.md
├── SECURITY.md
└── capstone.md
```

---

# Repositories

| Repository | Purpose |
|------------|---------|
| platform-live | Terraform environments and platform deployment |
| platform-modules | Reusable Terraform modules |
| platform-bootstrap | Initial AWS bootstrap resources |
| platform-config | Shared platform configuration |
| helm-charts | Custom Helm charts |
| sample-api | Sample application used throughout the labs |
| docs | Project documentation |

---

# Design Principles

The project follows a number of guiding principles.

## Documentation First

Architecture and design are documented before implementation.

## Infrastructure as Code

Infrastructure is provisioned and managed using Terraform.

## GitOps

Kubernetes deployments are managed declaratively through Git using ArgoCD.

## Automation

Manual operations are minimized through automation and Continuous Integration.

## Cloud-Native

Platform components follow Kubernetes and CNCF best practices whenever possible.

## Reusability

Infrastructure, Helm charts and workflows are designed to be modular and reusable.

---

# Learning Roadmap

The complete implementation roadmap is available in:

```text
docs/labs/README.md
```

Each lab builds directly on the previous one, resulting in a complete production-inspired AWS Platform Engineering platform.

---

# Future Improvements

Future enhancements may include:

- Multi-cluster deployments
- Service Mesh
- Policy as Code
- FinOps dashboards
- Platform APIs
- Developer Self-Service
- Internal Developer Platform capabilities

---

# Practical Implementation

Use the documentation in this order:

1. Review the platform overview in this README.
2. Read the architecture documents in [`architecture/`](./architecture/).
3. Use the shared [`concepts`](./concepts/README.md) reference when a lab introduces an unfamiliar platform, AWS, Kubernetes or observability term.
4. Complete the labs sequentially from [`labs/README.md`](./labs/README.md).
5. Use each lab's validation and troubleshooting sections as the source of truth for hands-on checks.
6. Review [`SECURITY.md`](./SECURITY.md) before introducing credentials, secrets or access changes.

The labs are the implementation path. Architecture documents provide context, while detailed commands live in the labs to keep the repository lightweight.
