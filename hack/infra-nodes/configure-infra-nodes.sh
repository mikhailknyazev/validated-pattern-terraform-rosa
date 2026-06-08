#!/usr/bin/env bash
# configure-infra-nodes.sh
#
# Post-deploy script for ROSA HCP clusters that have a dedicated infra machine pool
# with the node-role.kubernetes.io/infra label and NoSchedule taint.
#
# Run AFTER:
#   1. Cluster is up
#   2. Infra machine pool exists and nodes are Ready
#   3. You are logged into the cluster (oc whoami works)
#
# What this script does:
#   Phase 1 - DaemonSet tolerations: infra nodes need networking/storage/dns DaemonSets
#             to function. These are patched to tolerate the infra taint.
#   Phase 2 - Operator CRs: monitoring, ingress, and image-registry are moved to infra
#             nodes via their operator APIs (the correct way - operators reconcile these).
#
# What it does NOT move (intentionally left on worker nodes):
#   - openshift-console / console-operator
#   - openshift-service-ca / service-ca-operator
#   - openshift-gitops-operator
#   - openshift-insights / insights-operator
#   - openshift-kube-storage-version-migrator
#   - openshift-deployment-validation-operator
#   - ArgoCD instances
#
# Usage:
#   ./hack/infra-nodes/configure-infra-nodes.sh
#
# Dry-run (check only, no changes):
#   DRY_RUN=true ./hack/infra-nodes/configure-infra-nodes.sh

set -euo pipefail

DRY_RUN="${DRY_RUN:-false}"

INFRA_KEY="node-role.kubernetes.io/infra"

# ─── helpers ──────────────────────────────────────────────────────────────────

info() { echo "  [info]  $*"; }
ok() { echo "  [✓]     $*"; }
warn() { echo "  [warn]  $*" >&2; }
dry_run() { echo "  [dry]   (skipped) $*"; }

oc_apply() {
	if [[ "${DRY_RUN}" == "true" ]]; then
		dry_run "oc apply ..."
		return
	fi
	oc apply -f -
}

patch_ds_toleration() {
	local ns="$1"
	local name="$2"

	if ! oc get daemonset "${name}" -n "${ns}" &>/dev/null; then
		warn "DaemonSet ${ns}/${name} not found — skipping"
		return
	fi

	# Idempotent: skip if toleration already present
	if oc get daemonset "${name}" -n "${ns}" -o json |
		jq -e --arg key "${INFRA_KEY}" \
			'.spec.template.spec.tolerations // [] | map(.key) | contains([$key])' \
			>/dev/null 2>&1; then
		ok "DaemonSet ${ns}/${name} already has infra toleration"
		return
	fi

	if [[ "${DRY_RUN}" == "true" ]]; then
		dry_run "patch DaemonSet ${ns}/${name} — add infra toleration"
		return
	fi

	oc patch daemonset "${name}" -n "${ns}" --type=json -p="[{
    \"op\": \"add\",
    \"path\": \"/spec/template/spec/tolerations/-\",
    \"value\": {
      \"key\": \"${INFRA_KEY}\",
      \"effect\": \"NoSchedule\",
      \"operator\": \"Exists\"
    }
  }]"
	ok "Patched DaemonSet ${ns}/${name}"
}

# ─── preflight ────────────────────────────────────────────────────────────────

echo ""
echo "=== ROSA HCP Infra Node Configuration ==="
echo ""

if [[ "${DRY_RUN}" == "true" ]]; then
	echo "  DRY_RUN=true — no changes will be made"
	echo ""
fi

if ! oc whoami &>/dev/null; then
	echo "ERROR: Not logged into a cluster. Run 'oc login' first." >&2
	exit 1
fi

# Verify at least one infra node exists and is Ready
INFRA_NODES=$(oc get nodes -l "${INFRA_KEY}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${INFRA_NODES}" -eq 0 ]]; then
	echo "ERROR: No nodes found with label ${INFRA_KEY}." >&2
	echo "       Ensure the infra machine pool is provisioned and nodes are Ready." >&2
	exit 1
fi
info "Found ${INFRA_NODES} infra node(s)"
echo ""

# ─── Phase 1: DaemonSet tolerations ──────────────────────────────────────────
# Infra nodes must run these DaemonSets to remain functional (network, storage,
# dns, node management). Without toleration these DaemonSets won't schedule
# onto infra-tainted nodes, breaking node networking and storage entirely.

echo "--- Phase 1: DaemonSet tolerations ---"
echo ""

# Networking (critical — node is unusable without these)
patch_ds_toleration "openshift-ovn-kubernetes" "ovnkube-node"
patch_ds_toleration "openshift-multus" "multus"
patch_ds_toleration "openshift-multus" "multus-additional-cni-plugins"
patch_ds_toleration "openshift-multus" "network-metrics-daemon"

# DNS (critical)
patch_ds_toleration "openshift-dns" "dns-default"
patch_ds_toleration "openshift-dns" "node-resolver"

# Storage (needed for PVC workloads on infra nodes)
patch_ds_toleration "openshift-cluster-csi-drivers" "aws-ebs-csi-driver-node"

# Node management
patch_ds_toleration "openshift-cluster-node-tuning-operator" "tuned"
patch_ds_toleration "openshift-machine-config-operator" "kube-rbac-proxy-crio"

# Monitoring — node-level only (cluster-level moved via operator CR below)
patch_ds_toleration "openshift-monitoring" "node-exporter"

# Network diagnostics
patch_ds_toleration "openshift-network-diagnostics" "network-check-target"
patch_ds_toleration "openshift-network-operator" "iptables-alerter"

# kube-system (HCP control plane connectivity)
patch_ds_toleration "kube-system" "konnectivity-agent" || true
patch_ds_toleration "kube-system" "global-pull-secret-syncer" || true

# Image registry node agent
patch_ds_toleration "openshift-image-registry" "node-ca"

# Insights runtime extractor
patch_ds_toleration "openshift-insights" "insights-runtime-extractor" || true

echo ""

# ─── Phase 2: Operator CRs ───────────────────────────────────────────────────
# Move platform workloads to infra nodes via operator APIs. Direct pod patches
# would be reconciled away — operator CRs are the durable mechanism.

echo "--- Phase 2: Operator CRs ---"
echo ""

# ── Cluster Monitoring ──────────────────────────────────────────────────────
# Reference: https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/monitoring/configuring-the-monitoring-stack
info "Configuring cluster-monitoring-config (prometheus, alertmanager, thanos, etc.)..."
oc_apply <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    prometheusK8s:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
        - key: node-role.kubernetes.io/infra
          effect: NoSchedule
    alertmanagerMain:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
        - key: node-role.kubernetes.io/infra
          effect: NoSchedule
    thanosQuerier:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
        - key: node-role.kubernetes.io/infra
          effect: NoSchedule
    prometheusOperator:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
        - key: node-role.kubernetes.io/infra
          effect: NoSchedule
    prometheusOperatorAdmissionWebhook:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
        - key: node-role.kubernetes.io/infra
          effect: NoSchedule
    kubeStateMetrics:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
        - key: node-role.kubernetes.io/infra
          effect: NoSchedule
    metricsServer:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
        - key: node-role.kubernetes.io/infra
          effect: NoSchedule
    monitoringPlugin:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
        - key: node-role.kubernetes.io/infra
          effect: NoSchedule
    telemeterClient:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
        - key: node-role.kubernetes.io/infra
          effect: NoSchedule
    openshiftStateMetrics:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
        - key: node-role.kubernetes.io/infra
          effect: NoSchedule
EOF
[[ "${DRY_RUN}" != "true" ]] && ok "cluster-monitoring-config applied"

# ── Ingress ─────────────────────────────────────────────────────────────────
# Reference: https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/networking/configuring-ingress
info "Patching default IngressController nodePlacement..."
if [[ "${DRY_RUN}" == "true" ]]; then
	dry_run "patch IngressController default — nodePlacement to infra"
else
	oc patch ingresscontroller default -n openshift-ingress-operator --type=merge -p '{
    "spec": {
      "nodePlacement": {
        "nodeSelector": {
          "matchLabels": { "node-role.kubernetes.io/infra": "" }
        },
        "tolerations": [
          { "key": "node-role.kubernetes.io/infra", "effect": "NoSchedule" }
        ]
      }
    }
  }'
	ok "IngressController default patched"
fi

# ── Image Registry ───────────────────────────────────────────────────────────
info "Patching image registry config nodeSelector..."
if [[ "${DRY_RUN}" == "true" ]]; then
	dry_run "patch config.imageregistry/cluster — nodeSelector to infra"
else
	oc patch config.imageregistry.operator.openshift.io/cluster --type=merge -p '{
    "spec": {
      "nodeSelector": { "node-role.kubernetes.io/infra": "" },
      "tolerations": [
        { "key": "node-role.kubernetes.io/infra", "effect": "NoSchedule" }
      ]
    }
  }'
	ok "Image registry config patched"
fi

echo ""
echo "=== Done ==="
echo ""
echo "Workloads will reschedule onto infra nodes as operators reconcile."
echo "Monitor progress:"
echo "  oc get pods -n openshift-monitoring -o wide -w"
echo "  oc get pods -n openshift-ingress -o wide -w"
echo "  oc get pods -n openshift-image-registry -o wide -w"
echo ""
echo "Verify nothing is Pending on worker nodes that shouldn't be:"
echo "  oc get pods -A --field-selector=status.phase=Pending"
