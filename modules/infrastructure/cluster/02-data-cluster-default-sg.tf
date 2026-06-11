# ROSA default worker security group lookup
#
# After rhcs_cluster_rosa_hcp reports ready, Hypershift still tags the default worker SG
# ({cluster_id}-default-sg) asynchronously. Reading it immediately returns ids = [] and breaks
# EFS mount targets and AutoNode Karpenter discovery tags on first apply.
#
# time_sleep delays the data source read until ROSA has had time to create the SG (no local-exec).

locals {
  need_cluster_default_sg = local.persists_through_sleep && (var.enable_efs || var.enable_autonode)
  cluster_default_sg_name = local.need_cluster_default_sg ? "${one(rhcs_cluster_rosa_hcp.main[*].id)}-default-sg" : ""
}

resource "time_sleep" "wait_for_cluster_default_sg" {
  count = local.need_cluster_default_sg ? 1 : 0

  depends_on = [
    rhcs_cluster_rosa_hcp.main,
  ]

  create_duration = var.rosa_default_sg_wait_duration

  triggers = {
    cluster_id = one(rhcs_cluster_rosa_hcp.main[*].id)
  }
}

data "aws_security_groups" "cluster_default" {
  count = local.need_cluster_default_sg ? 1 : 0

  filter {
    name   = "tag:Name"
    values = [local.cluster_default_sg_name]
  }

  depends_on = [
    time_sleep.wait_for_cluster_default_sg,
  ]

  lifecycle {
    postcondition {
      condition     = length(self.ids) > 0
      error_message = "ROSA default security group ${local.cluster_default_sg_name} not found after ${var.rosa_default_sg_wait_duration} wait; re-run terraform apply or increase rosa_default_sg_wait_duration."
    }
  }
}
