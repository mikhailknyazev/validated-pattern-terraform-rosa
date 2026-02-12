#!/bin/bash
# scripts/utils/get-infra-outputs.sh
# Extract infrastructure outputs and export as TF_VAR_* environment variables
# Usage: source get-infra-outputs.sh <cluster_name>
#        or: eval $(get-infra-outputs.sh <cluster_name>)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
	error "Usage: source $0 <cluster_name>"
	exit 1
fi

TERRAFORM_INFRA_DIR=$(get_terraform_dir infrastructure)
get_cluster_dir "$CLUSTER_NAME" >/dev/null # Validate cluster exists

# Check infrastructure is initialized
if [ ! -d "$TERRAFORM_INFRA_DIR/.terraform" ]; then
	error "Infrastructure not initialized. Run init-infrastructure.sh first"
	exit 1
fi

# Extract outputs and export as environment variables
cd "$TERRAFORM_INFRA_DIR"

# Core cluster information
TF_VAR_api_url=$(terraform output -raw api_url 2>/dev/null || echo "")
export TF_VAR_api_url
TF_VAR_cluster_id=$(terraform output -raw cluster_id 2>/dev/null || echo "")
export TF_VAR_cluster_id
TF_VAR_cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "")
export TF_VAR_cluster_name
TF_VAR_console_url=$(terraform output -raw console_url 2>/dev/null || echo "")
export TF_VAR_console_url

# Optional infrastructure outputs
TF_VAR_admin_user_created=$(terraform output -raw admin_user_created 2>/dev/null || echo "false")
export TF_VAR_admin_user_created
TF_VAR_bastion_deployed=$(terraform output -raw bastion_deployed 2>/dev/null || echo "false")
export TF_VAR_bastion_deployed
TF_VAR_bastion_instance_id=$(terraform output -raw bastion_instance_id 2>/dev/null || echo "")
export TF_VAR_bastion_instance_id
TF_VAR_bastion_ssm_command=$(terraform output -raw bastion_ssm_command 2>/dev/null || echo "")
export TF_VAR_bastion_ssm_command
TF_VAR_bastion_sshuttle_command=$(terraform output -raw bastion_sshuttle_command 2>/dev/null || echo "")
export TF_VAR_bastion_sshuttle_command

cd - >/dev/null

# If not sourced, output export commands
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	echo "export TF_VAR_api_url=\"$TF_VAR_api_url\""
	echo "export TF_VAR_cluster_id=\"$TF_VAR_cluster_id\""
	echo "export TF_VAR_cluster_name=\"$TF_VAR_cluster_name\""
	echo "export TF_VAR_console_url=\"$TF_VAR_console_url\""
	echo "export TF_VAR_admin_user_created=\"$TF_VAR_admin_user_created\""
	echo "export TF_VAR_bastion_deployed=\"$TF_VAR_bastion_deployed\""
	echo "export TF_VAR_bastion_instance_id=\"$TF_VAR_bastion_instance_id\""
	echo "export TF_VAR_bastion_ssm_command=\"$TF_VAR_bastion_ssm_command\""
	echo "export TF_VAR_bastion_sshuttle_command=\"$TF_VAR_bastion_sshuttle_command\""
fi
