#!/bin/bash
# scripts/vpn/stop.sh
# Stop OpenVPN tunnel for AWS Client VPN
# Usage: stop.sh <cluster-name>

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
info "Stopping OpenVPN tunnel for $CLUSTER_NAME..."

if [ -f "$PIDFILE" ]; then
	PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
	if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
		sudo kill "$PID" 2>/dev/null || true
		sudo rm -f "$PIDFILE" 2>/dev/null || rm -f "$PIDFILE" 2>/dev/null || true
		success "OpenVPN tunnel stopped for $CLUSTER_NAME"
		exit 0
	fi
	rm -f "$PIDFILE" 2>/dev/null || true
fi

# Fallback: try to find openvpn process by config path
if pgrep -f "openvpn.*clusters/${CLUSTER_NAME}" >/dev/null 2>&1; then
	sudo pkill -f "openvpn.*clusters/${CLUSTER_NAME}" 2>/dev/null || true
	success "OpenVPN tunnel stopped for $CLUSTER_NAME"
	exit 0
fi

warn "No OpenVPN tunnel found running for $CLUSTER_NAME"
