terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    rhcs = {
      # 1.7.4 adds rhcs_log_forwarder support
      # 1.7.5 adds autoscaling_enabled / min_replicas / max_replicas day-1 hints on rhcs_cluster_rosa_hcp
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7.5"
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
