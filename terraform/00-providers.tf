terraform {
  # Backend configuration is provided via -backend-config flags or environment variables
  # For local development: terraform init -backend-config="path=../../clusters/<name>/infrastructure.tfstate"
  # For CI/CD with S3: terraform init -backend-config="bucket=..." -backend-config="key=..." etc.
  # Default to local backend, but can be overridden via -backend-config flags
  backend "local" {
    # path provided via -backend-config flag or environment variable
  }

  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    rhcs = {
      # Official registry provider
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    shell = {
      source  = "scottwinkler/shell"
      version = ">= 1.7.10"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
  }
}

# Local value for tags (use override if set, otherwise use tags variable)
locals {
  tags = var.tags_override != null ? var.tags_override : var.tags
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# Registry provider for most resources (IAM, OIDC, nested modules, etc.)
provider "rhcs" {
  # Token can be provided via:
  # 1. Variable: var.token (set in terraform.tfvars or via TF_VAR_token environment variable)
  # 2. Environment variable: OCM_TOKEN or ROSA_TOKEN (if var.token is not set)
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/00-provider.tf
  # Get token from: https://console.redhat.com/openshift/token/rosa/show
  token = var.token
  url   = "https://api.openshift.com"
  # Optional: Custom token URL and client settings
  # token_url     = "https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token"
  # client_id     = "cloud-services"
  # client_secret = "" # Empty string uses default client secret
}

# Shell provider for bootstrap scripts
# This provider must be configured at the root level, not in modules,
# to avoid making modules "legacy modules" that cannot use depends_on
provider "shell" {
  interpreter           = ["/bin/sh", "-c"]
  enable_parallelism    = false
  sensitive_environment = {}
}
