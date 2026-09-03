# Covers: required_version, rhcs, source, version
# Does: Pins the Terraform language floor and the RHCS provider compatibility range.
# Why: The plan evidence and provider behavior are version-bound to these constraints.
# Change: A different provider version may support OpenID updates with different semantics.
# Trap: Relaxing either bound silently changes the behavior this module documents.
# Evidence: https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/identity_provider
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7.7"
    }
  }
}
