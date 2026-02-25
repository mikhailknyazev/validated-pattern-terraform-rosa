#!/bin/bash
# scripts/vpn/status.sh
# Check OpenVPN tunnel status for AWS Client VPN
# Usage: status.sh <cluster-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
	error "Usage: $0 <cluster-name>"
	exit 1
fi

get_cluster_dir "$CLUSTER_NAME" >/dev/null

PIDFILE="/tmp/openvpn-${CLUSTER_NAME}.pid"
info "Checking OpenVPN tunnel status for $CLUSTER_NAME..."

if [ -f "$PIDFILE" ]; then
	PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
	if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
		success "OpenVPN tunnel is active for $CLUSTER_NAME"
		info "PID: $PID"
		exit 0
	fi
	rm -f "$PIDFILE" 2>/dev/null || true
fi

# Fallback: check by process name and config path
if pgrep -f "openvpn.*clusters/${CLUSTER_NAME}" >/dev/null 2>&1; then
	PID=$(pgrep -f "openvpn.*clusters/${CLUSTER_NAME}" | head -1)
	success "OpenVPN tunnel is active for $CLUSTER_NAME"
	info "PID: $PID"
	exit 0
fi

warn "OpenVPN tunnel is not running for $CLUSTER_NAME"
exit 1
