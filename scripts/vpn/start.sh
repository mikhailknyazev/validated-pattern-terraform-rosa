#!/bin/bash
# scripts/vpn/start.sh
# Start OpenVPN tunnel using AWS Client VPN config
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

get_cluster_dir "$CLUSTER_NAME" >/dev/null
TERRAFORM_INFRA_DIR=$(get_terraform_dir infrastructure)

# Initialize and check VPN is deployed
"$SCRIPT_DIR/../cluster/init-infrastructure.sh" "$CLUSTER_NAME" >/dev/null 2>&1 || true

cd "$TERRAFORM_INFRA_DIR"
VPN_DEPLOYED=$(terraform output -no-color -raw client_vpn_deployed 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//' || echo "false")
CONFIG_PATH=$(terraform output -no-color -raw client_vpn_config_path 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//' || echo "")
cd - >/dev/null

if [ "$VPN_DEPLOYED" != "true" ] || [ -z "$CONFIG_PATH" ] || [ "$CONFIG_PATH" = "null" ]; then
	error "Client VPN not deployed for $CLUSTER_NAME"
	error "Set enable_client_vpn=true in terraform.tfvars and run terraform apply first."
	exit 1
fi

# Resolve config path relative to project root
CONFIG_FILE="${PROJECT_ROOT}/${CONFIG_PATH#./}"
if [ ! -f "$CONFIG_FILE" ]; then
	error "VPN config file not found: $CONFIG_FILE"
	error "Run terraform apply to generate the .ovpn file."
	exit 1
fi

PIDFILE="/tmp/openvpn-${CLUSTER_NAME}.pid"
if [ -f "$PIDFILE" ]; then
	PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
	if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
		info "OpenVPN tunnel already running for $CLUSTER_NAME (PID: $PID)"
		exit 0
	fi
	rm -f "$PIDFILE" 2>/dev/null || true
fi

if ! command -v openvpn >/dev/null 2>&1; then
	error "openvpn not found. Install with: brew install openvpn (macOS) or apt install openvpn (Linux)"
	exit 1
fi

info "Starting OpenVPN tunnel for $CLUSTER_NAME..."
if sudo openvpn --config "$CONFIG_FILE" --daemon --writepid "$PIDFILE"; then
	success "OpenVPN tunnel started for $CLUSTER_NAME"
	info "Config: $CONFIG_PATH"
	info "PID file: $PIDFILE"
else
	error "Failed to start OpenVPN. Check config and try: sudo openvpn --config $CONFIG_PATH"
	exit 1
fi
