terraform {
  required_version = ">= 1.5.0"

  required_providers {
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7.7"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}
