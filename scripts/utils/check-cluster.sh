#!/bin/bash
# scripts/utils/check-cluster.sh
# Validate cluster directory exists
# Usage: check-cluster.sh <cluster_name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
	error "Usage: $0 <cluster_name>"
	exit 1
fi

get_cluster_dir "$CLUSTER_NAME" >/dev/null
success "Cluster directory validated: $CLUSTER_NAME"
