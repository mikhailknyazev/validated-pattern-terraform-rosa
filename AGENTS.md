# Terraform Best Practices - ROSA HCP Infrastructure

This project follows Terraform best practices based on Red Hat MOBB Rules.
Reference: https://github.com/rh-mobb/mobb-rules/blob/main/content/languages/terraform/_index.md

## Project Plan and Architecture

### PLAN.md Compliance

**CRITICAL**: Always reference and follow `PLAN.md` for this project.

**MANDATORY Rules**:
1. **Before making changes**: Review `PLAN.md` to understand the intended architecture and design decisions
2. **During implementation**: Ensure all code aligns with the specifications in `PLAN.md`
3. **If deviating**:
   - **STOP and QUESTION**: Why are we deviating from the plan?
   - **Document the deviation**: Explain the reason in code comments or commit messages
   - **Update PLAN.md**: Keep the plan synchronized with actual implementation
   - **Get approval**: For significant deviations, ensure stakeholders are aware

4. **When updating PLAN.md**:
   - Update relevant sections when architecture changes
   - Document new decisions in the Architecture Decisions section
   - Keep examples and code snippets current
   - Update the Implementation Checklist as work progresses

**Best Practice**: `PLAN.md` is the source of truth. Code should reflect the plan, and the plan should reflect reality.

## Problem Solving and Debugging

### Validation-First Approach

**CRITICAL**: Before making any changes to fix errors or bugs, **ALWAYS validate inputs, assumptions, and current state first**.

**Validation-First Workflow**:
1. **Validate inputs** - Compare what we're passing/using vs what's expected/required
   - Check configuration files, values.yaml, variables, etc.
   - Compare actual commands/API calls with expected format
   - Verify all required parameters are present and correct
2. **Test assumptions** - Don't assume, verify
   - Use dry-run modes (`terraform plan`, `helm template`, `kubectl --dry-run`)
   - Test commands in isolation before integrating
   - Verify tool behavior with minimal examples
3. **Check current state** - Understand what exists before changing
   - Review existing code/configuration
   - Check logs, outputs, or state
   - Understand dependencies and relationships
4. **Identify root cause** - Don't add workarounds until root cause is confirmed
   - Trace the problem to its source
   - Verify the issue is what you think it is
   - Rule out configuration errors before assuming tool bugs
5. **Propose minimal fix** - Fix the root cause, not symptoms
   - Make targeted, minimal changes
   - Avoid adding complex workarounds
   - Fix configuration/input issues before adding logic

**Example Validation Process**:
```
## Step 1: Validate Inputs
- Compare values.yaml with our Helm command
- Check: Are all required values set? Are formats correct?
- Test: Run `helm template` to see what gets rendered

## Step 2: Test Assumptions
- Assumption: "Helm hooks aren't running"
- Test: Check if hooks exist in manifest, verify hook execution
- Verify: Are hooks actually failing, or are values wrong?

## Step 3: Check Current State
- Review: What resources exist? What's in the cluster?
- Compare: Expected vs actual state
- Identify: What's missing or incorrect?

## Step 4: Root Cause Analysis
- Root cause: "Values not set correctly" (not "hooks broken")
- Fix: Correct the values (not add hook extraction workaround)

## Step 5: Minimal Fix
- Change: Update Helm command to set correct values
- Avoid: Adding complex hook extraction logic
```

### Discussion Before Implementation

**MANDATORY**: When encountering errors, bugs, or situations with multiple solution approaches, **ALWAYS validate first, then discuss the issue and potential fixes before implementing**.

**When to Validate and Discuss First**:
1. **Any error messages** - Validate inputs, analyze error, understand root cause, discuss solutions
2. **Bugs or unexpected behavior** - Validate current state, understand why it's happening, explore fix options
3. **Multiple solution approaches** - Validate each approach, present options with pros/cons, get direction
4. **Architectural decisions** - Changes that affect module structure or patterns
5. **Breaking changes** - Any change that affects existing functionality
6. **Complex fixes** - Solutions that require changes across multiple files/modules
7. **Configuration issues** - When tools/commands aren't working as expected, validate configuration first

**Discussion Process**:
1. **Validate inputs and current state**: Check what we're passing vs what's expected
2. **Analyze the problem**: Understand what's happening and why
3. **Identify root cause**: Don't just fix symptoms, understand the underlying issue
4. **Test assumptions**: Verify assumptions before proposing fixes
5. **Present options**: List 2-3 potential solutions with:
   - Pros and cons of each approach
   - Impact on existing code
   - Trade-offs and considerations
   - Validation steps taken
6. **Get direction**: Wait for user input on preferred approach
7. **Implement**: Once direction is given, implement the chosen solution with minimal changes

**Example Discussion Format**:
```
## Validation Results
- Checked: values.yaml vs Helm command
- Found: Missing gitRepoUrl overrides for applications
- Tested: helm template shows incorrect values

## Problem Analysis
[Describe the error/issue]

## Root Cause
[Explain why this is happening - based on validation]

## Potential Solutions

### Option 1: [Approach Name]
- Pros: ...
- Cons: ...
- Impact: ...
- Validation: [How this was tested/verified]

### Option 2: [Approach Name]
- Pros: ...
- Cons: ...
- Impact: ...
- Validation: [How this was tested/verified]

## Recommendation
[Which option do you prefer and why?]
```

**Exception**: Simple, obvious fixes (typos, syntax errors, missing imports) can be fixed immediately without discussion, but still validate the fix works.

### Terraform-Specific Debugging Techniques

**CRITICAL**: When debugging Terraform issues, especially errors during `terraform apply` or unexpected resource behavior, follow this systematic approach:

#### 1. Inspect the Plan File First

**MANDATORY**: Before making code changes, **ALWAYS inspect the plan file** to see what Terraform is actually planning to do.

**Plan File Location**:
- Plan files are typically saved to `clusters/<cluster-name>/terraform.tfplan`
- Check the plan script (`scripts/cluster/plan-infrastructure.sh`) to confirm the exact location
- Plan files are binary, use `terraform show` to inspect them

**Inspection Commands**:
```bash
# View the entire plan
terraform show clusters/<cluster-name>/terraform.tfplan

# Search for specific resources or variables
terraform show -no-color clusters/<cluster-name>/terraform.tfplan | grep -E "multi_az|workers|rhcs_hcp_machine_pool"

# View specific resource details
terraform show -no-color clusters/<cluster-name>/terraform.tfplan | grep -A 20 "rhcs_hcp_machine_pool.default"

# Check variable values in the plan
terraform show -no-color clusters/<cluster-name>/terraform.tfplan | grep -E "^  # .*\.(multi_az|availability_zones)"
```

**Key Things to Check in Plan**:
- Variable values: Are they what you expect?
- Resource attributes: Are they being set correctly?
- Resource count: Are the right number of resources being created?
- Conditional logic: Are conditionals evaluating as expected?

#### 2. Trace Variable Values Through Module Chain

**MANDATORY**: When debugging module behavior, trace variables from root → child modules.

**Debugging Workflow**:
1. **Check root module inputs** (`terraform/10-main.tf`):
   - What variables are being passed to child modules?
   - Are there conditional assignments that might override expected values?
   - Check `.tfvars` files for variable overrides

2. **Check child module variables** (`modules/infrastructure/cluster/01-variables.tf`):
   - What are the variable definitions?
   - What are the default values?
   - Are variables nullable or required?

3. **Check local computations** (`modules/infrastructure/cluster/10-main.tf`):
   - How are variables being transformed in `locals` blocks?
   - Are conditionals evaluating correctly?
   - Are there multiple conditionals that might conflict?

4. **Check resource definitions**:
   - How are locals/variables being used in resources?
   - Are `count` or `for_each` expressions correct?

**Example Trace**:
```bash
# 1. Check root module variable assignment
grep -A 10 "module \"cluster\"" terraform/10-main.tf

# 2. Check what's passed to the module
grep -B 5 -A 15 "machine_pools\|multi_az\|availability_zones" terraform/10-main.tf

# 3. Check child module variable definitions
grep -A 10 "variable \"machine_pools\"" modules/infrastructure/cluster/01-variables.tf

# 4. Check how variables are used in locals
grep -B 5 -A 10 "hcp_machine_pools\|is_multi_az" modules/infrastructure/cluster/10-main.tf

# 5. Check resource usage
grep -B 5 -A 15 "rhcs_hcp_machine_pool" modules/infrastructure/cluster/10-main.tf
```

#### 3. Check for Conditional Overrides in Parent Modules

**CRITICAL**: Parent modules may have conditional logic that overrides child module defaults.

**Common Patterns to Check**:
- Conditional variable assignments: `machine_pools = var.network_type == "public" ? [...] : []`
- Conditional attribute overrides: `instance_type = var.network_type == "public" ? var.instance_type : null`
- Environment-specific defaults that might conflict with child module logic

**Example Issue**:
```hcl
# Root module (terraform/10-main.tf)
module "cluster" {
  machine_pools = var.network_type == "public" ? [
    { name = "workers", ... }  # This overrides child module's multi-AZ logic!
  ] : []
  multi_az = var.multi_az  # true
}

# Child module (modules/infrastructure/cluster/10-main.tf)
locals {
  hcp_machine_pools = local.is_multi_az ?
    ["workers-0", "workers-1", "workers-2"] :  # Never reached!
    var.machine_pools  # Uses "workers" from parent instead
}
```

**Solution**: Check parent module conditionals first, then ensure child module logic prioritizes correctly.

#### 4. Use Terraform Console for Expression Testing

**Best Practice**: Test complex expressions before implementing them.

```bash
# Start Terraform console
cd terraform/
terraform console

# Test expressions
> var.multi_az ? 3 : 1
> length(var.machine_pools) > 0 ? var.machine_pools[0].name : "workers"
> [for idx in range(3) : "workers-${idx}"]
```

#### 5. Verify Variable Precedence

**MANDATORY**: Understand Terraform variable precedence when debugging variable values.

**Variable Precedence** (highest to lowest):
1. Command-line flags (`-var` and `-var-file`)
2. `.tfvars` files (in order: `terraform.tfvars`, `*.auto.tfvars`)
3. Environment variables (`TF_VAR_*`)
4. Variable defaults in `variable` blocks

**Key Points**:
- `.tfvars` files take precedence over environment variables
- Saved plan files bake in variable values - regenerate plans after code changes
- Check for conflicting variable sources (e.g., both `.tfvars` and `TF_VAR_*`)

**Debugging Variable Values**:
```bash
# Check what variables are set
terraform console
> var.multi_az
> var.network_type

# Check for environment variables
env | grep TF_VAR_

# Check .tfvars files
cat clusters/<cluster-name>/terraform.tfvars | grep multi_az
```

#### 6. Regenerate Plans After Code Changes

**CRITICAL**: Plan files are snapshots of variable values and resource definitions at plan time.

**When to Regenerate**:
- After changing variable defaults
- After modifying conditional logic
- After updating module inputs/outputs
- After changing resource definitions

**Regeneration Process**:
```bash
# Delete old plan
rm clusters/<cluster-name>/terraform.tfplan

# Generate new plan
make cluster.<name>.plan

# Verify new plan has correct values
terraform show -no-color clusters/<cluster-name>/terraform.tfplan | grep -E "multi_az|workers"
```

#### 7. Check State File Location

**MANDATORY**: Verify where Terraform state is stored.

**State File Location**:
- Check `terraform/00-providers.tf` for backend configuration
- Check `scripts/cluster/init-infrastructure.sh` for backend config path
- State files are typically in `clusters/<cluster-name>/infrastructure.tfstate`

**Verification**:
```bash
# Check backend configuration
grep -A 10 "backend" terraform/00-providers.tf

# Check init script for state path
grep "path\|key" scripts/cluster/init-infrastructure.sh

# List resources in state
cd terraform/
terraform state list
```

#### 8. Systematic Debugging Checklist

**MANDATORY**: Follow this checklist when debugging Terraform issues:

1. **Read the error message carefully**:
   - What resource is failing?
   - What's the specific error?
   - Is it a validation error or runtime error?

2. **Inspect the plan file**:
   - [ ] Run `terraform show` on the plan file
   - [ ] Check variable values in the plan
   - [ ] Verify resource attributes match expectations
   - [ ] Check resource counts (`count` or `for_each`)

3. **Trace variable flow**:
   - [ ] Check `.tfvars` file values
   - [ ] Check root module variable assignments
   - [ ] Check child module variable definitions
   - [ ] Check local computations
   - [ ] Verify conditional logic evaluation

4. **Check for overrides**:
   - [ ] Are parent modules overriding child module defaults?
   - [ ] Are conditionals in parent modules conflicting with child logic?
   - [ ] Are explicit variable assignments overriding computed values?

5. **Verify state**:
   - [ ] Is state file in expected location?
   - [ ] Are there existing resources that might conflict?
   - [ ] Is state file locked or corrupted?

6. **Test assumptions**:
   - [ ] Use `terraform console` to test expressions
   - [ ] Regenerate plan after code changes
   - [ ] Compare expected vs actual values

7. **Document findings**:
   - [ ] Document root cause
   - [ ] Document the fix
   - [ ] Update `.cursorrules` if debugging process needs improvement

#### 9. Common Terraform Debugging Pitfalls

**Avoid These Mistakes**:

1. **Assuming variable values without checking**:
   - ❌ "multi_az must be false because..."
   - ✅ Check plan file: `terraform show plan.tfplan | grep multi_az`

2. **Not checking parent module overrides**:
   - ❌ "The child module logic looks correct..."
   - ✅ Check root module: `grep -A 10 "module \"cluster\"" terraform/10-main.tf`

3. **Using stale plan files**:
   - ❌ Applying old plan after code changes
   - ✅ Regenerate plan: `make cluster.<name>.plan`

4. **Not understanding conditional precedence**:
   - ❌ "The first condition should match..."
   - ✅ Trace through all conditionals, check evaluation order

5. **Ignoring variable precedence**:
   - ❌ "Environment variables override .tfvars"
   - ✅ Remember: `.tfvars` > environment variables

6. **Not checking resource counts**:
   - ❌ "It should create 3 resources..."
   - ✅ Check plan: `terraform show plan.tfplan | grep "will be created" | wc -l`

#### 10. Example Debugging Session

**Scenario**: Multi-AZ cluster creating single "workers" pool instead of "workers-0", "workers-1", "workers-2"

**Debugging Steps**:
```bash
# Step 1: Check plan file
terraform show -no-color clusters/egress-zero/terraform.tfplan | grep -E "multi_az|workers|rhcs_hcp_machine_pool"

# Step 2: Check .tfvars
cat clusters/egress-zero/terraform.tfvars | grep multi_az

# Step 3: Check root module
grep -B 5 -A 15 "machine_pools\|multi_az" terraform/10-main.tf

# Step 4: Check child module variables
grep -A 10 "variable \"machine_pools\"" modules/infrastructure/cluster/01-variables.tf

# Step 5: Check child module logic
grep -B 5 -A 10 "hcp_machine_pools\|is_multi_az" modules/infrastructure/cluster/10-main.tf

# Step 6: Found issue - root module sets machine_pools=["workers"] for public networks
# Step 7: Fix - prioritize multi_az check in child module before checking machine_pools input
# Step 8: Regenerate plan
rm clusters/egress-zero/terraform.tfplan
make cluster.egress-zero.plan

# Step 9: Verify fix
terraform show -no-color clusters/egress-zero/terraform.tfplan | grep -E "workers"
```

## Documentation Requirements

### Code Documentation

**MANDATORY**: All code must be well-documented:

1. **Module README.md**: Every module MUST have a README.md with:
   - Purpose and use case
   - Input variables (with descriptions)
   - Outputs (with descriptions)
   - Usage examples
   - Dependencies
   - Requirements

2. **Inline Comments**: Document:
   - Complex logic or non-obvious decisions
   - Workarounds for provider limitations
   - Why certain patterns are used
   - Resource lifecycle decisions
   - Deviations from PLAN.md (with explanation)

3. **Variable and Output Descriptions**: Every variable and output MUST have a clear description

### Project Documentation

**REQUIRED Files**:
- `README.md` - Project overview, quick start, architecture summary
- `PLAN.md` - Detailed implementation plan and architecture decisions
- `CHANGELOG.md` - Version history and changes (see Changelog section below)
- `ARCHITECTURE.md` - High-level architecture diagrams and decisions (if separate from PLAN.md)
- `.cursorrules` - Development guidelines (this file)

**Module Documentation**:
- Each module in `modules/` MUST have a `README.md`
- Document all inputs, outputs, and usage examples
- Include architecture diagrams if helpful

## Versioning and Changelog

### Semantic Versioning

**MANDATORY**: Use Semantic Versioning (SemVer) for modules and releases:
- Format: `MAJOR.MINOR.PATCH` (e.g., `1.2.3`)
- **MAJOR**: Breaking changes (incompatible API changes)
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

**Versioning Strategy**:
- Modules: Version in `versions.tf` or module metadata
- Releases: Tag Git commits with version numbers
- Document version compatibility in README files

### CHANGELOG.md

**MANDATORY**: Maintain a `CHANGELOG.md` file following [Keep a Changelog](https://keepachangelog.com/) format:

**Format**:
```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New features

### Changed
- Changes to existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Security fixes

## [1.0.0] - 2024-01-15

### Added
- Initial release
- Network modules (public, private, egress-zero)
- IAM module
- Cluster module
- Example cluster configurations
```

**Changelog Rules**:
1. **Every change MUST be documented** in CHANGELOG.md
2. **Group changes by type**: Added, Changed, Deprecated, Removed, Fixed, Security
3. **Link to issues/PRs**: Reference related issues or pull requests
4. **Date format**: Use YYYY-MM-DD format
5. **Unreleased section**: Keep an "Unreleased" section for upcoming changes
6. **Update on every commit**: Add entries as you make changes

**When to update CHANGELOG.md**:
- Adding new features or modules
- Changing existing functionality
- Fixing bugs
- Deprecating features
- Removing features
- Security updates
- **Any deviation from PLAN.md** (document why)

### Version Tags

**Best Practice**: Tag releases in Git:
```bash
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
```

Tag format: `vMAJOR.MINOR.PATCH` (e.g., `v1.2.3`)

## File Organization

### File Naming and Structure

**MANDATORY**: Use numeric prefixes to control execution order:
- `00-providers.tf` - Provider configuration and Terraform settings (ALWAYS FIRST)
- `01-variables.tf` - Variable definitions
- `02-data.tf` - Data sources (if many exist)
- `03-network.tf` - Network resources
- `04-compute.tf` - Compute resources
- `05-storage.tf` - Storage resources
- `06-security.tf` - Security groups, IAM, etc.
- `10-main.tf` - Main resources (if not using numbered files)
- `90-outputs.tf` - Output values (ALWAYS LAST, use 90-99 range)

**File Naming Rules**:
- Use lowercase with underscores: `network_resources.tf`
- Be descriptive: `database_cluster.tf` not `db.tf`
- Group by resource type or function, not by provider
- Keep related resources in the same file

## Code Style and Conventions

### Provider Configuration

**REQUIRED**: Always pin provider versions:
```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"  # Use ~> to allow patch updates but not minor version changes
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7"
    }
  }
}
```

**Best Practice**: Pin provider versions to avoid unexpected changes. Use `~>` to allow patch updates but not minor version changes.

### Resource Naming

- Use descriptive names: `aws_vpc.main` not `aws_vpc.vpc1`
- Follow Terraform conventions: lowercase with underscores
- Include resource type in name when helpful: `aws_security_group.web_server`

### Variable Definitions

**MANDATORY**: All variables MUST include:
- `description` - Always include a description
- `type` - Explicit type declaration
- `nullable` - Explicit nullability (use `nullable = true` with `default = null` for optional)
- `sensitive = true` - For passwords, tokens, and secrets
- `validation` blocks - For input validation when appropriate

**Example**:
```hcl
variable "cluster_name" {
  description = "The name of the ROSA HCP cluster"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "admin_password" {
  description = "Password for the admin user"
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(var.admin_password) >= 14
    error_message = "Password must be at least 14 characters long."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption (optional)"
  type        = string
  nullable    = true
  default     = null
}
```

**Best Practices**:
- Always include `description` for all variables and outputs
- Use `sensitive = true` for passwords, tokens, and secrets
- Use `nullable = true` with `default = null` for optional variables
- Provide meaningful default values when appropriate
- Use `validation` blocks for input validation

### Output Definitions

**MANDATORY**: All outputs MUST include:
- `description` - Always include a description
- `sensitive` - Mark as `true` for sensitive outputs (passwords, tokens, kubeconfigs)

**Example**:
```hcl
output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
  sensitive   = false
}

output "kubeconfig" {
  description = "Kubernetes configuration file"
  value       = module.cluster.kubeconfig
  sensitive   = true
}
```

### Locals for Computed Values

Use locals for computed values and conditional logic:
```hcl
locals {
  # Use locals for computed values and conditional logic
  environment = var.environment != null ? var.environment : "dev"
  common_tags = merge(var.tags, {
    Environment = local.environment
    ManagedBy   = "Terraform"
    Project     = "rosa-hcp"
  })
}
```

## Resource Lifecycle

Use lifecycle blocks appropriately:
```hcl
resource "aws_instance" "example" {
  # ...

  lifecycle {
    # Use create_before_destroy for resources that can't be replaced in-place
    create_before_destroy = true

    # Use prevent_destroy sparingly for critical resources
    # prevent_destroy = true

    # Ignore changes for attributes managed outside Terraform
    ignore_changes = [tags]
  }
}
```

## Dependencies

- **Prefer implicit dependencies** (references) over explicit `depends_on`
- Use `depends_on` only when dependencies aren't obvious
- **Document why `depends_on` is needed** if you use it

## Conditional Resources

**Best Practice**: Prefer `for_each` over `count` when possible for more stable resource addressing.

```hcl
# Use count for simple conditionals
resource "aws_instance" "bastion" {
  count = var.create_bastion ? 1 : 0
  # ...
}

# Use for_each for multiple resources (more stable addressing)
resource "aws_instance" "workers" {
  for_each = var.worker_configs
  # ...
}
```

## Error Handling

Provide clear, actionable error messages using preconditions and postconditions:
```hcl
resource "aws_instance" "example" {
  # ...

  lifecycle {
    precondition {
      condition     = var.instance_type != "t2.micro" || var.environment == "dev"
      error_message = "t2.micro instances are only allowed in dev environment. Current: ${var.environment}"
    }

    postcondition {
      condition     = self.private_ip != null
      error_message = "Instance must have a private IP address"
    }
  }
}
```

## State Management

### Remote State

**MANDATORY**: Always use remote state for production:
```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

### State Locking

- Always enable state locking (automatic with S3 backend + DynamoDB)
- Configure appropriate lock timeouts
- **Never disable locking in production**

### State File Hygiene

- **Never commit state files** to version control (add to `.gitignore`)
- Use `.terraformignore` to exclude unnecessary files
- Regularly review state file size
- Use `terraform state list` to audit resources

## Module Development

### Module Structure

**REQUIRED** structure:
```
modules/my-module/
├── main.tf           # Primary resources
├── variables.tf       # Input variables
├── outputs.tf         # Output values
├── README.md          # Module documentation (REQUIRED)
└── versions.tf         # Provider requirements (optional)
```

### Module Best Practices

**Version Pinning**:
- Pin module versions when using from registry: `source = "terraform-aws-modules/vpc/aws?ref=v5.0.0"`
- Use version constraints: `version = "~> 5.0"` (allows patch updates)
- Document version compatibility

**Module Interface**:
- Keep interfaces simple and focused
- Use consistent variable naming
- Provide sensible defaults
- **Document all inputs and outputs**

**Example Module**:
```hcl
# modules/vpc/main.tf
resource "aws_vpc" "this" {
  cidr_block = var.cidr_block
  tags       = var.tags
}

# modules/vpc/variables.tf
variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
  nullable    = false
}

# modules/vpc/outputs.tf
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
  sensitive   = false
}
```

## Security Practices

### Secrets Management

**CRITICAL**: Never commit secrets:
- Use environment variables: `TF_VAR_password`
- Use secret management systems (AWS Secrets Manager, HashiCorp Vault)
- Mark sensitive variables: `sensitive = true`
- Mark sensitive outputs: `sensitive = true`

**Example**:
```hcl
variable "api_key" {
  description = "API key for external service"
  type        = string
  sensitive   = true
  nullable    = false
}
```

### IAM and Permissions

- Follow principle of least privilege
- Review IAM policies regularly
- Use separate service accounts/roles for CI/CD
- Document why specific permissions are needed

### Security Scanning

Use checkov or similar tools to scan for security issues:
```bash
checkov -d . --framework terraform
```

**Suppressing False Positives**:
Use inline comments in your code:
```hcl
resource "aws_s3_bucket" "public" {
  # checkov:skip=CKV_AWS_20:This bucket is intentionally public for static content
  bucket = "public-static-content"
  acl    = "public-read"
}
```

**Best Practice**: Document why you're skipping checks. If a check is frequently skipped, consider if the configuration should be changed.

## Resource Tagging

**MANDATORY**: Use consistent tagging strategy:
```hcl
locals {
  common_tags = {
    Environment   = var.environment
    Project       = var.project_name
    ManagedBy     = "Terraform"
    CreatedDate   = timestamp()
  }
}

resource "aws_instance" "example" {
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-web-server"
  })
}
```

### Provider Configuration

Use `default_tags` for AWS provider:
```hcl
provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}
```

## Performance

- Use `for_each` instead of `count` when possible (more stable resource addressing)
- Avoid unnecessary `depends_on` (Terraform usually infers dependencies)
- Use `-target` sparingly and only for debugging
- Consider `terraform plan -refresh=false` for faster plans when state is current

## Code Organization

- Group related resources together
- Use data sources to avoid hardcoding values
- Cache data source results when appropriate
- Organize data sources in a `data.tf` file if many exist

## Code Comments

**When to comment**:
- Complex logic or non-obvious decisions
- Workarounds for provider limitations
- Why certain patterns are used
- Resource lifecycle decisions

**Example**:
```hcl
# Use create_before_destroy because this resource can't be replaced in-place
resource "aws_instance" "example" {
  lifecycle {
    create_before_destroy = true
  }
}
```

## Code Quality Checks

### Mandatory Checks After Modifying Files

**CRITICAL**: After modifying any Terraform (`.tf`, `.tfvars`) or shell script (`.sh`) files, **ALWAYS run the appropriate formatting, linting, and validation checks** before committing changes.

#### Terraform Files

**After modifying any `.tf` or `.tfvars` files**, run:

```bash
# Format Terraform files
make tf-fmt

# Check Terraform formatting (non-destructive)
make tf-fmt-check

# Validate Terraform syntax and configuration
make tf-validate

# Or run all Terraform checks at once
make tf-fmt-check tf-validate
```

**What these checks do**:
- `tf-fmt`: Formats all Terraform files according to standard formatting rules
- `tf-fmt-check`: Verifies files are properly formatted without modifying them (used in CI/CD)
- `tf-validate`: Validates Terraform syntax and configuration correctness for all modules and root config

**Failure to run these checks** may result in:
- CI/CD pipeline failures
- Inconsistent code formatting
- Syntax errors that could break deployments
- Configuration errors that only surface during `terraform apply`

#### Shell Scripts

**After modifying any `.sh` files**, run:

```bash
# Format shell scripts
make sh-fmt

# Check shell script formatting (non-destructive)
make sh-fmt-check

# Lint shell scripts with ShellCheck
make sh-lint

# Or run all shell script checks at once
make sh-fmt-check sh-lint
```

**What these checks do**:
- `sh-fmt`: Formats all shell scripts using shfmt for consistent formatting
- `sh-fmt-check`: Verifies shell scripts are properly formatted without modifying them (used in CI/CD)
- `sh-lint`: Runs ShellCheck to catch common errors, best practice violations, and potential bugs

**Failure to run these checks** may result in:
- CI/CD pipeline failures
- Shell script errors that only surface at runtime
- Security vulnerabilities or bugs in scripts
- Inconsistent code formatting

#### Combined Checks

**After modifying both Terraform and shell script files**, run:

```bash
# Format all files (Terraform + shell scripts)
make fmt

# Check formatting for all files (non-destructive)
make fmt-check

# Validate all code (Terraform + shell scripts)
make validate

# Run all linting checks (Terraform + shell scripts)
make lint

# Run all tests (format check, validation, and linting)
make test
```

**Recommended Workflow**:

1. **Make your changes** to Terraform or shell script files
2. **Run formatting** to fix auto-fixable issues:
   ```bash
   make lint-fix  # Fixes formatting for both Terraform and shell scripts
   ```
3. **Run validation and linting** to catch errors:
   ```bash
   make test  # Runs all checks: fmt-check, validate, and lint
   ```
4. **Fix any remaining issues** reported by the checks
5. **Re-run checks** until all pass
6. **Commit your changes**

#### Pre-Commit Checklist

Before committing any changes that modify Terraform or shell script files:

- [ ] **Terraform files formatted**: `make tf-fmt-check` passes
- [ ] **Terraform files validated**: `make tf-validate` passes
- [ ] **Shell scripts formatted**: `make sh-fmt-check` passes
- [ ] **Shell scripts linted**: `make sh-lint` passes
- [ ] **All checks pass**: `make test` passes

#### CI/CD Integration

These checks are automatically run in GitHub Actions workflows:
- **PR checks** (`terraform-pr-checks.yml`): Runs on all pull requests
- **Master checks** (`terraform-master-checks.yml`): Runs on pushes to main/master

**All checks must pass** before code can be merged. Running checks locally before pushing saves time and ensures your PR will pass CI/CD.

#### Quick Reference

```bash
# Individual checks
make tf-fmt          # Format Terraform files
make tf-fmt-check    # Check Terraform formatting
make tf-validate     # Validate Terraform code
make sh-fmt          # Format shell scripts
make sh-fmt-check    # Check shell script formatting
make sh-lint         # Lint shell scripts

# Combined checks
make fmt             # Format all files
make fmt-check       # Check formatting for all files
make validate        # Validate all code
make lint            # Run all linting checks
make lint-fix        # Fix auto-fixable issues
make test            # Run all tests (recommended before commit)
```

## ROSA HCP Specific Rules

### Network Modules

- **MANDATORY**: Apply ROSA-required tags to subnets:
  - Private Subnets: `kubernetes.io/role/internal-elb = "1"`
  - Public Subnets: `kubernetes.io/role/elb = "1"`

### Cluster Module

- Always use `multi_az = true` for production clusters
- Set `private = true` for production (PrivateLink API)
- Enable `etcd_encryption = true` for production
- Use customer-managed KMS keys for encryption in production

### IAM Module

- Use prefixes for account roles to ensure uniqueness: `account_role_prefix = "${var.cluster_name}-"`
- Document all operator roles created
- Use least privilege principles

## Checklist for New Code

When writing new Terraform code, ensure:
- [ ] **PLAN.md reviewed** - Changes align with project plan
- [ ] **PLAN.md updated** - If architecture changed, update the plan
- [ ] **CHANGELOG.md updated** - Document all changes
- [ ] File uses numeric prefix (00-99) for execution order
- [ ] File name uses lowercase with underscores
- [ ] Provider versions are pinned
- [ ] All variables have descriptions, types, and nullable flags
- [ ] Sensitive variables marked with `sensitive = true`
- [ ] All outputs have descriptions
- [ ] Sensitive outputs marked with `sensitive = true`
- [ ] Resources use descriptive names
- [ ] Common tags are applied to all resources
- [ ] No secrets are hardcoded
- [ ] State backend is configured (for cluster directories)
- [ ] Validation blocks added where appropriate
- [ ] Comments added for complex logic or non-obvious decisions
- [ ] Module README.md created/updated (if creating/updating a module)
- [ ] Documentation updated for any new features or changes
- [ ] **Code quality checks passed** - **MANDATORY**: Run `make test` after modifying files (see Code Quality Checks section)

When writing new shell scripts, ensure:
- [ ] Script uses `set -euo pipefail` for strict error handling
- [ ] All variables are quoted to prevent word splitting
- [ ] Script is executable (`chmod +x`)
- [ ] Script follows existing patterns and conventions
- [ ] Error handling and user feedback implemented
- [ ] **Code quality checks passed** - **MANDATORY**: Run `make sh-fmt-check sh-lint` after modifying scripts (see Code Quality Checks section)

## Workflow Checklist

Before committing code, ensure:
1. [ ] **Inputs validated** - Configuration, values, and parameters validated against requirements
2. [ ] **Assumptions tested** - Verified assumptions with dry-run, template, or test commands
3. [ ] **Root cause identified** - Understood underlying issue, not just symptoms
4. [ ] **Issues discussed** - Errors, bugs, or multiple solution approaches discussed before implementing
5. [ ] **Minimal changes made** - Fixed root cause with targeted changes, avoided workarounds
6. [ ] **Plan file inspected** - Used `terraform show` to verify plan matches expectations (see Terraform-Specific Debugging Techniques)
7. [ ] **Variable flow traced** - Verified variables from root → child modules (see Terraform-Specific Debugging Techniques)
8. [ ] **Plan regenerated** - Deleted old plan and regenerated after code changes
9. [ ] Code follows PLAN.md specifications
10. [ ] PLAN.md updated if architecture changed
11. [ ] CHANGELOG.md updated with changes
12. [ ] All documentation updated (README.md, module docs)
13. [ ] **Code quality checks passed** - **MANDATORY**: Run `make test` after modifying Terraform or shell script files (see Code Quality Checks section)
    - [ ] Terraform files formatted: `make tf-fmt-check` passes
    - [ ] Terraform files validated: `make tf-validate` passes
    - [ ] Shell scripts formatted: `make sh-fmt-check` passes
    - [ ] Shell scripts linted: `make sh-lint` passes
14. [ ] Security scanning completed (checkov)
15. [ ] Variables and outputs documented
16. [ ] Sensitive data properly handled
17. [ ] Version numbers updated if needed
18. [ ] Git commit message references PLAN.md if deviating

## Reference Repositories

**IMPORTANT**: The `./reference/` directory contains three reference repositories that provide valuable source code examples and patterns. These repositories significantly improve Cursor's accuracy and understanding of ROSA HCP Terraform patterns.

### Checking for Reference Repositories

**MANDATORY**: Before implementing new features or patterns, check if reference implementations exist in `./reference/`:

1. **rosa-hcp-dedicated-vpc** (`./reference/rosa-hcp-dedicated-vpc/`):
   - **Purpose**: Comprehensive ROSA HCP deployment example with advanced production features
   - **Useful References**:
     - API endpoint security group configuration (`terraform/2.expose-api.tf`) - **Used for api_endpoint_allowed_cidrs implementation**
     - Secrets management (`terraform/3.secrets.tf`) - AWS Secrets Manager integration patterns
     - Logging and SIEM (`terraform/4.logging.tf`, `terraform/5.siem-logging.tf`) - CloudWatch and SIEM integration
     - Cert Manager (`terraform/6.cert-manager.tf`) - Certificate management patterns
     - Storage (`terraform/7.storage.tf`) - EFS storage configuration
     - IPSec VPN (`terraform/8.ipsec.tf`) - VPN connectivity patterns
     - Bootstrap scripts (`terraform/9.bootstrap.tf`, `scripts/*.tftpl`) - Cluster initialization patterns
     - Alerting (`terraform/10.alerting.tf`) - Monitoring and alerting setup
     - Ingress (`terraform/11.ingress.tf`) - Ingress controller configuration
     - Machine pool management (`terraform/12-restart-default-machinepool.tf`) - Machine pool lifecycle patterns
     - Termination protection (`terraform/13.termination-protection.tf`) - Resource protection patterns
   - **When to Reference**: Production-grade features, advanced configurations, Day 2 operations

2. **terraform-rosa** (`./reference/terraform-rosa/`):
   - **Purpose**: Red Hat MOBB's all-in-one ROSA module (supports both Classic and HCP)
   - **Source**: https://github.com/rh-mobb/terraform-rosa
   - **Useful References**:
     - Network module (`modules/terraform-rosa-networking/`) - Network topology patterns
     - Cluster creation (`04-cluster.tf`) - Cluster resource patterns and version handling
     - IAM roles (`03-roles.tf`) - IAM role creation patterns
     - Identity providers (`05-identity.tf`) - HTPasswd and other IDP patterns
     - Bastion host (`06-bastion.tf`) - Bastion host configuration
     - GitOps deployment (`21-gitops.tf`) - GitOps operator installation
     - File organization - Numbered file prefix system (00-99) for execution order
   - **When to Reference**: Module structure patterns, file organization, simpler deployment patterns

3. **terraform-provider-rhcs** (`./reference/terraform-provider-rhcs/`):
   - **Purpose**: Source code for the RHCS Terraform provider
   - **Source**: https://github.com/terraform-redhat/terraform-provider-rhcs
   - **Useful References**:
     - Provider documentation (`docs/`) - Complete provider resource and data source documentation
     - Examples (`examples/`) - Official provider usage examples
     - Resource implementations (`provider/*/`) - Understanding how provider resources work internally
     - Data sources (`docs/data-sources/`) - Available data sources and their usage
     - Guides (`docs/guides/`) - Provider-specific guides (upgrading clusters, machine pools, etc.)
   - **When to Reference**: Understanding provider capabilities, finding available resources/data sources, debugging provider issues

4. **OCM API Specification** (`./reference/OCM.json`):
   - **Purpose**: Complete OpenAPI specification for the OpenShift Cluster Manager (OCM) API
   - **Source**: Exported from OCM API endpoint
   - **Useful References**:
     - API schema definitions (`components/schemas/`) - Complete data structures and types
     - Endpoint definitions (`paths/`) - Available API endpoints and operations
     - Request/response schemas - Understanding API payload structures
     - Field names and types - Verifying exact API field names (e.g., `role_arn` vs `roleArn`)
   - **When to Reference**:
     - Verifying API field names and structures when implementing provider features
     - Understanding nested object structures (e.g., `aws.audit_log.role_arn`)
     - Checking available API endpoints and operations
     - Confirming data types and validation rules
   - **Example**: Used to verify CloudWatch audit log structure (`AWS.audit_log.role_arn`)

5. **OCM SDK** (`./reference/ocm-sdk-go/`):
   - **Purpose**: Go SDK for the OpenShift Cluster Manager (OCM) API
   - **Source**: https://github.com/openshift-online/ocm-sdk-go
   - **Useful References**:
     - Builder patterns (`*_builder_alias.go`) - How to construct API objects (e.g., `NewAuditLog()`, `RoleArn()`)
     - Type definitions (`*_type_alias.go`) - Go types for API objects
     - Method names - Verifying exact SDK method names (e.g., `RoleArn` vs `RoleARN`, `GetRoleArn` vs `GetRoleARN`)
     - OpenAPI spec (`openapi/clusters_mgmt/v1/openapi.json`) - Generated OpenAPI spec used by SDK
   - **When to Reference**:
     - Implementing provider features that use OCM SDK
     - Verifying SDK method names and signatures
     - Understanding how to build API objects (builders)
     - Checking available methods on types (getters, setters)
   - **Example**: Used to verify `AuditLogBuilder.RoleArn()` and `AuditLog.GetRoleArn()` method names

### Using Reference Repositories

**Best Practice**: When implementing new features:
1. **Check reference repositories first** - Look for similar patterns in `./reference/`
2. **Reference the implementation** - Add comments referencing the source file (e.g., `# Reference: ./reference/rosa-hcp-dedicated-vpc/terraform/2.expose-api.tf`)
3. **Adapt patterns** - Adapt patterns to match this repository's architecture and conventions
4. **Document deviations** - If deviating from reference patterns, document why in code comments

**Note**: These repositories and files are cloned/downloaded locally for development. They are not part of the main repository but provide invaluable reference material. See README.md for instructions on cloning/downloading them.

## References

- **Project Plan**: See `PLAN.md` in repository root
- Red Hat MOBB Terraform Rules: https://github.com/rh-mobb/mobb-rules/blob/main/content/languages/terraform/_index.md
- Terraform Best Practices: https://www.terraform.io/docs/language/best-practices
- ROSA HCP Documentation: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/
- Keep a Changelog: https://keepachangelog.com/
- Semantic Versioning: https://semver.org/
- **OCM API Specification**: `./reference/OCM.json` - OpenAPI spec for OCM API (see Reference Repositories section)
- **OCM SDK**: `./reference/ocm-sdk-go/` - Go SDK for OCM API (see Reference Repositories section)
