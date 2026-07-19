# Cluster Termination Protection
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/13.termination-protection.tf
# This resource enables/disables cluster termination protection using the ROSA CLI
# Termination protection prevents accidental cluster deletion

# Script path is defined in 10-main.tf as termination_protection_script_path

# Enable/Disable Termination Protection using ROSA CLI
# Uses null_resource with local-exec provisioners instead of shell provider
# destroy-time provisioners can't reference var.* or local.*, so values are stored in triggers
resource "null_resource" "termination_protection" {
  count = local.persists_through_sleep && var.enable_termination_protection ? 1 : 0

  triggers = {
    cluster_name = var.cluster_name
    script_path  = local.termination_protection_script_path
  }

  provisioner "local-exec" {
    command = self.triggers.script_path
    environment = {
      CLUSTER_NAME = self.triggers.cluster_name
      ENABLE       = "true"
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = self.triggers.script_path
    environment = {
      CLUSTER_NAME = self.triggers.cluster_name
      ENABLE       = "false"
    }
  }

  depends_on = [
    rhcs_cluster_rosa_hcp.main
  ]
}
