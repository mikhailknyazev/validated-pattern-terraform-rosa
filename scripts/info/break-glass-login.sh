#!/bin/bash
# scripts/info/break-glass-login.sh
# Create a ROSA break-glass credential for temporary admin access on external-auth clusters.
# Usage: break-glass-login.sh <cluster-name>

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
use_cluster_tf_data_dir "$CLUSTER_NAME"
TERRAFORM_INFRA_DIR=$(get_terraform_dir infrastructure)

check_required_tools rosa oc

cd "$TERRAFORM_INFRA_DIR"

EXTERNAL_AUTH=$(terraform output -no-color -raw external_auth_providers_enabled 2>/dev/null || echo "false")
if [ "$EXTERNAL_AUTH" != "true" ]; then
	error "This cluster does not use external authentication providers."
	error "Use 'make cluster.${CLUSTER_NAME}.login' for HTPasswd-based login instead."
	exit 1
fi

KUBECONFIG_DIR="$PROJECT_ROOT/clusters/$CLUSTER_NAME"
KUBECONFIG_FILE="$KUBECONFIG_DIR/break-glass.kubeconfig"

info "Creating ROSA break-glass credential for cluster '$CLUSTER_NAME'..."

BG_OUTPUT=$(rosa create break-glass-credential --cluster="$CLUSTER_NAME" --expiration=24h 2>&1) || {
	error "Failed to create break-glass credential."
	error "$BG_OUTPUT"
	exit 1
}

BG_ID=$(echo "$BG_OUTPUT" | grep -oE '[0-9a-z]{32}' | head -1 || true)
if [ -z "$BG_ID" ]; then
	BG_ID=$(rosa list break-glass-credential --cluster="$CLUSTER_NAME" -o json 2>/dev/null |
		python3 -c 'import json,sys; creds=json.load(sys.stdin); print(creds[-1]["id"] if creds else "")' 2>/dev/null || true)
fi

if [ -z "$BG_ID" ]; then
	error "Could not determine break-glass credential ID."
	error "List credentials manually: rosa list break-glass-credential --cluster=$CLUSTER_NAME"
	exit 1
fi

info "Break-glass credential ID: $BG_ID"
info "Waiting for credential to become ready..."

MAX_WAIT=600
ELAPSED=0
INTERVAL=10
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
	STATUS=$(rosa describe break-glass-credential "$BG_ID" --cluster="$CLUSTER_NAME" -o json 2>/dev/null |
		python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || echo "")

	if [ "$STATUS" = "issued" ] || [ "$STATUS" = "ready" ]; then
		break
	fi

	if [ "$STATUS" = "failed" ] || [ "$STATUS" = "expired" ]; then
		error "Break-glass credential $STATUS."
		exit 1
	fi

	info "  Status: ${STATUS:-pending} (${ELAPSED}s / ${MAX_WAIT}s)..."
	sleep "$INTERVAL"
	ELAPSED=$((ELAPSED + INTERVAL))
done

if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
	error "Timed out waiting for break-glass credential (${MAX_WAIT}s)."
	error "Check status: rosa describe break-glass-credential $BG_ID --cluster=$CLUSTER_NAME"
	exit 1
fi

info "Credential ready. Exporting kubeconfig..."

mkdir -p "$KUBECONFIG_DIR"
rosa describe break-glass-credential "$BG_ID" --cluster="$CLUSTER_NAME" --kubeconfig >"$KUBECONFIG_FILE" 2>/dev/null || {
	error "Failed to export kubeconfig."
	exit 1
}

export KUBECONFIG="$KUBECONFIG_FILE"

if oc whoami &>/dev/null; then
	success "Successfully authenticated as $(oc whoami)"
else
	warn "Kubeconfig exported but oc whoami failed. The credential may still be propagating."
fi

success "Break-glass kubeconfig saved to: $KUBECONFIG_FILE"
echo ""
info "To use this credential, run:"
info "  export KUBECONFIG=$KUBECONFIG_FILE"
echo ""
info "To revoke all break-glass credentials:"
info "  rosa revoke break-glass-credentials --cluster=$CLUSTER_NAME"

cd - >/dev/null
