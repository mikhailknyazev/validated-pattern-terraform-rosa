# Purpose: define the complete input contract for one built-in-OAuth OpenID provider.
# What this is not: these declarations do not create a tenant registration or protect state.
# Prerequisites: a caller-owned resource identity and protected secret delivery surface.
# Authoritative references:
# - https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/identity_provider
# Covers: description, type, nullable, default, condition, error_message, ca, client_id, client_secret, issuer, extra_scopes, extra_authorize_parameters, claims, email, groups, name, preferred_username, sensitive
# Does: Types every resource value and rejects unsupported identity mapping methods.
# Why: Explicit types keep cardinality known and make the state-resident secret visible.
# Change: Adding optional fields changes the provider request and the module contract.
# Trap: Marking a value sensitive redacts output but does not remove it from state.
# Evidence: https://developer.hashicorp.com/terraform/language/values/variables
variable "cluster_id" {
  description = "ROSA cluster identifier. It may be unknown during a greenfield plan because resource cardinality is controlled by the caller's map keys."
  type        = string
  nullable    = false
}

variable "name" {
  description = "Stable identity-provider name shown by ROSA and OpenShift."
  type        = string
  nullable    = false
}

variable "mapping_method" {
  description = "OpenShift identity mapping method. 'claim' refuses a second identity claiming an existing user; 'add' attaches it to that user."
  type        = string
  default     = "claim"
  nullable    = false

  validation {
    condition     = contains(["add", "claim", "generate", "lookup"], var.mapping_method)
    error_message = "mapping_method must be one of: add, claim, generate, lookup."
  }
}

variable "openid" {
  description = "OpenID Connect registration and state-resident client secret. RHCS 1.7.7 requires a broad lifecycle workaround that hides changes to ca, client_id, client_secret, issuer, extra_scopes, extra_authorize_parameters, and claims; replace the resource deliberately when any member changes."
  type = object({
    ca                         = optional(string)
    client_id                  = string
    client_secret              = string
    issuer                     = string
    extra_scopes               = optional(list(string), [])
    extra_authorize_parameters = optional(map(string), {})
    claims = object({
      email              = optional(list(string), [])
      groups             = optional(list(string), [])
      name               = optional(list(string), [])
      preferred_username = list(string)
    })
  })
  sensitive = true
  nullable  = false
}
