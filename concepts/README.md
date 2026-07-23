# Concepts Reference

This reference explains the main platform, AWS, Kubernetes and observability concepts used throughout the labs.

The labs remain the hands-on implementation path. Use this page when a lab introduces a term and you want a deeper explanation of what was deployed, why it exists and how it fits into the platform.

## How to Use This Reference

- Read the relevant concept when it first appears in a lab.
- Return to the lab for the exact implementation commands and validation checks.
- Treat this page as conceptual context, not a replacement for AWS, Kubernetes or tool-specific documentation.

## Platform and Repository Concepts

- **Platform Engineering:** The practice of building reusable infrastructure, automation and workflows that make it easier for teams to deploy and operate applications safely.
- **Internal Developer Platform:** A curated set of infrastructure, deployment, observability and security capabilities exposed to application teams through standard workflows.
- **Multi-repository architecture:** A project layout where each repository has a focused responsibility. In these labs, infrastructure modules, live environments, GitOps configuration, Helm charts, application code and documentation are separate repositories.
- **Source of truth:** The place that defines the intended state of a system. Terraform state and GitOps desired state are both source-of-truth mechanisms in different layers of the platform.

## Terraform and State

- **Terraform:** An Infrastructure as Code tool that manages cloud resources from declarative configuration files.
- **Terraform module:** A reusable Terraform package. Modules define infrastructure patterns that can be consumed by one or more live environments.
- **Live environment:** A deployable Terraform root module for a specific environment, such as Development. It composes reusable modules and provides environment-specific values.
- **Terraform state:** Terraform's record of which real resources correspond to which configuration blocks.
- **Remote backend:** A remote storage location for Terraform state. These labs use S3 so state is not kept only on one workstation.
- **State locking:** A protection mechanism that prevents multiple Terraform runs from modifying the same state at the same time.
- **Plan and apply:** `terraform plan` previews changes; `terraform apply` makes the approved changes.

## AWS Networking

- **VPC:** A Virtual Private Cloud is an isolated network boundary inside AWS. The EKS cluster, private workloads and platform services run inside this network.
- **CIDR block:** An IP address range assigned to a network or subnet, such as `10.100.0.0/24`.
- **Subnet:** A smaller IP range inside a VPC. Subnets are placed in specific Availability Zones.
- **Public subnet:** A subnet that can route directly to the internet through an Internet Gateway. These labs reserve public subnets for infrastructure such as load balancers and NAT gateways.
- **Private subnet:** A subnet without direct inbound internet routing. Worker nodes and application workloads run here.
- **Internet Gateway:** The AWS resource that lets public subnets route traffic to and from the internet.
- **NAT Gateway:** Lets resources in private subnets initiate outbound internet connections without being directly reachable from the internet.
- **Route table:** Defines where network traffic goes based on destination CIDR ranges.
- **Availability Zone:** A physically separate data center zone inside an AWS Region. Spreading resources across zones improves resilience.
- **Security group:** A stateful virtual firewall attached to AWS network interfaces and resources.

## Amazon EKS and Kubernetes

- **Kubernetes:** A container orchestration platform that runs and manages containerized workloads.
- **Amazon EKS:** AWS-managed Kubernetes. AWS operates the Kubernetes control plane while worker nodes run in your AWS account.
- **Control plane:** The Kubernetes API and controllers that store desired state and decide what should run.
- **Worker node:** A compute instance that runs application and platform pods.
- **Cluster:** A Kubernetes control plane plus worker nodes.
- **kubeconfig:** A local configuration file that tells `kubectl` how to connect to a cluster.
- **kubectl:** The Kubernetes command-line tool.
- **Namespace:** A logical partition inside a cluster used to group related resources.
- **Pod:** The smallest deployable Kubernetes workload unit. A pod usually runs one application container, but can include sidecars.
- **Deployment:** A Kubernetes controller for stateless workloads. It manages ReplicaSets and keeps the requested number of pods running.
- **StatefulSet:** A Kubernetes controller for stateful workloads that need stable names or persistent identity, such as Prometheus or databases.
- **DaemonSet:** Runs one pod on each selected node. Node-level agents such as log collectors and node exporters commonly use DaemonSets.
- **Job:** Runs a task to completion. Hook jobs and one-time setup tasks often use Jobs.
- **Service:** Provides a stable network name and virtual IP for reaching pods.
- **Endpoint:** The actual backing pod IPs behind a Service. If a Service has no endpoints, port-forwarding to that Service usually fails.
- **Ingress:** A Kubernetes API object that routes external HTTP or HTTPS traffic to Services when an ingress controller is installed.
- **ConfigMap:** Stores non-secret configuration consumed by pods.
- **Secret:** Stores sensitive values such as passwords or registry credentials. Do not commit secret values to Git.
- **CRD:** A Custom Resource Definition teaches Kubernetes a new resource type, such as `Prometheus`, `ServiceMonitor`, `ExternalSecret` or `Rollout`.
- **Operator:** A controller that watches custom resources and turns them into real running infrastructure or workloads. Prometheus Operator and External Secrets Operator are examples.

## Helm

- **Helm:** A package manager and templating tool for Kubernetes manifests.
- **Chart:** A Helm package containing templates, default values and metadata.
- **Values:** Configuration passed into a chart to customize rendered manifests.
- **Template rendering:** The process where Helm combines chart templates and values into Kubernetes YAML.
- **Release:** A deployed instance of a Helm chart. In GitOps workflows, Argo CD usually manages the rendered release state.
- **Linting:** Static validation that checks chart structure and templates before deployment.

## CI, Containers and Registries

- **GitHub Actions:** GitHub's CI automation system. These labs use it for validation, tests, image builds and package publishing.
- **CI:** Continuous Integration. It validates changes before they become part of the main branch.
- **Container image:** A packaged application and runtime filesystem that Kubernetes can run.
- **Image tag:** A label pointing at an image version. Commit-SHA tags are immutable and traceable; `latest` is convenient but mutable.
- **Digest:** A content-addressed image identifier such as `sha256:...`. Digests prove exactly which image content was pulled.
- **GHCR:** GitHub Container Registry, used here to publish the `sample-api` image.
- **Image pull secret:** A Kubernetes secret that lets nodes authenticate to a private registry such as GHCR.

## GitOps and Argo CD

- **GitOps:** A deployment model where Git stores desired state and a controller reconciles the cluster to match Git.
- **Desired state:** The resources and configuration declared in Git.
- **Actual state:** The resources currently running in the cluster.
- **Reconciliation:** The controller loop that compares desired and actual state, then applies changes.
- **Drift:** A difference between desired state and actual state.
- **Self-heal:** Automatic correction of drift back to the Git-defined state.
- **Pruning:** Deleting cluster resources that are no longer defined in Git.
- **Argo CD:** A GitOps controller and UI for Kubernetes.
- **Argo CD Application:** A custom resource that tells Argo CD where to read desired state from and where to deploy it.
- **App-of-apps:** A pattern where one root Application creates child Applications for individual components.
- **Sync status:** Whether live resources match Git. Common values are `Synced` and `OutOfSync`.
- **Health status:** Whether resources are operational. Common values are `Healthy`, `Progressing`, `Degraded` and `Unknown`.

## Observability

- **Observability:** The ability to understand system behavior from signals emitted by workloads and infrastructure.
- **Metrics:** Numeric time-series data, such as CPU usage, memory usage and request counts.
- **Logs:** Timestamped records emitted by applications and components.
- **Traces:** End-to-end request paths across services. A trace is made of spans.
- **Span:** A timed unit of work within a distributed trace.
- **Prometheus:** A metrics database and query engine that scrapes targets and stores time-series data.
- **Prometheus Operator:** An operator that manages Prometheus, Alertmanager and related monitoring resources using CRDs.
- **ServiceMonitor:** A Prometheus Operator custom resource that tells Prometheus how to scrape a Kubernetes Service.
- **PrometheusRule:** A custom resource containing alerting or recording rules.
- **Alertmanager:** Handles alerts generated by Prometheus.
- **Grafana:** A visualization and dashboard system used to inspect metrics, logs and traces.
- **Loki:** A log aggregation system designed to work well with Grafana.
- **Alloy:** Grafana's collector agent for gathering and forwarding telemetry signals.
- **Tempo:** A distributed tracing backend.
- **OpenTelemetry:** A vendor-neutral standard and tooling ecosystem for telemetry collection.

## Platform Operations and Security

- **Karpenter:** A Kubernetes node autoscaler that provisions and removes nodes based on pending workload needs.
- **External Secrets Operator:** A Kubernetes operator that syncs secrets from external secret stores into Kubernetes Secrets.
- **IRSA:** IAM Roles for Service Accounts. It lets Kubernetes service accounts assume AWS IAM roles without static AWS keys in pods.
- **NetworkPolicy:** A Kubernetes resource that restricts pod-to-pod and pod-to-network traffic when a compatible network policy engine is installed.
- **Progressive delivery:** Deployment strategies such as canary and blue-green releases that reduce release risk.
- **Argo Rollouts:** A Kubernetes controller for progressive delivery patterns.
- **High availability:** Designing systems to keep running through failures.
- **Resilience:** The ability to recover from failures and continue meeting service expectations.
- **Chaos engineering:** Controlled failure injection used to validate resilience assumptions.
