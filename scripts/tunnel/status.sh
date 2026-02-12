#!/bin/bash
# scripts/tunnel/status.sh
# Check tunnel status
# Usage: status.sh <cluster-name>

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
	warn "Tunnel not needed for $NETWORK_TYPE clusters"
	exit 0
fi

info "Checking sshuttle tunnel status..."

cd "$TERRAFORM_INFRA_DIR"
BASTION_ID=$(terraform output -no-color -raw bastion_instance_id 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//' || echo "")

if [ -z "$BASTION_ID" ] || [ "$BASTION_ID" = "null" ]; then
	warn "Bastion not deployed"
	exit 1
fi

VPC_CIDR=$(terraform output -no-color -raw vpc_cidr_block 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//' ||
	terraform output -no-color -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty' | tr -d '\n\r' || echo "")

cd - >/dev/null

if [ -z "$VPC_CIDR" ]; then
	error "VPC CIDR not found"
	exit 1
fi

if pgrep -f "sshuttle.*$VPC_CIDR" >/dev/null 2>&1; then
	PID=$(pgrep -f "sshuttle.*$VPC_CIDR" | head -1)
	success "sshuttle tunnel is active for VPC $VPC_CIDR"
	info "Tunnel PID: $PID"
	info "Bastion ID: $BASTION_ID"
else
	warn "sshuttle tunnel is not running for VPC $VPC_CIDR"
	exit 1
fi
