# Lab 03 - AWS Networking

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Foundation |
| **Lab** | 03 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 45–75 minutes |
| **Primary Tools** | Terraform, AWS CLI |

## Introduction

This lab provisions the foundational AWS networking layer for the platform.

This lab adds AWS networking resources that can incur cost while they exist, especially the NAT Gateway and its data processing. These resources are removed in the final cleanup lab.

A production-inspired Virtual Private Cloud (VPC) is created with public and private subnets distributed across multiple Availability Zones. Internet connectivity, outbound access and routing are configured to support future workloads running on Amazon EKS.

The networking resources created in this lab form the foundation for every subsequent lab in the project.

Concepts introduced in this lab include VPCs, CIDR blocks, public subnets, private subnets, route tables, Internet Gateways, NAT Gateways and Availability Zones. See the [Concepts Reference](../concepts/README.md) for concise definitions.

## Outcome

In this lab you create the first reusable infrastructure module and the first environment-specific live Terraform stack.

The completed implementation provisions:

- one dedicated VPC using primary CIDR `10.100.0.0/24`
- optional secondary VPC CIDR `100.64.0.0/18` for EKS-ready private subnets
- two public subnets across two Availability Zones
- two platform private subnets, plus optional EKS private subnets, across two Availability Zones
- one Internet Gateway
- one cost-optimized NAT Gateway by default
- public and private route tables
- subnet discovery tags required by future EKS load balancers
- remote Terraform state in the S3 backend created during Lab 02

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 02 completed
- Remote Terraform backend operational
- Terraform, AWS CLI and Git installed
- AWS CLI authenticated to the intended account
- `platform-live` and `platform-modules` checked out as sibling directories

## Architecture

```text
                               Internet
                                   │
                         Internet Gateway
                                   │
                  ┌─────────────────────────────┐
                  │            VPC              │
                  │ Primary: 10.100.0.0/24      │
                  │ EKS:     100.64.0.0/18      │
                  └─────────────────────────────┘
                       │                   │
          ┌────────────┘                   └────────────┐
          │                                             │

  Public Subnet (AZ-a)                        Public Subnet (AZ-b)
      10.100.0.0/27                             10.100.0.32/27
          │                                             │
          │                                     Future Load Balancer
          │
     NAT Gateway
          │
──────────┼────────────────────────────────────────────────────────
          │
  Private Subnet (AZ-a)                    Private Subnet (AZ-b)
      10.100.0.64/27                         10.100.0.96/27
      100.64.0.0/19                          100.64.32.0/19
          │                                             │
          └────────────── Future Amazon EKS ────────────┘
```

## AWS Resources

| Resource | Purpose |
|----------|---------|
| Amazon VPC | Private network |
| Public Subnets | Internet-facing resources |
| Private Subnets | Internal workloads |
| Internet Gateway | Internet access |
| NAT Gateway | Outbound internet access |
| Elastic IP | Static public IP for NAT Gateway |
| Route Tables | Traffic routing |

## Design Decisions

The networking architecture follows AWS Well-Architected design principles.

- **Dedicated VPC:** The default AWS VPC is not used. A dedicated VPC provides better isolation, easier management and greater flexibility for future platform expansion.

- **CIDR planning:** The primary VPC CIDR is intentionally small: `10.100.0.0/24`. Treat the primary CIDR as part of the agreed IP plan because it may need to route to customer networks, shared services, VPNs, Transit Gateway or other VPCs later. Amazon EKS can consume many IP addresses when using the AWS VPC CNI. To avoid exhausting the primary range, the lab can optionally allocate EKS-ready private subnets from a secondary VPC CIDR: `100.64.0.0/18`. `100.64.0.0/10` is the RFC 6598 shared address space, also known as CGNAT space. AWS allows it for VPC CIDRs, and it is commonly used for Kubernetes pod-heavy ranges, but it is not magic private space. The selected secondary CIDR is platform-internal and must still be planned so it does not overlap with current or future connected networks.

- **Public subnets:** Public subnets are reserved for infrastructure components that require direct internet connectivity, such as Application Load Balancers and NAT Gateways.

- **Private subnets:** Application workloads will never receive public IP addresses. Future workloads include Amazon EKS worker nodes, platform services, GitOps components, the monitoring stack and the logging stack.

- **Multi-AZ deployment:** Resources are distributed across two Availability Zones to improve availability and resilience.

- **Cost-optimized NAT Gateway:** The shared lab infrastructure uses one NAT Gateway by default to limit recurring lab cost. This creates an Availability Zone dependency for private-subnet outbound connectivity. The reusable module supports one NAT Gateway per Availability Zone when a higher-availability production configuration is required.

- **EKS-ready subnet discovery:** Public and private subnets are tagged for future AWS Load Balancer Controller discovery. Public subnets use `kubernetes.io/role/elb = 1`, while private subnets use `kubernetes.io/role/internal-elb = 1`.

- **Reusable module and live configuration:** Reusable VPC logic is stored in `platform-modules`, while environment-specific values and remote state configuration are stored in `platform-live`.

## Network Layout

| Resource | CIDR |
|----------|------|
| VPC primary CIDR | 10.100.0.0/24 |
| Optional VPC secondary CIDR for EKS | 100.64.0.0/18 |
| Public Subnet A | 10.100.0.0/27 |
| Public Subnet B | 10.100.0.32/27 |
| Private Platform Subnet A | 10.100.0.64/27 |
| Private Platform Subnet B | 10.100.0.96/27 |
| Optional Private EKS Subnet A | 100.64.0.0/19 |
| Optional Private EKS Subnet B | 100.64.32.0/19 |

## Implementation Overview

This lab consists of the following high-level tasks.

1. Create the VPC
2. Create public subnets
3. Create private subnets
4. Attach an Internet Gateway
5. Allocate an Elastic IP
6. Create a NAT Gateway
7. Configure Route Tables
8. Associate Route Tables with subnets
9. Verify network connectivity

The expected repository layout is:

```text
platform-labs/
├── docs/
├── platform-bootstrap/
├── platform-live/
└── platform-modules/
```

`platform-live` and `platform-modules` must be sibling directories because the shared infrastructure stack initially consumes the module through a local relative path. A future release workflow can replace the relative path with an immutable Git tag.

## Files to Review

This lab uses `platform-modules` for reusable Terraform logic and `platform-live` for the deployable shared AWS infrastructure.

| File | Why it matters |
|------|----------------|
| `platform-modules/modules/core/vpc.tf` | Owns reusable VPC, subnet and routing logic |
| `platform-modules/modules/core/variables.tf` | Defines reusable module inputs |
| `platform-modules/modules/core/outputs.tf` | Exposes subnet and VPC IDs to live environments |
| `platform-live/environments/shared/network.tf` | Composes reusable modules for the shared lab network |
| `platform-live/environments/shared/backend.hcl.example` | Documents the remote backend configuration shape |
| `platform-live/environments/shared/terraform.tfvars.example` | Provides safe example values for the shared lab network |

## Step-by-Step Implementation

Follow the steps below to configure the remote backend, review the network design, initialize Terraform, apply the plan and validate the deployed AWS resources.

1. Configure the remote backend. Retrieve the state bucket created in Lab 02:

   ```bash
   cd ../platform-bootstrap
   terraform output
   ```

   Move to the shared infrastructure root module:

   ```bash
   cd ../platform-live/environments/shared
   cp backend.hcl.example backend.hcl
   cp terraform.tfvars.example terraform.tfvars
   export TF_VAR_workspace_path="$WORKSPACE"
   ```

   Edit `backend.hcl`:

   ```hcl
   bucket = "your-lab02-state-bucket"
   region = "<your-aws-region>"
   ```

   `backend.hcl` is intentionally ignored by Git because it contains account-specific configuration.

   Use the backend bucket name from the Lab 02 `terraform output`; do not use the state object key as the bucket. The key for this lab is already defined by the checked-in backend example.

   The bootstrap stack created the shared state bucket. This live stack now uses that bucket to store its own state file, so Terraform can remember the VPC and subnet resources it creates in this lab.

   `TF_VAR_workspace_path` records the local checkout path as a `Workspace` tag on supported AWS resources.

2. Review the network design. The default network uses:

   | Resource | CIDR |
   |---|---|
   | VPC primary CIDR | `10.100.0.0/24` |
   | Optional VPC secondary CIDR for EKS | `100.64.0.0/18` |
   | Public subnet A | `10.100.0.0/27` |
   | Public subnet B | `10.100.0.32/27` |
   | Private platform subnet A | `10.100.0.64/27` |
   | Private platform subnet B | `10.100.0.96/27` |
   | Optional private EKS subnet A | `100.64.0.0/19` |
   | Optional private EKS subnet B | `100.64.32.0/19` |

   The primary CIDR should be agreed and documented in the IP plan. The secondary CIDR is optional and is used only when `secondary_cidr_blocks` and `eks_private_subnet_cidrs` are set. If used, it must still be non-overlapping and planned. `100.64.0.0/18` is carved from RFC 6598 shared address space.

   The network stack exports `platform_private_subnet_ids` and `eks_private_subnet_ids` separately. Later EKS labs use `eks_private_subnet_ids` when the optional EKS subnets exist, otherwise they fall back to `platform_private_subnet_ids`.

   Private subnet names also identify their purpose: `<project-name>-dev-platform-private-<az>` for primary-CIDR private subnets and `<project-name>-dev-eks-private-<az>` for EKS private subnets.

   The stack dynamically selects the first two standard Availability Zones returned in the configured Region. This avoids hard-coding zone letters whose physical mapping differs between AWS accounts.

   The lab uses one NAT Gateway by default to keep recurring cost lower. This provides multi-AZ subnet placement but does not make outbound connectivity fully Availability-Zone independent. Setting `single_nat_gateway = false` creates one NAT Gateway per Availability Zone for a more production-oriented design at higher cost.

3. Initialize the live stack:

   ```bash
   terraform init -backend-config=backend.hcl
   ```

   Terraform should initialize the S3 backend and download the AWS provider and the pinned VPC module dependency.

   Expected output ends with `Terraform has been successfully initialized!`. Stop on backend bucket, key, profile or Region errors because a failed init means Terraform is not using the intended remote state.

   The checked-in `.terraform.lock.hcl` records the selected provider versions and checksums after successful initialization.

4. Format and validate Terraform:

   ```bash
   printf '\n===== Terraform format =====\n'
   terraform fmt
   printf '\n===== Terraform validate =====\n'
   terraform validate
   ```

   Expected result:

   ```text
   Success! The configuration is valid.
   ```

5. Review the plan:

   ```bash
   terraform plan
   ```

   Review all resources before applying. Confirm that:

   - the VPC primary CIDR is `10.100.0.0/24`
   - the optional secondary EKS CIDR is `100.64.0.0/18` when `secondary_cidr_blocks` is set
   - four subnets are planned for the primary-CIDR layout, or six subnets when optional EKS subnets are enabled
   - two Availability Zones are used
   - private subnets do not map public IPs on launch
   - a NAT Gateway and Elastic IP are planned
   - EKS load-balancer subnet tags are present

   The exact resource count can change between module releases. Validate the intended architecture rather than relying only on a fixed count.

   Proceed only if the plan is additive or updates expected networking resources. Stop on destroy actions, wrong CIDRs, wrong Region, missing private routing, missing subnet tags or resources planned in an unexpected account.

6. Apply the network:

   ```bash
   terraform apply
   ```

   NAT Gateway creation can take several minutes.

   After completion:

   ```bash
   terraform output
   ```

   Expected output includes a non-empty VPC ID and subnet ID lists. Empty outputs usually mean the apply failed or you are in the wrong workspace/root module.

7. Validate Terraform state and outputs:

   ```bash
   printf '\n===== Terraform state resources =====\n'
   terraform state list
   printf '\n===== VPC ID =====\n'
   terraform output -raw vpc_id
   printf '\n===== Public subnet IDs =====\n'
   terraform output -json public_subnet_ids
   printf '\n===== Private subnet IDs =====\n'
   terraform output -json private_subnet_ids
   printf '\n===== Platform private subnet IDs =====\n'
   terraform output -json platform_private_subnet_ids
   printf '\n===== EKS private subnet IDs =====\n'
   terraform output -json eks_private_subnet_ids
   ```

8. Verify the remote state object:

   ```bash
   export AWS_PAGER=""

   aws s3api head-object   --bucket "$(awk -F'"' '/bucket/ {print $2}' backend.hcl)"   --key "platform-live/shared/terraform.tfstate"
   ```

   A successful `head-object` prints JSON metadata for the remote state object. `NoSuchKey`, `NotFound` or `AccessDenied` means the bucket, key, Region or AWS profile does not match the backend configuration.

   Think of the S3 bucket as the storage container and the backend key as the file path inside that container. This command checks that Terraform wrote the live environment state file to the expected path.

9. Inspect the AWS resource configuration:

   ```bash
   export AWS_PAGER=""
   VPC_ID="$(terraform output -raw vpc_id)"
   printf '\n===== VPC configuration =====\n'
   aws ec2 describe-vpcs   --vpc-ids "${VPC_ID}"   --query 'Vpcs[0].{VpcId:VpcId,Cidr:CidrBlock,DnsSupport:EnableDnsSupport,DnsHostnames:EnableDnsHostnames}'
   printf '\n===== Subnet configuration =====\n'
   aws ec2 describe-subnets   --filters "Name=vpc-id,Values=${VPC_ID}"   --query 'Subnets[].{SubnetId:SubnetId,AZ:AvailabilityZone,Cidr:CidrBlock,PublicIpOnLaunch:MapPublicIpOnLaunch}'   --output table
   printf '\n===== NAT gateways =====\n'
   aws ec2 describe-nat-gateways   --filter "Name=vpc-id,Values=${VPC_ID}"   --query 'NatGateways[].{Id:NatGatewayId,State:State,Subnet:SubnetId}'   --output table
   printf '\n===== Route tables =====\n'
   aws ec2 describe-route-tables   --filters "Name=vpc-id,Values=${VPC_ID}"   --query 'RouteTables[].{RouteTableId:RouteTableId,Routes:Routes[].{Destination:DestinationCidrBlock,Gateway:GatewayId,NatGateway:NatGatewayId}}'
   ```

   Expected output: VPC DNS support and hostnames are enabled, NAT Gateway state is `available`, public routes point to an internet gateway and private routes point to a NAT Gateway.

10. Check EKS subnet discovery tags:

   ```bash
   export AWS_PAGER=""

   printf '\n===== Public subnet load-balancer tags =====\n'
   aws ec2 describe-tags   --filters     "Name=resource-id,Values=$(terraform output -json public_subnet_ids | jq -r 'join(",")')"     "Name=key,Values=kubernetes.io/role/elb"

   printf '\n===== Private subnet load-balancer tags =====\n'
   aws ec2 describe-tags   --filters     "Name=resource-id,Values=$(terraform output -json private_subnet_ids | jq -r 'join(",")')"     "Name=key,Values=kubernetes.io/role/internal-elb"
   ```

    The tag commands use `jq`. You may also inspect the subnet tags in the AWS Console.

    Expected output includes public subnet tags for external load balancers and private subnet tags for internal load balancers. Missing tags can prevent Kubernetes load balancer discovery in later labs.

11. Confirm Terraform state and local inputs stay out of source control.

    This lab creates real AWS networking resources and writes live state to S3. The source repositories should contain reusable Terraform code and examples, not your local backend configuration, local variables or generated state files.

    In `platform-modules`:

    ```bash
    cd "$WORKSPACE/platform-modules"
    printf '\n===== platform-modules ignored local files check =====\n'
    git ls-files backend.hcl terraform.tfvars terraform.tfstate terraform.tfstate.backup
    ```

    In `platform-live`:

    ```bash
    cd "$WORKSPACE/platform-live"
    printf '\n===== platform-live ignored local files check =====\n'
    git ls-files backend.hcl terraform.tfvars terraform.tfstate terraform.tfstate.backup
    ```

    The `git ls-files` commands should print no local backend, variable or state files. Empty output is the expected result because these files are local execution details, not platform source code.

## Expected Results

Terraform provisions the shared lab VPC, public subnets, private platform subnets, optional EKS private subnets, Internet Gateway, NAT Gateway, route tables and subnet discovery tags. State is stored in the S3 backend created in Lab 02.

## Validation

- Public subnets carry `kubernetes.io/role/elb = 1`.
- Private subnets carry `kubernetes.io/role/internal-elb = 1`.
- Routing is validated through Terraform state, route-table inspection and later by the EKS worker nodes deployed in Lab 04.
- A public subnet routes `0.0.0.0/0` to the Internet Gateway.
- A private subnet routes `0.0.0.0/0` to the NAT Gateway.
- No EC2 instance is launched solely for connectivity testing because it would add temporary infrastructure and cost.

## Troubleshooting

- **Backend initialization fails:** Confirm the bucket name, Region and AWS profile in `backend.hcl`:

   ```bash
   export AWS_PAGER=""
   aws s3api head-bucket --bucket "your-state-bucket"
   ```

   Then retry:

   ```bash
   terraform init -reconfigure -backend-config=backend.hcl
   ```

- **Fewer than two Availability Zones are available:** Use an AWS Region with at least two standard Availability Zones available to your account.

- **NAT Gateway remains pending:** Wait several minutes and inspect it:

   ```bash
   export AWS_PAGER=""
   VPC_ID=$(terraform output -raw vpc_id)

   aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${VPC_ID}"
   ```

   The expected state is `available`. If private workloads cannot reach AWS APIs or the internet, inspect route tables and subnet associations before changing resources:

   ```bash
   export AWS_PAGER=""
   VPC_ID=$(terraform output -raw vpc_id)

   aws ec2 describe-route-tables \
     --filters "Name=vpc-id,Values=${VPC_ID}" \
     --query 'RouteTables[].{RouteTable:RouteTableId,Associations:Associations[].SubnetId,Routes:Routes}'
   ```

   Expected default routes are `0.0.0.0/0` to the Internet Gateway for public subnets and `0.0.0.0/0` to a NAT Gateway for private subnets.

   Run `terraform plan` and investigate unexpected drift before applying any remediation.

- **Module path cannot be found:** Verify that `platform-live` and `platform-modules` are sibling directories. The source path is:

   ```text
   ../../../platform-modules/modules/core
   ```

## Final Repository State

At completion:

- Terraform state is stored remotely and locked in S3.
- The shared lab VPC is deployed across two Availability Zones.
- Public and private subnets are ready for Amazon EKS.
- Network code is separated into a reusable module and a live environment stack.
- No temporary connectivity-test resources remain.

## Best Practices

This lab follows AWS networking best practices.

- Never use the default VPC for production workloads.
- Deploy resources across multiple Availability Zones.
- Keep workloads in private subnets.
- Expose only required infrastructure to the internet.
- Manage all networking through Infrastructure as Code.

## Cleanup

No cleanup is required.

The networking infrastructure created during this lab will be used throughout the remainder of the project.

## References

- [Amazon EKS VPC and subnet requirements](https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html)
- [Amazon EKS subnet best practices](https://docs.aws.amazon.com/eks/latest/best-practices/subnets.html)
- [Terraform AWS VPC module](https://github.com/terraform-aws-modules/terraform-aws-vpc)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)

## Next Steps

Continue with [Lab 04 - Amazon EKS](./lab04-amazon-eks.md).
