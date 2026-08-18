#!/usr/bin/env bash
# E2E: fresh cluster → bootstrap-gitea → dev.private.sync → Argo verification
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PROFILE="${E2E_CLUSTER_PROFILE:-public}"
LOG_DIR="clusters/${PROFILE}/logs"
mkdir -p "${LOG_DIR}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="${LOG_DIR}/${TS}-e2e-private-gitops.log"
RESULT="${LOG_DIR}/e2e-private-gitops-result.txt"

exec > >(tee -a "$LOG") 2>&1
echo "$LOG" >"${LOG_DIR}/e2e-private-gitops.log.path"

log() { echo "=== $(date -u +%H:%M:%SZ) $* ==="; }

fail() {
	log "FAIL: $*"
	echo "FAIL: $*" >"$RESULT"
	exit 1
}

pass() {
	log "PASS: $*"
	echo "PASS: $*" >"$RESULT"
}

# Fresh cluster name for E2E — avoids IAM/VPC conflicts with prior destroy leftovers.
export TF_VAR_cluster_name="${E2E_CLUSTER_NAME:-cz-gitops-e2e}"
CLUSTER_NAME="${TF_VAR_cluster_name}"
log "E2E private GitOps start (profile=${PROFILE}, cluster=${CLUSTER_NAME})"

log "Step 1/5: apply infrastructure"
make "cluster.${PROFILE}.apply"

log "Step 2/5: bootstrap-gitea"
make "cluster.${PROFILE}.bootstrap-gitea"

log "Step 3/5: dev.private.preflight"
make dev.private.preflight "DEV_CLUSTER_NAME=${PROFILE}"

log "Step 4/5: dev.private.sync"
make dev.private.sync "DEV_CLUSTER_NAME=${PROFILE}"

log "Step 5/5: verify cluster + Argo"
make "cluster.${PROFILE}.login"

# Gitea
oc get pods -n gitea -o wide
oc wait --for=condition=Ready pod -l app.kubernetes.io/name=gitea -n gitea --timeout=300s

# Platform metadata
oc get configmap rosa-platform-metadata -n openshift-gitops

# Argo apps — refresh cluster-config if present
if oc get application cluster-config -n openshift-gitops >/dev/null 2>&1; then
	oc patch application cluster-config -n openshift-gitops --type merge \
		-p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' || true
	log "Waiting for cluster-config Application (best-effort 10m)..."
	oc wait --for=jsonpath='{.status.sync.status}'=Synced application/cluster-config -n openshift-gitops --timeout=600s ||
		log "WARN: cluster-config not Synced within timeout (check Degraded apps)"
fi

log "Argo Application summary:"
oc get applications.argoproj.io -n openshift-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null || true

env_file="clusters/${PROFILE}/private-gitops.env"
if [[ -f "${env_file}" ]]; then
	# shellcheck disable=SC1090,SC1091
	source "${env_file}"
	GITEA_CHARTS="$(curl -sf -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
		"http://127.0.0.1:13000/api/v1/packages/gitops/helm?limit=5" 2>/dev/null | jq -r 'length' 2>/dev/null || echo "?")"
else
	GITEA_CHARTS="?"
fi
log "Gitea helm packages (sample API): ${GITEA_CHARTS}"

pass "E2E private GitOps completed — see ${LOG}"
