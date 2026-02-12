#!/bin/bash
# scripts/utils/get-network-config.sh
# Extract network_type and zero_egress from terraform.tfvars
# Usage: source get-network-config.sh <cluster_dir>
#        or: eval $(get-network-config.sh <cluster_dir>)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

CLUSTER_DIR="${1:-}"
if [ -z "$CLUSTER_DIR" ]; then
	error "Usage: source $0 <cluster_dir>"
	exit 1
fi

if [ ! -d "$CLUSTER_DIR" ]; then
	error "Cluster directory not found: $CLUSTER_DIR"
	exit 1
fi

TFVARS_FILE="$CLUSTER_DIR/terraform.tfvars"
if [ ! -f "$TFVARS_FILE" ]; then
	error "terraform.tfvars not found: $TFVARS_FILE"
	exit 1
fi

# Extract network_type
LINE=$(grep -E "^network_type\s*=" "$TFVARS_FILE" 2>/dev/null | head -1)
if [ -n "$LINE" ]; then
	if echo "$LINE" | grep -q '".*"'; then
		NETWORK_TYPE=$(echo "$LINE" | sed -E 's/.*"([^"]+)".*/\1/')
	else
		NETWORK_TYPE=$(echo "$LINE" | sed -E 's/.*=\s*([^"#]+).*/\1/' | sed 's/[[:space:]]*#.*//' | tr -d ' ')
	fi
else
	NETWORK_TYPE="unknown"
fi

# Extract zero_egress
LINE2=$(grep -E "^zero_egress\s*=" "$TFVARS_FILE" 2>/dev/null | head -1)
if [ -n "$LINE2" ]; then
	if echo "$LINE2" | grep -q '".*"'; then
		ZERO_EGRESS=$(echo "$LINE2" | sed -E 's/.*"([^"]+)".*/\1/')
	else
		ZERO_EGRESS=$(echo "$LINE2" | sed -E 's/.*=\s*([^"#]+).*/\1/' | sed 's/[[:space:]]*#.*//' | tr -d ' ')
	fi
else
	ZERO_EGRESS="false"
fi

# Determine mode
if [ "$NETWORK_TYPE" = "private" ] && [ "$ZERO_EGRESS" = "true" ]; then
	MODE="egress-zero"
else
	MODE="$NETWORK_TYPE"
fi

# Export variables
export NETWORK_TYPE
export ZERO_EGRESS
export MODE

# If not sourced, output export commands
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	echo "export NETWORK_TYPE=\"$NETWORK_TYPE\""
	echo "export ZERO_EGRESS=\"$ZERO_EGRESS\""
	echo "export MODE=\"$MODE\""
fi
