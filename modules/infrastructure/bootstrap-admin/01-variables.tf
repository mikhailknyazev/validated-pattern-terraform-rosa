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
    condition     = var.password == null || length(var.password) >= 14
    error_message = "Bootstrap password must be at least 14 characters when set (ROSA HTPasswd requirement)."
  }
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
