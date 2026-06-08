terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    rhcs = {
      # 1.7.4 adds rhcs_log_forwarder; 1.7.7-prerelease.6 fixes AutoNode post-apply state (OCM-25158)
      source  = "terraform-redhat/rhcs"
      version = "1.7.7-prerelease.6"
    }
  }
}
