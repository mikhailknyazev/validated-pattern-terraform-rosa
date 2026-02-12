# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **GitHub Actions CI/CD Workflows**: Added automated Terraform and shell script validation and quality checks
  - `terraform-pr-checks.yml`: Runs on pull requests to validate Terraform code and shell scripts
  - `terraform-master-checks.yml`: Runs on pushes to main/master branches
  - **Terraform checks**: Formatting (`terraform fmt -check`), TFLint linting, validation for all modules and root config, init for all modules
  - **Shell script checks**: ShellCheck linting and shfmt formatting checks for all scripts in `scripts/` directory
  - TFLint configuration (`.tflint.hcl`) with AWS provider plugin and Terraform best practices
  - ShellCheck configuration (`.shellcheckrc`) for shell script linting rules
  - Workflows run in parallel for faster feedback
  - Note: Terraform plan is not included by default (requires AWS credentials and RHCS token)
  - Documentation updated in `docs/CI_CD.md` with workflow details and local testing instructions
- **Makefile Targets for Code Quality**: Reorganized Makefile with consistent `tf-` and `sh-` prefixes
  - **Terraform targets**: `tf-fmt`, `tf-fmt-check`, `tf-validate`, `tf-validate-modules`, `tf-validate-root`
  - **Shell script targets**: `sh-fmt`, `sh-fmt-check`, `sh-lint`, `sh-lint-fix`
  - **Combined targets**: `fmt` (runs `tf-fmt` and `sh-fmt`), `fmt-check` (runs `tf-fmt-check` and `sh-fmt-check`), `validate` (runs `tf-validate` and `sh-lint`), `lint` (runs `tf-fmt-check`, `sh-fmt-check`, and `sh-lint`), `lint-fix` (runs `tf-fmt` and `sh-fmt`), `test` (runs all checks)
  - All targets include helpful error messages with installation instructions
  - Clear separation between Terraform and shell script operations
- **Contributing Guide**: Added comprehensive `CONTRIBUTING.md` guide
  - Development setup instructions for macOS, Ubuntu/Debian, and RHEL/CentOS/Fedora
  - Installation instructions for all required tools (Terraform, AWS CLI, OpenShift CLI, ShellCheck, shfmt, TFLint)
  - Development workflow (fork, clone, branch, test, commit, PR)
  - Code quality guidelines and testing instructions
  - Code style guidelines for Terraform and shell scripts
  - Pull request checklist and process
- **macOS Installation Instructions**: Added macOS-specific installation instructions
  - Homebrew installation commands for all development tools
  - Updated `docs/CI_CD.md` with macOS instructions
  - Makefile targets detect missing tools and provide macOS installation hints

### Changed
- **BREAKING**: Renamed `enable_strict_egress` variable to `zero_egress` throughout the codebase
  - Root module: `terraform/01-variables.tf` - variable renamed from `enable_strict_egress` to `zero_egress`
  - Network-private module: variable renamed from `enable_strict_egress` to `zero_egress`
  - All `.tfvars` files updated to use `zero_egress` instead of `enable_strict_egress`
  - Scripts updated: `get-network-config.sh`, `Makefile.cluster`, tunnel scripts (`start.sh`, `stop.sh`, `status.sh`)
  - Documentation updated: `README.md`, `PLAN.md`, `clusters/README.md`, module READMEs
  - **Migration**: Update all `terraform.tfvars` files to replace `enable_strict_egress = true/false` with `zero_egress = true/false`
  - **Rationale**: Matches ROSA API property name (`zero_egress`) for consistency across all modules and eliminates mapping layer
- **IMPORTANT**: `zero_egress` is now independent of `network_type` - it's a cluster-level ROSA API property
  - `zero_egress` is passed directly to cluster and IAM modules (independent of network configuration)
  - Network infrastructure (NAT Gateway, security groups) is configured for zero egress when both `network_type="private"` AND `zero_egress=true`
  - This allows `zero_egress` to be set independently, though it typically requires `network_type="private"` for PrivateLink API endpoint

### Added
- **Termination Protection**: Added cluster termination protection feature
  - New variable `enable_termination_protection` (default: `false`) in cluster module
  - Creates `shell_script` resource that uses ROSA CLI to enable/disable delete protection
  - Prevents accidental cluster deletion via ROSA CLI
  - Note: Disabling protection requires manual action via OCM console (cannot be done via CLI)
  - Script: `scripts/cluster/termination-protection.sh`
  - Reference: `./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/13.termination-protection.tf`
- **ETCD KMS Key**: Added dedicated KMS key for etcd encryption
  - Creates `aws_kms_key.etcd` resource when `enable_storage = true` and `etcd_encryption = true`
  - KMS key persists through sleep operations (like EBS/EFS keys)
  - Cluster resource automatically uses etcd KMS key ARN when `etcd_encryption = true`
  - New outputs: `etcd_kms_key_id` and `etcd_kms_key_arn`
  - Reference: `./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/1.main.tf:5-12`
- **Cert Manager IAM Roles**: Added IAM role and policy for cert-manager to use AWS Private CA
  - New variable `enable_cert_manager_iam` (default: `false`) in cluster module
  - Creates IAM role for `cert-manager:cert-manager` service account
  - IAM policy grants AWS Private CA permissions (`acm-pca:DescribeCertificateAuthority`, `acm-pca:GetCertificate`, `acm-pca:IssueCertificate`)
  - Bootstrap script updated to use `CERT_MANAGER_ROLE_ARN` environment variable from Terraform output
  - New output `cert_manager_role_arn` exposes IAM role ARN
  - Reference: `./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/6.cert-manager.tf`
- **Secrets Manager IAM Integration**: Added IAM role and policy for ArgoCD Vault Plugin to access AWS Secrets Manager
  - New variable `enable_secrets_manager_iam` (default: `false`) in cluster module
  - New variable `additional_secrets` (optional list of secret names) for granting access to additional secrets
  - Creates IAM role for `openshift-gitops:vplugin` service account
  - IAM policy uses explicit secret ARN list for security (not wildcards)
  - Cluster credentials secret automatically included in policy
  - Additional secrets looked up by name via data sources to get exact ARNs
  - New output `secrets_manager_role_arn` exposes IAM role ARN
  - Reference: `./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/3.secrets.tf`
- **CloudWatch Logging for OpenShift Logging Operator**: Added IAM role and policy for OpenShift Logging Operator to send logs to CloudWatch
  - New variable `enable_cloudwatch_logging` (default: `false`) in cluster module
  - Creates IAM role for `openshift-logging:logging` service account (used by ClusterLogForwarder)
  - IAM policy grants CloudWatch Logs permissions (CreateLogGroup, CreateLogStream, PutLogEvents, etc.)
  - New output `cloudwatch_logging_role_arn` exposes IAM role ARN
  - Reference: `./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/4.logging.tf`

### Added
- **DNS Domain Registration**: Added DNS domain registration using `rhcs_dns_domain` resource with feature toggle:
  - New `enable_persistent_dns_domain` variable in cluster module (default: `false`) controls DNS domain registration
  - When enabled, creates `rhcs_dns_domain` resource in cluster module that persists between cluster creations (not gated by `persists_through_sleep`)
  - DNS domain resource is created and managed within the cluster module for better encapsulation
  - When disabled, ROSA uses default DNS domain
  - Infrastructure files pass the toggle to the cluster module
  - Reference implementation: `./reference/rosa-hcp-dedicated-vpc/terraform/1.main.tf:17-19`
- **CloudWatch Audit Log Forwarding**: Added CloudWatch audit log forwarding as a toggleable feature (enabled by default):
  - New `enable_audit_logging` variable (default: `true`) in cluster module
  - Creates IAM role and policy for CloudWatch audit log forwarding
  - IAM role uses OIDC federation for OpenShift logging service account (`system:serviceaccount:openshift-logging:cluster-logging`)
  - New output `cloudwatch_audit_logging_role_arn` provides the role ARN for cluster configuration
  - Configuration file: `modules/infrastructure/cluster/20-audit-logging.tf`
  - Reference implementation: `./reference/rosa-hcp-dedicated-vpc/terraform/4.logging.tf`
  - Note: Cluster configuration via OCM API or rosa CLI may be required depending on provider version
- **API Endpoint Security Group Access**: Added optional `api_endpoint_allowed_cidrs` variable to cluster module:
  - Allows specifying additional IPv4 CIDR blocks to access the ROSA HCP API endpoint
  - By default, the VPC endpoint security group only allows access from within the VPC
  - Useful for allowing access from VPN ranges, bastion hosts, or other VPCs
  - Automatically finds the ROSA-managed VPC endpoint security group by tag name
  - Creates ingress rules for each specified CIDR block (port 443/TCP)
  - Only creates resources when CIDRs are provided and `persists_through_sleep` is true
  - Reference implementation: `reference/rosa-hcp-dedicated-vpc/terraform/2.expose-api.tf`
- **Machine Pool Management**: Added support for additional custom machine pools beyond default pools:
  - New `additional_machine_pools` variable in cluster module for creating custom pools
  - Support for advanced features: taints, labels, kubelet configs, tuning configs, version pinning
  - Support for AWS features: capacity reservations, additional security groups, custom disk size
  - New outputs: `default_machine_pools`, `additional_machine_pools`, `all_machine_pools`
  - Validation to prevent name conflicts between default and additional pools
  - Validation for subnet IDs, instance types, and autoscaling configuration
  - Uses `for_each` pattern for stable resource addressing
  - Reference implementation: `./reference/rosa-hcp-dedicated-vpc/terraform/1.main.tf:212-233`

### Removed
- **BREAKING**: Removed `modules/infrastructure/network-egress-zero/` module
  - Egress-zero functionality has been consolidated into `network-private` module
  - Use `network-private` with `zero_egress = true` and `enable_nat_gateway = false` for zero-egress mode
  - Migration: Update module source from `network-egress-zero` to `network-private` and add `zero_egress = true`
  - Updated all documentation and references to reflect consolidation
  - Updated `modules/infrastructure/bastion/` and `modules/infrastructure/network-existing/` READMEs
- **BREAKING**: Removed `examples/private/` cluster example
  - Private cluster example removed (only public and egress-zero examples remain)
  - Private network module (`modules/infrastructure/network-private/`) retained for use with egress-zero clusters
  - Updated Makefile to remove all private cluster targets
  - Updated README.md to remove private cluster deployment instructions

### Changed
- **BREAKING**: Admin password management moved to AWS Secrets Manager:
  - **BREAKING**: Variable renamed: `admin_password` → `admin_password_override` (nullable, optional)
  - **BREAKING**: Removed `admin_password` output (password never output by Terraform)
  - Added `admin_password_secret_arn` output (ARN of AWS Secrets Manager secret)
  - If `admin_password_override` is not set, a random password is generated and stored in AWS Secrets Manager
  - Password stored in secret: `rosa-hcp-{cluster_name}-admin-password`
  - Makefile updated to retrieve password from AWS Secrets Manager using AWS CLI
  - **Migration required**: Update any references to `admin_password` variable or output
  - **Security improvement**: Password no longer stored in Terraform state or outputs

### Added
- **Sleep Protection Pattern**: Implemented `persists_through_sleep` pattern to prevent accidental resource destruction:
  - Global `persists_through_sleep` variable (default: `true`) controls all resources by default
  - Per-resource override variables: `persists_through_sleep_cluster`, `persists_through_sleep_iam`, `persists_through_sleep_network`
  - When `persists_through_sleep = true`, resources are active and managed by Terraform
  - To sleep cluster: Set `persists_through_sleep = false`, run `terraform apply` (resources are destroyed but essential metadata preserved)
  - OIDC configuration and provider are never gated (preserved for reuse across clusters)
  - Subnet tags in `network-existing` module are never gated (read-only, managed by ROSA)
  - All modules updated: cluster, IAM, network (public/private/egress-zero), bastion
  - All example clusters updated with `persists_through_sleep = true` by default
  - Module outputs updated to handle conditional resources (return null when slept)
  - Example cluster module calls updated to use `try()` for conditional dependencies
  - Comprehensive documentation added to README.md with usage examples and workflow
  - Resources tagged with `persists_through_sleep = "true"` tag to indicate they persist through sleep operations
  - Designed for enterprise environments with strict change control and permission constraints

### Changed
- **BREAKING**: Reorganized repository structure to separate infrastructure and configuration:
  - Modules reorganized: `modules/infrastructure/` (network, iam, cluster, bastion, identity-admin) and `modules/configuration/` (gitops)
  - Module organization is based on provider type: infrastructure modules use OCM/AWS providers, configuration modules use Kubernetes/Terraform providers
  - **BREAKING**: Moved `identity-admin` module from `modules/configuration/` to `modules/infrastructure/`:
    - Uses `rhcs` (OCM) provider, not Kubernetes/Terraform providers
    - Belongs in infrastructure based on provider type
    - Updated all example cluster references to new path
    - Updated documentation (README.md, PLAN.md, module READMEs)
  - Cluster examples reorganized: Each cluster now has `infrastructure/` and `configuration/` subdirectories with separate state files
  - Configuration uses `terraform_remote_state` data source to read infrastructure outputs
  - Updated Makefile with infrastructure/configuration specific targets
  - Module source paths updated: `modules/infrastructure/...` and `modules/configuration/...`
  - **Migration required**: Existing clusters need to be migrated to new structure (see README.md for migration guide)

### Added
- Created gitops module (`modules/configuration/gitops/`) for deploying OpenShift GitOps operator:
  - Deploys OpenShift GitOps operator (ArgoCD) via OperatorHub using oc CLI
  - Uses terraform_data with local-exec provisioner to avoid Kubernetes provider interpolation issues
  - Configurable operator channel, source, and install plan approval
  - Waits for operator installation to complete and verifies deployment
  - Supports custom namespace configuration
  - Handles cluster authentication via oc CLI
  - Comprehensive error handling and timeout configuration
  - Full documentation with usage examples and troubleshooting guide

### ⚠️ Work in Progress - Egress-Zero Cluster
- **Egress-zero cluster configuration is currently non-functional**
- Worker nodes are not starting successfully (0/1 replicas)
- Security group egress rules have been added (HTTPS and DNS to VPC CIDR) but issues persist
- Investigation ongoing: checking console logs, security groups, VPC endpoints, and IAM permissions
- **Do not use egress-zero cluster example for production until this issue is resolved**

### Changed
- Clarified bastion host is for development/demo use only:
  - Added prominent warnings in bastion module README and main README
  - Updated variable descriptions in example clusters to warn against production use
  - Added comments in example cluster configurations explaining production alternatives
  - Documented that production should use AWS Transit Gateway, Direct Connect, or VPN
  - Updated bastion subnet recommendation document with decision rationale

### Added
- Added identity provider support to cluster module:
  - HTPasswd identity provider for admin user (optional, via `admin_password`)
  - Group membership to add admin user to cluster-admins group
  - Configurable admin username and group
- Added `admin_password` variable to all example clusters
- Removed duplicate `05-identity.tf` files from example clusters (now handled by cluster module)

### Removed
- Removed developer user functionality from cluster module (additional users should be configured separately after cluster creation)
- Added `token` variable to all example clusters for RHCS provider authentication
- Updated provider configuration to match rh-mobb reference implementation

### Added
- Created identity-admin module (`modules/identity-admin/`) for admin user creation:
  - Separated admin user creation from cluster module for independent lifecycle management
  - Allows admin user to be created initially and removed when external IDP is configured
  - HTPasswd identity provider with cluster-admin group membership
  - Can be easily added or removed from cluster configuration
  - Updated all example clusters to use the new module
- Created bastion module (`modules/bastion/`) for secure access to private clusters:
  - SSM Session Manager support (no public IP, no SSH keys required)
  - Optional public IP mode for testing
  - Pre-installed OpenShift CLI (`oc`) and Kubernetes CLI (`kubectl`)
  - IAM-based authentication via SSM
  - Supports SSH tunnels for Terraform automation
  - Supports sshuttle for VPN-like access
  - Integrated into private and egress-zero cluster examples (optional, enabled by default)
- Added Makefile targets for bastion and tunnel management:
  - `make tunnel-start.<cluster>`: Start SSH tunnel to cluster API via bastion (for Terraform/automation)
  - `make tunnel-stop.<cluster>`: Stop SSH tunnel
  - `make tunnel-status.<cluster>`: Check if tunnel is running
  - `make bastion-connect.<cluster>`: Connect to bastion via SSM Session Manager
  - Tunnels forward localhost:6443 to cluster API, enabling Terraform to access private clusters
  - Automatic tunnel cleanup on stop

### Changed
- Switched tunnel implementation from SSH port forwarding to sshuttle VPN tunnel:
  - `make tunnel-start.<cluster>` now uses `sshuttle` instead of SSH port forwarding
  - sshuttle creates a VPN-like tunnel that routes ALL VPC traffic through the bastion
  - This enables full cluster access including OAuth flows required for `oc login`
  - Requires `sshuttle` to be installed (provides installation instructions if missing)
  - Requires sudo privileges - displays warning message before prompting for local sudo password
  - Tunnel detection in `show-endpoints` and `login` targets updated to check for sshuttle process
  - Direct API URL is used (sshuttle routes traffic transparently)
  - Added `vpc_cidr_block` and `region` outputs to all example clusters for tunnel management
  - Updated help text and documentation to reflect sshuttle usage
- Refactored admin user creation into separate `identity-admin` module:
  - Removed `admin_password`, `admin_username`, and `admin_group` variables from cluster module
  - Removed `rhcs_identity_provider.admin` and `rhcs_group_membership.admin` resources from cluster module
  - Updated all example clusters to use `modules/identity-admin/` instead
  - Enables independent lifecycle management (create initially, remove when external IDP configured)
- Refactored Makefile to use pattern rules, reducing duplication:
  - New pattern syntax: `make <action>.<cluster>` (e.g., `make apply.public`, `make login.private`)
  - Supports all actions: `init`, `plan`, `apply`, `destroy`, `login`, `show-endpoints`, `show-credentials`
  - Supports all clusters: `public`, `private`, `egress-zero`
  - Legacy syntax still supported for backwards compatibility (e.g., `make apply-public`)
  - Uses Make functions to map cluster names to directories automatically
  - Updated help text to show both pattern and legacy syntax

### Added
- Added Makefile targets for cluster access and credential management:
  - `make login-public`, `make login-private`, `make login-egress-zero`: Login to clusters using `oc login` with terraform outputs
  - `make show-endpoints-public`, `make show-endpoints-private`, `make show-endpoints-egress-zero`: Display API and console URLs from terraform outputs
  - `make show-credentials-public`, `make show-credentials-private`, `make show-credentials-egress-zero`: Display admin credentials and endpoints (show-credentials automatically runs show-endpoints)
  - All targets support getting admin password from `TF_VAR_admin_password` environment variable or `terraform.tfvars` file
  - Login targets verify `oc` CLI is installed and handle errors gracefully
- Added STS VPC endpoint to `network-public` module:
  - STS endpoint is required for IAM role assumption (IRSA), OIDC provider operations
  - Benefits: cost optimization (avoids NAT Gateway charges), lower latency, improved security
  - Worker nodes in private subnets benefit from STS endpoint even in public networks
  - Updated outputs to include STS endpoint ID
  - Updated README to document all VPC endpoints created by the module

### Fixed
- Added HTTPS and DNS egress rules to worker node security group in egress-zero module:
  - Worker nodes need HTTPS (443) egress to VPC CIDR to reach VPC endpoints (ECR, STS, CloudWatch)
  - Worker nodes need DNS (53) egress to VPC CIDR for DNS resolution
  - Previous configuration had no egress rules, preventing nodes from pulling container images from ECR
  - **Note**: This fix is part of ongoing investigation - worker nodes still not starting successfully
- Fixed cluster replicas calculation for multi-AZ clusters:
  - Changed cluster-level `replicas` to always be set (not null when autoscaling enabled)
  - Cluster-level replicas must be set for validation, even with autoscaling (autoscaling is handled at machine pool level)
  - Added precondition to validate replicas is a multiple of number of subnets for multi-AZ clusters
  - For multi-AZ with 3 subnets, replicas must be 3, 6, 9, etc. (multiple of 3)
  - Fixes "Invalid number of compute nodes: 2" error for multi-AZ clusters
- Fixed network ACL rule number in egress-zero module:
  - Changed deny rule from `rule_no = 32767` to `rule_no = 32766` (maximum allowed is 32766)
  - AWS Network ACL rule numbers must be in range 1-32766
- Removed unsupported `disable_workload_monitoring` attribute from cluster resource:
  - This attribute is not supported by the ROSA HCP provider
  - Removed from cluster resource, variables, and README
  - Variable was already commented out in egress-zero example
- Fixed egress-zero cluster configuration:
  - Added `zero_egress` variable to cluster module to enable zero egress mode
  - Sets `zero_egress = "true"` property in cluster properties when enabled
  - Added `zero_egress` variable to IAM module to attach ECR read-only policy to worker role
  - When `zero_egress = true`, IAM module attaches `AmazonEC2ContainerRegistryReadOnly` policy to worker role (required for egress-zero clusters to pull container images via VPC endpoints)
  - Added `depends_on = [module.account_roles]` to policy attachment to ensure worker role exists before attaching policy
  - Updated egress-zero cluster example to set `zero_egress = true` in both IAM and cluster modules
  - This ensures proper egress-zero cluster configuration with required IAM permissions
- Fixed SSM agent installation in bastion module user_data script:
  - Replaced `wget` with `curl` for downloading SSM agent RPM (wget not installed by default on RHEL 9 AMI)
  - `curl` is available by default on RHEL, ensuring SSM agent installs successfully
  - Resolves `TargetNotConnected` error when connecting via SSM Session Manager
  - SSM agent now registers correctly with AWS Systems Manager
- Fixed destroy-time dependency ordering to ensure cluster is destroyed before IAM roles/OIDC:
  - Updated Makefile `destroy.%` targets to use two-phase destroy: `terraform destroy -target=module.cluster` first, then full destroy
  - This explicitly destroys the cluster BEFORE IAM roles/OIDC, preventing permission loss during cluster destruction
  - Terraform's implicit dependency graph wasn't sufficient - explicit targeting ensures proper order
  - Added documentation comments in example clusters explaining the destroy process
  - Manual destroy instructions: `terraform destroy -target=module.cluster` then `terraform destroy`
- Documented destroy-time dependency ordering to ensure cluster is destroyed before IAM roles/OIDC:
  - Cluster resource depends on IAM module outputs (installer_role_arn, support_role_arn, worker_role_arn, oidc_config_id, oidc_endpoint_url)
  - Terraform destroys resources in reverse dependency order, so cluster (dependent) is destroyed BEFORE IAM resources (dependencies)
  - This ensures Terraform maintains permissions to destroy the cluster
  - Added documentation comments in cluster and IAM modules explaining the dependency ordering
  - Updated Makefile destroy targets with warnings about proper destroy order
- Refactored machine pool resource to match reference implementation:
  - Changed from `for_each` to `count` for data source and resource (matching reference pattern)
  - Removed complex null-checking logic - reference trusts data source will have values
  - Simplified subnet_id, auto_repair, and aws_node_pool handling to directly use data source values
  - This ensures the magic import pattern works correctly as designed by the provider
  - ROSA HCP creates "workers" (plural) for single-AZ, "workers-0", "workers-1", "workers-2" for multi-AZ
- Added lifecycle block to ignore tag changes on subnet resources:
  - ROSA automatically adds tags like `kubernetes.io/cluster/{cluster_id}` to subnets
  - Added `lifecycle { ignore_changes = [tags] }` to all subnet resources in network modules
  - Prevents Terraform from removing service-managed tags on subsequent runs
  - Applied to network modules: `network-public`, `network-private` (egress-zero functionality consolidated into network-private)
- Fixed null reference errors in machine pool resource:
  - Added null checks for `subnet_id`, `auto_repair`, and `aws_node_pool` in `rhcs_hcp_machine_pool` resource
  - When these values are null (e.g., during initial cluster creation), use appropriate defaults:
    - `subnet_id`: Derive from machine pool name (e.g., "workers-1" maps to `var.subnet_ids[1]`, "workers" maps to `var.subnet_ids[0]`)
    - `auto_repair`: Default to `true` (standard ROSA default)
    - `instance_type`: Fallback to `var.default_instance_type`
    - `ec2_metadata_http_tokens`: Default to `"required"` (matching cluster-level setting)
  - Updated precondition validation to handle null `aws_node_pool` gracefully
- Fixed double-dash issue in IAM role names:
  - Removed trailing dashes from `account_role_prefix` and `operator_role_prefix` in all example clusters
  - The upstream modules (`account-iam-resources` and `operator-roles`) add their own dashes, so passing a trailing dash caused double dashes (e.g., `pczarkow--HCP-ROSA-Installer-Role`)
  - Now matches reference implementation: prefixes should be `var.cluster_name` without trailing dash
  - This fixes the cluster waiting state error: "Operator Role(s) not found"

### Changed
- Automatic version detection in cluster module: if `openshift_version` is not provided, the module now uses `rhcs_versions` data source to automatically determine the latest installable OpenShift version
- Added `rhcs_versions` data source to query available OpenShift versions from the ROSA API
- Updated IAM module to use upstream terraform-redhat/rosa-hcp/rhcs modules:
  - `account-iam-resources` for account roles
  - `oidc-config-and-provider` for OIDC configuration
  - `operator-roles` for operator roles
- Added `oidc_endpoint_url` variable to cluster module (required for STS configuration)

### Changed
- Updated all network modules to automatically calculate subnet CIDR size (matching reference pattern):
  - Made `subnet_cidr_size` variable optional (defaults to `null`)
  - Subnet CIDR size is now automatically calculated based on VPC CIDR size and number of subnets needed
  - Calculation ensures sufficient space: `subnet_cidr_size = vpc_cidr_size + ceil(log2(total_subnets))`
  - Examples: /16 VPC with 6 subnets (multi-AZ public) → /19, /16 VPC with 3 subnets (multi-AZ private) → /18
  - Can still be overridden by explicitly setting `subnet_cidr_size` if needed
  - Removed `subnet_cidr_size` from all example cluster configurations
- Updated all network modules to automatically calculate availability zones (matching reference implementation):
  - Removed `availability_zones` variable from all network modules
  - Added `data.aws_availability_zones.available` data source to automatically query available AZs
  - Network modules now use first 3 AZs for multi-AZ, first 1 AZ for single-AZ
  - Added `private_subnet_azs` and `public_subnet_azs` outputs to network modules
  - Cluster module now receives `availability_zones` from network module output instead of requiring it as input
  - Removed `availability_zones` variable from all example cluster configurations
  - Updated example clusters to use `module.network.private_subnet_azs` for cluster availability zones
- Added machine type validation using `rhcs_machine_types` data source in cluster module:
  - Instance types are now validated against available ROSA machine types for the specified region
  - Clear error messages guide users to available machine types if validation fails
  - Validation applies to both `default_instance_type` and `machine_pools[].instance_type`
- Added `name_prefix` variable to all network modules to ensure unique AWS resource names across clusters:
  - All resource names (VPC, subnets, NAT gateways, VPC endpoints, security groups, etc.) now use `${var.name_prefix}-` prefix
  - Example clusters updated to pass `name_prefix = var.cluster_name`
  - Updated all module README files to document the new variable
- Updated all network modules to automatically calculate subnet CIDRs (matching reference implementation):
  - Removed `private_subnet_cidrs` and `public_subnet_cidrs` variables
  - Added `subnet_cidr_size` variable (default: 20 for /20 subnets)
  - Subnet CIDRs are now calculated automatically from VPC CIDR and subnet size
  - Private subnets are calculated first, then public subnets (for network-public module)
- Removed regional NAT Gateway support from network-public module - now uses standard (zonal) NAT Gateways only (one per AZ)
- Removed `nat_gateway_type` variable from network-public module
- Updated network-public module to always create public subnets (required for NAT Gateways)
- Updated all example clusters to use automatic subnet CIDR calculation
- Updated Makefile to save plan files (`terraform.tfplan`) for all plan targets
- Updated apply targets to use saved plan files instead of running plan again
- Added `*.tfplan` and `terraform.tfplan` to `.gitignore`
- Fixed deprecation warning: Replaced `data.aws_region.current.name` with `data.aws_region.current.id` in all network modules (public, private, egress-zero)
- Updated cluster module to align with rh-mobb reference implementation:
  - Added `machine_cidr` attribute (required, uses `vpc_cidr` variable)
  - Added `aws_billing_account_id` variable (optional, defaults to current account)
  - Added `replicas`, `compute_machine_type`, `ec2_metadata_http_tokens`, `properties`, and lifecycle settings to cluster resource
  - Machine pool `aws_node_pool` now preserves instance type from data source (allows override via `machine_pools` variable)
  - Updated example clusters to pass `vpc_cidr` and `multi_az` to cluster module
- Updated cluster module to follow rh-mobb patterns:
  - Version detection: Uses `rhcs_versions` data source with search filter and order
  - Machine pools: Reads default pools created by cluster, then manages them (following rh-mobb pattern)
  - Replicas logic: HCP uses 1 per subnet for multi-AZ, 2 for single-AZ
  - Added `compute_machine_type`, `replicas`, `ec2_metadata_http_tokens`, `properties`, and lifecycle settings to cluster resource
- Updated cluster module STS configuration to match upstream pattern:
  - `role_arn` now uses installer_role_arn (not operator role ARN)
  - Added `oidc_endpoint_url` to STS block
  - Removed `operator_role_arns` variable (operator roles created via prefix)

### Fixed
- Updated Makefile so plan targets depend on init targets, ensuring backend is initialized before planning
- Fixed `rhcs_cluster_rosa_hcp` resource structure to match Terraform Registry API:
  - Changed `sts` from block to attribute (object) with required fields:
    - Added `role_arn` (operator role ARN) and `instance_iam_roles` (required)
    - Moved `oidc_config_id` into `sts` attribute
  - Changed `openshift_version` to `version`
  - Changed `aws_node_pool` and `autoscaling` from blocks to attributes (objects)
  - Added `enabled` attribute to `autoscaling` configuration
  - Removed unsupported attributes (`fips`, `disable_workload_monitoring`, `tags` on machine pools)
  - Removed invalid outputs (`kubeconfig`, `cluster_admin_password`) that don't exist on the resource
- Corrected module source paths in all cluster examples (changed from `../../../../modules` to `../../../modules`)
- Removed invalid `multi_az` attribute from cluster module calls (multi_az is only used in machine pools, not cluster-level)

### Changed
- Default Terraform backend to local state storage in all cluster examples
- S3 backend configuration commented out for easy reference when needed
- Updated machine pool replica settings in all cluster examples:
  - Single AZ: min_replicas = 2, max_replicas = 4 (double min)
  - Multi-AZ: min_replicas = 3, max_replicas = 6 (double min)
- Renamed module Terraform files to use numbered prefixes following best practices:
  - `versions.tf` → `00-versions.tf` (provider configuration, always first)
  - `variables.tf` → `01-variables.tf` (variable definitions)
  - `main.tf` → `10-main.tf` (main resources)
  - `outputs.tf` → `90-outputs.tf` (outputs, always last)

### Added
- Makefile with targets for cluster management (init, plan, apply, destroy)
- Code quality targets (fmt, validate)
- Utility targets (clean, init-all, plan-all)
- Initial repository structure
- Network modules (public, private, egress-zero)
  - Public module with Regional NAT Gateway (default) and zonal option
  - Private module with VPC endpoints only
  - Egress-zero module with strict security controls and VPC Flow Logs
- IAM module for ROSA HCP
  - OIDC configuration and provider
  - Account roles using terraform-redhat/rosa-hcp/rhcs module
  - Operator roles (Ingress, Control Plane, CSI, Image Registry, Network, Node Pool)
- Cluster module (thin wrapper)
  - Organizational defaults (private=true, etcd_encryption=false)
  - Machine pool support with defaults
  - Pass-through for all provider variables
- Example cluster configurations
  - Public cluster (development example)
  - Private cluster (development example)
  - Egress-zero cluster (production-ready with hardening)
- Project documentation
  - README.md with overview and quick start
  - PLAN.md with detailed architecture and implementation plan
  - CHANGELOG.md following Keep a Changelog format
  - Module READMEs for all modules
- Development guidelines (.cursorrules)
  - Terraform best practices
  - PLAN.md compliance requirements
  - Documentation and versioning standards

### Changed

### Deprecated

### Removed

### Fixed

### Security
