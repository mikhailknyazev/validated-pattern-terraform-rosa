#!/usr/bin/env bash
# Bootstrap GitOps on a ROSA cluster with external auth enabled.
# Uses rosa break-glass-credential instead of HTPasswd admin.
#
# Usage:
#   bootstrap-external-auth.sh <cluster-name>
#
# Expects these environment variables (set by Makefile.cluster bootstrap target):
#   BOOTSTRAP_VALUES_FILE  — path to Helm values YAML
#   BOOTSTRAP_SCRIPT_PATH  — path to the GitOps bootstrap script
#   ACM_MODE               — hub|spoke|noacm (optional)
#   AWS_REGION             — AWS region
#
# Creates a short-lived break-glass credential, exports its kubeconfig,
# runs the GitOps bootstrap script, then revokes the credential on exit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

CLUSTER_NAME="${1:-}"
if [[ -z "$CLUSTER_NAME" ]]; then
	error "Usage: $0 <cluster-name>"
	exit 1
fi

check_required_tools rosa oc

BG_ID=""
BG_KUBECONFIG=""

cleanup_break_glass() {
	if [[ -n "$BG_KUBECONFIG" ]] && [[ -f "$BG_KUBECONFIG" ]]; then
		rm -f "$BG_KUBECONFIG"
	fi
	if [[ -n "$BG_ID" ]]; then
		info "Revoking break-glass credentials for cluster '$CLUSTER_NAME'..."
		rosa revoke break-glass-credentials --cluster="$CLUSTER_NAME" --yes 2>/dev/null || true
	fi
}
trap cleanup_break_glass EXIT

info "Creating break-glass credential for GitOps bootstrap (expiration=1h)..."

BG_OUTPUT=$(rosa create break-glass-credential --cluster="$CLUSTER_NAME" --expiration=1h 2>&1) || {
	error "Failed to create break-glass credential."
	error "$BG_OUTPUT"
	exit 1
}

BG_ID=$(echo "$BG_OUTPUT" | grep -oE '[0-9a-z]{32}' | head -1 || true)
if [[ -z "$BG_ID" ]]; then
	BG_ID=$(rosa list break-glass-credential --cluster="$CLUSTER_NAME" -o json 2>/dev/null |
		python3 -c 'import json,sys; creds=json.load(sys.stdin); print(creds[-1]["id"] if creds else "")' 2>/dev/null || true)
fi

if [[ -z "$BG_ID" ]]; then
	error "Could not determine break-glass credential ID."
	exit 1
fi

info "Break-glass credential ID: $BG_ID"
info "Waiting for credential to become ready..."

MAX_WAIT=600
ELAPSED=0
INTERVAL=10
while [[ "$ELAPSED" -lt "$MAX_WAIT" ]]; do
	STATUS=$(rosa describe break-glass-credential "$BG_ID" --cluster="$CLUSTER_NAME" -o json 2>/dev/null |
		python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || echo "")

	if [[ "$STATUS" == "issued" ]] || [[ "$STATUS" == "ready" ]]; then
		break
	fi

	if [[ "$STATUS" == "failed" ]] || [[ "$STATUS" == "expired" ]]; then
		error "Break-glass credential $STATUS."
		exit 1
	fi

	info "  Status: ${STATUS:-pending} (${ELAPSED}s / ${MAX_WAIT}s)..."
	sleep "$INTERVAL"
	ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ "$ELAPSED" -ge "$MAX_WAIT" ]]; then
	error "Timed out waiting for break-glass credential (${MAX_WAIT}s)."
	exit 1
fi

BG_KUBECONFIG=$(mktemp -t break-glass-kubeconfig.XXXXXX)
rosa describe break-glass-credential "$BG_ID" --cluster="$CLUSTER_NAME" --kubeconfig >"$BG_KUBECONFIG" 2>/dev/null || {
	error "Failed to export break-glass kubeconfig."
	exit 1
}

export KUBECONFIG="$BG_KUBECONFIG"
export BOOTSTRAP_KUBECONFIG="$BG_KUBECONFIG"

info "Break-glass credential ready. Verifying cluster access..."

MAX_LOGIN_WAIT=60
LOGIN_ELAPSED=0
while [[ "$LOGIN_ELAPSED" -lt "$MAX_LOGIN_WAIT" ]]; do
	if oc whoami &>/dev/null; then
		success "Authenticated as $(oc whoami)"
		break
	fi
	sleep 5
	LOGIN_ELAPSED=$((LOGIN_ELAPSED + 5))
done

if [[ "$LOGIN_ELAPSED" -ge "$MAX_LOGIN_WAIT" ]]; then
	error "Could not verify cluster access within ${MAX_LOGIN_WAIT}s."
	exit 1
fi

BOOTSTRAP_SCRIPT="${BOOTSTRAP_SCRIPT_PATH:-}"
if [[ -z "$BOOTSTRAP_SCRIPT" ]]; then
	error "BOOTSTRAP_SCRIPT_PATH is not set."
	exit 1
fi

info "Running GitOps bootstrap script: $BOOTSTRAP_SCRIPT"
set +e
bash "$BOOTSTRAP_SCRIPT"
GITOPS_RC=$?
set -e

if [[ "$GITOPS_RC" -ne 0 ]]; then
	error "GitOps bootstrap failed (exit $GITOPS_RC)."
fi

exit "$GITOPS_RC"
