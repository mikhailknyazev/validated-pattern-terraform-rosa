variable "enabled" {
  description = "When true, create the HTPasswd identity provider, user, and group membership. When false, no resources are created (apply with false destroys previously created resources)."
  type        = bool
  default     = false
  nullable    = false
}

variable "cluster_id" {
  description = "ROSA HCP cluster ID. Required when enabled is true."
  type        = string
  nullable    = true
  default     = null
}

variable "password" {
  description = "Optional HTPasswd password. When null, a random password is generated. When set, that value is used and random_password is not created."
  type        = string
  sensitive   = true
  nullable    = true
  default     = null

  validation {
    # Covers: condition
    # Does: Validates a supplied password without evaluating length on null.
    # Why: Terraform 1.5.0 through 1.11 evaluate both sides of the prior || form.
    # Change: A non-null password shorter than fourteen characters remains invalid.
    # Trap: Restoring boolean OR breaks the variable's own null default.
    # Evidence: https://developer.hashicorp.com/terraform/language/expressions/conditionals
    condition     = var.password == null ? true : length(var.password) >= 14
    error_message = "HTPasswd password must be at least 14 characters when set (ROSA HTPasswd requirement)."
  }
}

# Covers: description, type, default, nullable
# Does: Declares a plan-known choice of caller-owned or module-owned password generation.
# Why: Password values may be unknown during plan while resource cardinality must be known.
# Change: False requires a caller value; true creates the module password resource.
# Trap: Null preserves compatibility but cannot classify an unknown caller-generated value.
# Evidence: https://developer.hashicorp.com/terraform/language/meta-arguments/count
variable "generate_password" {
  description = "Optional plan-known password-source choice. True creates this module's random password; false requires password from the caller. Null preserves the prior behavior of deriving the choice from password nullability, but callers supplying an apply-time generated value must set false so resource count remains plan-known."
  type        = bool
  default     = null
  nullable    = true
}

variable "idp_name" {
  description = "Name of the HTPasswd identity provider"
  type        = string
  nullable    = false
}

variable "username" {
  description = "HTPasswd username"
  type        = string
  nullable    = false
}

variable "admin_group" {
  description = "OpenShift group to add the user to"
  type        = string
  default     = "cluster-admins"
  nullable    = false
}
