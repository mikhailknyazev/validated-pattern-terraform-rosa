variable "enabled" {
  description = "When true, create the short-lived HTPasswd bootstrap IDP/user and cluster-admins membership. When false, no resources are created (apply with false destroys a previously created bootstrap admin)."
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
  description = "Optional bootstrap HTPasswd password. When null, a random password is generated (useful when calling this module outside the bootstrap script). When set (e.g. by bootstrap-admin.sh), that value is used and random_password is not created."
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
    error_message = "Bootstrap password must be at least 14 characters when set (ROSA HTPasswd requirement)."
  }
}

# Covers: description, type, default, nullable
# Does: Separates the child password-source decision from the password value.
# Why: The wrapper can forward plan-known intent when a password is apply-time unknown.
# Change: False requires a caller value; true lets the shared child generate one.
# Trap: Null deliberately preserves existing literal-password and omitted-password inference.
# Evidence: https://developer.hashicorp.com/terraform/language/values/variables
variable "generate_password" {
  description = "Optional plan-known password-source choice passed to htpasswd-idp. True lets the child generate; false uses password; null preserves the prior literal/null behavior."
  type        = bool
  default     = null
  nullable    = true
}

variable "idp_name" {
  description = "Name of the HTPasswd identity provider created for bootstrap"
  type        = string
  default     = "bootstrap"
  nullable    = false
}

variable "username" {
  description = "Bootstrap HTPasswd username"
  type        = string
  default     = "bootstrap"
  nullable    = false
}

variable "admin_group" {
  description = "OpenShift group to add the bootstrap user to"
  type        = string
  default     = "cluster-admins"
  nullable    = false
}
