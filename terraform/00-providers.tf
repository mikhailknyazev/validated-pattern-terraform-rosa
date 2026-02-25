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
      # Official registry provider - 1.7.4 adds rhcs_log_forwarder support
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7.4"
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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
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
# Authentication: Set credentials before using make. Two options (see README.md):
#   Option 1 (Token): RHCS_TOKEN - offline token from console.redhat.com
#   Option 2 (Service account): RHCS_CLIENT_ID + RHCS_CLIENT_SECRET - Red Hat service account
# This project does not manage credentials - user responsibility.
provider "rhcs" {
  url = "https://api.openshift.com"
  # Provider reads from env: RHCS_TOKEN, RHCS_CLIENT_ID, RHCS_CLIENT_SECRET
}

# Shell provider for bootstrap scripts
# This provider must be configured at the root level, not in modules,
# to avoid making modules "legacy modules" that cannot use depends_on
provider "shell" {
  interpreter           = ["/bin/sh", "-c"]
  enable_parallelism    = false
  sensitive_environment = {}
}
