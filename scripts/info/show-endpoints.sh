#!/bin/bash
# scripts/info/show-endpoints.sh
# Show cluster API and console URLs
# Usage: show-endpoints.sh <cluster-name>

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

# Get network config
source "$PROJECT_ROOT/scripts/utils/get-network-config.sh" "$CLUSTER_DIR"

info "$CLUSTER_NAME Cluster Endpoints ($MODE):"

cd "$TERRAFORM_INFRA_DIR"

API_URL=$(terraform output -raw api_url 2>/dev/null || echo "")
if [ -z "$API_URL" ]; then
	error "Cluster not deployed or terraform outputs not available"
	exit 1
fi

VPC_CIDR=$(terraform output -raw vpc_cidr_block 2>/dev/null ||
	terraform output -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty' || echo "")

terraform output -json 2>/dev/null |
	jq -r '"API URL:     " + .api_url.value, "Console URL:  " + .console_url.value' 2>/dev/null || {
	# Fallback if jq fails
	echo "API URL:     $API_URL"
	CONSOLE_URL=$(terraform output -raw console_url 2>/dev/null || echo "")
	echo "Console URL:  $CONSOLE_URL"
}

if [ -n "$VPC_CIDR" ] && pgrep -f "sshuttle.*$VPC_CIDR" >/dev/null 2>&1; then
	success "✓ sshuttle tunnel active - all VPC traffic routed through bastion"
fi

cd - >/dev/null
