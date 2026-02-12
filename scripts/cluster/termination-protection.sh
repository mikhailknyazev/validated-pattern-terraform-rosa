#!/bin/bash

# Termination Protection Script for ROSA HCP Clusters
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/scripts/termination-protection.tftpl
# This script enables or disables cluster termination protection using the ROSA CLI
#
# Environment Variables:
#   CLUSTER_NAME - Name of the ROSA HCP cluster (required)
#   ENABLE - Set to "true" to enable, "false" to disable (required)
#   RHCS_TOKEN - ROSA API token for authentication (optional, uses existing login if not provided)
#   DEBUG - Set to "true" to enable debug output (optional)

set -euo pipefail

# Enable debug output if DEBUG is set
[[ "${DEBUG:-}" == "true" || "${DEBUG:-}" == "1" ]] && set -x

# --- Exit Functions ---
good_exit() {
	local message="$1"
	echo "INFO: $message"
	echo '{"status": "success", "message": "'"$message"'"}'
	exit 0
}

bad_exit() {
	local error_message="$1"
	echo "ERROR: $error_message" >&2
	echo '{"status": "failure", "message": "'"$error_message"'"}'
	exit 1
}

# --- Validation ---
if [[ -z "${CLUSTER_NAME:-}" ]]; then
	bad_exit "CLUSTER_NAME environment variable is required"
fi

if [[ -z "${ENABLE:-}" ]]; then
	bad_exit "ENABLE environment variable is required (must be 'true' or 'false')"
fi

if [[ "${ENABLE}" != "true" && "${ENABLE}" != "false" ]]; then
	bad_exit "ENABLE must be 'true' or 'false', got: ${ENABLE}"
fi

echo "#########################################"
echo "Enable/Disable Cluster Termination Protection Script"
echo "Cluster: ${CLUSTER_NAME}"
echo "Action: ${ENABLE}"
echo "Current Date: $(date)"
echo "#########################################"

# Authenticate with ROSA if token is provided
if [[ -n "${RHCS_TOKEN:-}" ]]; then
	echo "Authenticating with ROSA using provided token..."
	rosa login --token "${RHCS_TOKEN}"
	echo "ROSA login successful."
else
	echo "No RHCS_TOKEN provided, using existing ROSA login session..."
	# Verify we're logged in
	if ! rosa whoami &>/dev/null; then
		bad_exit "Not logged in to ROSA. Please run 'rosa login' or provide RHCS_TOKEN environment variable."
	fi
fi

# Conditional logic for enabling or disabling
if [[ "${ENABLE}" == "true" ]]; then
	echo "Enabling delete protection for cluster '${CLUSTER_NAME}'..."
	rosa edit cluster -c "${CLUSTER_NAME}" --enable-delete-protection --yes ${DEBUG:+--debug}
	good_exit "Cluster delete protection enabled successfully."
else
	echo "Disabling delete protection for cluster '${CLUSTER_NAME}'..."
	# Note: Disabling delete protection cannot be done from CLI according to the reference
	# It must be done via the OCM console or API
	echo "WARNING: Disabling delete protection cannot be done via CLI."
	echo "Please use the Red Hat OpenShift Cluster Manager console to disable delete protection."
	good_exit "Cluster delete protection disable request noted (requires manual console action)."
fi
