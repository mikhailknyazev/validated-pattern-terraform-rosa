terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    rhcs = {
      # Registry provider for IAM resources - 1.7.4 adds rhcs_log_forwarder support
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7.4"
    }
  }
}
