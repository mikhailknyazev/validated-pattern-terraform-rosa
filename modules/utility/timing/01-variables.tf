#------------------------------------------------------------------------------
# Timing Module Variables
#------------------------------------------------------------------------------

variable "enabled" {
  type        = bool
  description = "Enable timing capture. When false, no resources are created."
  default     = false
}

variable "stage" {
  type        = string
  description = "Name of the stage being timed (e.g., 'cluster-creation', 'full-deployment')."
  default     = "cluster-creation"
}

variable "dependency_ids" {
  type        = list(string)
  description = <<-EOT
    List of resource IDs or values that this timing depends on.
    The end time is captured after all dependencies complete.
    
    Example:
      dependency_ids = [module.cluster.cluster_id]
  EOT
  default     = []
}
