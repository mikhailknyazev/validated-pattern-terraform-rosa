#!/bin/bash
# scripts/tunnel/start.sh
# Start sshuttle tunnel (wrapper for existing script)
# Usage: start.sh <cluster-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

PROJECT_ROOT=$(get_project_root)

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
	error "Usage: $0 <cluster-name>"
	exit 1
fi

CLUSTER_DIR=$(get_cluster_dir "$CLUSTER_NAME")
TERRAFORM_INFRA_DIR=$(get_terraform_dir infrastructure)

# Check if tunnel is needed
source "$PROJECT_ROOT/scripts/utils/get-network-config.sh" "$CLUSTER_DIR"

if [ "$NETWORK_TYPE" != "private" ] || [ "$ZERO_EGRESS" != "true" ]; then
	warn "Tunnel not needed for $NETWORK_TYPE clusters (public API endpoint)"
	exit 0
fi

# Verify bastion exists
cd "$TERRAFORM_INFRA_DIR"
BASTION_ID=$(terraform output -no-color -raw bastion_instance_id 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//' || echo "")
cd - >/dev/null

if [ -z "$BASTION_ID" ] || [ "$BASTION_ID" = "null" ]; then
	error "Bastion not deployed. Tunnel requires a bastion host."
	error "Set enable_bastion=true in terraform.tfvars and apply infrastructure first."
	exit 1
fi

# Call existing tunnel-start script
info "Starting tunnel via bastion..."
"$PROJECT_ROOT/scripts/tunnel-start.sh" "$TERRAFORM_INFRA_DIR" "$CLUSTER_DIR"

success "Tunnel started successfully"
