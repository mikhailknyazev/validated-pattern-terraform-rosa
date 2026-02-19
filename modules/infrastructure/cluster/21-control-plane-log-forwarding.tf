# Control Plane Log Forwarding Configuration
# Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/guides/log-forwarders
# Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/log_forwarder
# Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/security_and_compliance/rosa-forwarding-control-plane-logs
#
# Uses rhcs_log_forwarder resource (RHCS provider 1.7.4+).
# Separate resources for CloudWatch and S3 allow different log groups and applications per destination.
# The IAM role and policies are created in the IAM module.
# CloudWatch log group and S3 bucket are created in 22-control-plane-log-forwarding-resources.tf.

locals {
  # Build groups for rhcs_log_forwarder (list of {id} objects)
  # Per Red Hat doc, groups are specified by name only; omit version so backend uses latest.
  # Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/security_and_compliance/rosa-forwarding-control-plane-logs#rosa-determine-log-groups_rosa-configuring-the-log-forwarder
  cloudwatch_log_forwarder_groups = [
    for group in [for g in var.control_plane_log_cloudwatch_groups : lower(g)] : {
      id = group
    }
  ]
  s3_log_forwarder_groups = [
    for group in [for g in var.control_plane_log_s3_groups : lower(g)] : {
      id = group
    }
  ]
}

# CloudWatch log forwarder - created when CloudWatch destination is enabled
resource "rhcs_log_forwarder" "cloudwatch" {
  count = local.persists_through_sleep && var.enable_control_plane_log_forwarding && var.control_plane_log_cloudwatch_enabled && var.control_plane_log_forwarding_role_arn != null ? 1 : 0

  cluster      = one(rhcs_cluster_rosa_hcp.main[*].id)
  applications = length(var.control_plane_log_cloudwatch_applications) > 0 ? var.control_plane_log_cloudwatch_applications : null
  groups       = local.cloudwatch_log_forwarder_groups

  cloudwatch = {
    log_distribution_role_arn = var.control_plane_log_forwarding_role_arn
    log_group_name            = var.control_plane_log_cloudwatch_log_group_name != null ? var.control_plane_log_cloudwatch_log_group_name : "${var.cluster_name}-control-plane-logs"
  }

  depends_on = [rhcs_cluster_rosa_hcp.main]
}

# S3 log forwarder - created when S3 destination is enabled
resource "rhcs_log_forwarder" "s3" {
  count = local.persists_through_sleep && var.enable_control_plane_log_forwarding && var.control_plane_log_s3_enabled && length(aws_s3_bucket.control_plane_logs) > 0 ? 1 : 0

  cluster      = one(rhcs_cluster_rosa_hcp.main[*].id)
  applications = length(var.control_plane_log_s3_applications) > 0 ? var.control_plane_log_s3_applications : null
  groups       = local.s3_log_forwarder_groups

  s3 = {
    bucket_name   = aws_s3_bucket.control_plane_logs[0].id
    bucket_prefix = var.control_plane_log_s3_bucket_prefix
  }

  depends_on = [
    rhcs_cluster_rosa_hcp.main,
    aws_s3_bucket.control_plane_logs
  ]
}
