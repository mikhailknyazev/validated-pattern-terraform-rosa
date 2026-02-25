#!/bin/bash
# scripts/vpn/config.sh
# Retrieve VPN config path and connection instructions from Terraform output
# Usage: config.sh <cluster-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
	error "Usage: $0 <cluster-name>"
	exit 1
fi

# Validate cluster directory exists (get_cluster_dir exits if not found)
get_cluster_dir "$CLUSTER_NAME" >/dev/null
TERRAFORM_INFRA_DIR=$(get_terraform_dir infrastructure)

# Initialize to ensure we have the correct cluster state
"$SCRIPT_DIR/../cluster/init-infrastructure.sh" "$CLUSTER_NAME" >/dev/null 2>&1 || true

cd "$TERRAFORM_INFRA_DIR"
VPN_DEPLOYED=$(terraform output -no-color -raw client_vpn_deployed 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//' || echo "false")
if [ "$VPN_DEPLOYED" != "true" ]; then
	error "Client VPN not deployed for $CLUSTER_NAME"
	error "Set enable_client_vpn=true in terraform.tfvars and run terraform apply first."
	exit 1
fi

CONFIG_PATH=$(terraform output -no-color -raw client_vpn_config_path 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//' || echo "")
if [ -z "$CONFIG_PATH" ] || [ "$CONFIG_PATH" = "null" ]; then
	error "VPN config path not found"
	exit 1
fi

success "VPN configuration file: $CONFIG_PATH"
echo ""
terraform output -no-color client_vpn_connection_instructions
cd - >/dev/null
