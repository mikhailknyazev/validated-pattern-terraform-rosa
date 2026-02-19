terraform {
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
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
    shell = {
      source  = "scottwinkler/shell"
      version = ">= 1.7.10"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}
