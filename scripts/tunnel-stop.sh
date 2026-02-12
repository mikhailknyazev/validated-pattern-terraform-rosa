#!/bin/bash
# Stop sshuttle VPN tunnel for egress-zero clusters
# Usage: ./scripts/tunnel-stop.sh <infrastructure_directory>
#
# This script stops the sshuttle VPN tunnel that routes VPC traffic through the bastion.

set -euo pipefail

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

INFRA_DIR="${1:-}"

if [ -z "$INFRA_DIR" ]; then
	echo -e "${YELLOW}Error: Infrastructure directory argument required${NC}" >&2
	echo "Usage: $0 <infrastructure_directory>" >&2
	exit 1
fi

if [ ! -d "$INFRA_DIR" ]; then
	echo -e "${YELLOW}Error: Infrastructure directory does not exist: $INFRA_DIR${NC}" >&2
	exit 1
fi

echo -e "${BLUE}Stopping sshuttle tunnel...${NC}"

# Get bastion instance ID
cd "$INFRA_DIR"
BASTION_ID=$(terraform output -no-color -raw bastion_instance_id 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//' || echo "")

if [ -z "$BASTION_ID" ] || [ "$BASTION_ID" = "null" ]; then
	echo -e "${YELLOW}Bastion not deployed${NC}"
	exit 0
fi

# Get VPC CIDR block
VPC_CIDR=$(terraform output -no-color -raw vpc_cidr_block 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//' ||
	terraform output -no-color -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty' | tr -d '\n\r' || echo "")

PIDFILE="/tmp/sshuttle-egress-zero-$BASTION_ID.pid"

# Try to stop using PID file first
if [ -f "$PIDFILE" ]; then
	PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
	if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
		sudo kill "$PID" 2>/dev/null || true
		# PID file may be owned by root (created by sudo sshuttle), so use sudo to remove it
		sudo rm -f "$PIDFILE" 2>/dev/null || rm -f "$PIDFILE" 2>/dev/null || true
		echo -e "${GREEN}Tunnel stopped${NC}"
		exit 0
	else
		# PID file exists but process is not running - remove it (may need sudo if owned by root)
		sudo rm -f "$PIDFILE" 2>/dev/null || rm -f "$PIDFILE" 2>/dev/null || true
		echo -e "${YELLOW}Tunnel process not found (cleaned up PID file)${NC}"
	fi
fi

# Fallback: try to find and kill by VPC CIDR pattern
if [ -n "$VPC_CIDR" ] && pgrep -f "sshuttle.*$VPC_CIDR" >/dev/null 2>&1; then
	sudo pkill -f "sshuttle.*$VPC_CIDR" 2>/dev/null || true
	echo -e "${GREEN}Tunnel stopped${NC}"
	exit 0
fi

echo -e "${YELLOW}No tunnel found running${NC}"
