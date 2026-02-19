# CloudWatch Audit Log Forwarding Configuration (DEPRECATED)
# Reference: https://access.redhat.com/solutions/7002219
#
# ⚠️  DEPRECATED: This legacy audit logging implementation is deprecated.
# Use the new control plane log forwarding mechanism instead (21-control-plane-log-forwarding.tf).
#
# Migration: Set enable_control_plane_log_forwarding = true and enable_audit_logging = false
# The new mechanism supports forwarding multiple log groups (api, authentication, controller manager,
# scheduler) to CloudWatch and/or S3 using ROSA's managed log forwarder service.
# Note: 'Other' group is not supported by ROSA CLI despite documentation.
#
# This configuration configures the cluster to forward audit logs to CloudWatch.
# The IAM role and policy are created in the IAM module.
#
# NOTE: The IAM role ARN is provided via cloudwatch_audit_logging_role_arn variable (from IAM module output)

# Configure audit log forwarding on the cluster using ROSA CLI
# Using script-based approach until audit_log_arn is available in official provider release
# Once PR is accepted, we can switch to provider-native implementation in 10-main.tf
# Reference: ./reference/rosa-hcp-dedicated-vpc/terraform/5.siem-logging.tf
resource "null_resource" "configure_audit_logging" {
  count = local.persists_through_sleep && var.enable_audit_logging ? 1 : 0

  triggers = {
    cluster_id   = one(rhcs_cluster_rosa_hcp.main[*].id)
    cluster_name = var.cluster_name
    # Use try() to safely handle null values from module outputs that depend on count
    role_arn = try(var.cloudwatch_audit_logging_role_arn, "")
    # Re-run if the role ARN changes (use empty string hash if null)
    role_arn_hash = try(sha256(var.cloudwatch_audit_logging_role_arn), "")
  }

  # Configure audit logging
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Configuring CloudWatch audit log forwarding for cluster ${var.cluster_name}..."

      # Check if rosa CLI is installed
      if ! command -v rosa &> /dev/null; then
        echo "ERROR: rosa CLI is not installed. Please install it from: https://console.redhat.com/openshift/downloads"
        exit 1
      fi

      # Check if already logged in, only login if not authenticated
      if ! rosa whoami &> /dev/null; then
        echo "Not logged in to ROSA. Attempting to login..."
        # Login to ROSA if token is available via environment variable
        # RHCS_TOKEN, OCM_TOKEN, ROSA_TOKEN all work (set before make - see README RHCS Authentication)
        if [ -n "$${RHCS_TOKEN}" ]; then
          rosa login --token="$${RHCS_TOKEN}" || {
            echo "ERROR: Failed to login with RHCS_TOKEN"
            exit 1
          }
        elif [ -n "$${OCM_TOKEN}" ]; then
          rosa login --token="$${OCM_TOKEN}" || {
            echo "ERROR: Failed to login with OCM_TOKEN"
            exit 1
          }
        elif [ -n "$${ROSA_TOKEN}" ]; then
          rosa login --token="$${ROSA_TOKEN}" || {
            echo "ERROR: Failed to login with ROSA_TOKEN"
            exit 1
          }
        else
          echo "ERROR: Not logged in and no token provided. Set RHCS_TOKEN, OCM_TOKEN, or ROSA_TOKEN environment variable."
          exit 1
        fi
      else
        echo "Already logged in to ROSA"
      fi

      # Configure audit log ARN (check if role ARN is available)
      if [ -z "${var.cloudwatch_audit_logging_role_arn}" ] || [ "${var.cloudwatch_audit_logging_role_arn}" = "null" ]; then
        echo "ERROR: cloudwatch_audit_logging_role_arn is not set. IAM role may not be created yet."
        exit 1
      fi

      rosa edit cluster -c "${var.cluster_name}" --audit-log-arn "${var.cloudwatch_audit_logging_role_arn}" --yes || {
        echo "WARNING: Failed to configure audit logging. Cluster may not be ready yet."
        exit 1
      }

      echo "Successfully configured CloudWatch audit log forwarding"
    EOT
  }

  # Note: No destroy provisioner needed - destroying the cluster automatically removes audit logging configuration

  depends_on = [
    rhcs_cluster_rosa_hcp.main
  ]
}

# Note: Using script-based approach until audit_log_arn is available in official provider release.
# Once PR is accepted, we can switch to provider-native implementation using audit_log_arn attribute in 10-main.tf.
