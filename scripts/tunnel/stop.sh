#!/bin/bash
# scripts/tunnel/stop.sh
# Stop sshuttle tunnel (wrapper for existing script)
# Usage: stop.sh <cluster-name>

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

# Call existing tunnel-stop script
info "Stopping tunnel..."
"$PROJECT_ROOT/scripts/tunnel-stop.sh" "$TERRAFORM_INFRA_DIR" || warn "Tunnel stop failed or tunnel not running"

success "Tunnel stopped"
