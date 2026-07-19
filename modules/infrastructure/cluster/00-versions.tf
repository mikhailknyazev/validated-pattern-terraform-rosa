terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    rhcs = {
      # 1.7.4 adds rhcs_log_forwarder; 1.7.5 adds day-1 autoscaling hints on rhcs_cluster_rosa_hcp
      # 1.7.7 fixes AutoNode post-apply state inconsistency (OCM-25158)
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7.7"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
