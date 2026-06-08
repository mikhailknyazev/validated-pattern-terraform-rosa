# Infra Nodes — ROSA HCP vs ROSA Classic

Comparison of infra node topology, default workload placement, and what's required to configure a dedicated infra machine pool.

Audited against:
- **ROSA Classic** `classic-bench`, OCP 4.19, 3 infra nodes (`m5.xlarge`), `us-east-1`
- **ROSA HCP** `autonode`, OCP 4.19.30, 2 worker nodes (`m6g.xlarge`), `us-east-1`

---

## Background

OpenShift infra nodes serve two purposes:

1. **Subscription cost** — nodes labelled `node-role.kubernetes.io/infra` are classified as infrastructure nodes and do not consume ROSA worker node entitlements
2. **Workload isolation** — platform services (ingress, monitoring, registry) are moved off general-purpose worker nodes onto dedicated infra nodes

The standard infra node label and taint:

```
Label:  node-role.kubernetes.io/infra: ""
Taint:  node-role.kubernetes.io/infra:NoSchedule
```

---

## ROSA Classic

### Topology

Ships with **3 dedicated infra nodes** (`roles: infra,worker`) pre-provisioned and tainted. Hive (Red Hat's cluster provisioning layer) applies `cluster-monitoring-config`, `IngressController` nodePlacement, and image registry tolerations at cluster creation — no customer action required.

### How DaemonSets run on infra nodes

**Classic DaemonSets do NOT have a specific `node-role.kubernetes.io/infra` toleration.** Instead, the critical networking/storage/node-management DaemonSets use a wildcard toleration `{operator: Exists}` — tolerating ALL taints on ALL nodes:

| Namespace | DaemonSet | Toleration |
|---|---|---|
| openshift-ovn-kubernetes | ovnkube-node | `{operator: Exists}` (wildcard) |
| openshift-multus | multus | `{operator: Exists}` (wildcard) |
| openshift-multus | multus-additional-cni-plugins | `{operator: Exists}` (wildcard) |
| openshift-multus | network-metrics-daemon | `{operator: Exists}` (wildcard) |
| openshift-cluster-csi-drivers | aws-ebs-csi-driver-node | `{operator: Exists}` (wildcard) |
| openshift-cluster-node-tuning-operator | tuned | `{operator: Exists}` (wildcard) |
| openshift-dns | node-resolver | `{operator: Exists}` (wildcard) |
| openshift-machine-config-operator | machine-config-daemon | `{operator: Exists}` (wildcard) |
| openshift-monitoring | node-exporter | `{operator: Exists}` (wildcard) |
| openshift-network-diagnostics | network-check-target | `{operator: Exists}` (wildcard) |
| openshift-network-operator | iptables-alerter | `{operator: Exists}` (wildcard) |
| openshift-dns | dns-default | `{key: node-role.kubernetes.io/master, operator: Exists}` — master only, **not infra** |
| openshift-ingress-canary | ingress-canary | `{key: node-role.kubernetes.io/infra, operator: Exists}` — specific infra key |
| openshift-security | splunkforwarder-ds | runs on infra (ROSA Classic specific) |

> **Key insight**: The wildcard `{operator: Exists}` means these DaemonSets run on every node regardless of what taints are present. This is how they land on infra nodes without an explicit infra key. Our HCP script should match this pattern.

### Workloads on infra nodes (Classic)

Hive pre-configures infra placement via operator CRs:

**Operator CRs pre-applied by Hive:**

| Resource | Mechanism | nodeSelector | Toleration |
|---|---|---|---|
| `cluster-monitoring-config` ConfigMap | Hive-managed (`hive.openshift.io/managed: "true"`) | `node-role.kubernetes.io/infra: ""` | `{key: node-role.kubernetes.io/infra, effect: NoSchedule, operator: Exists}` |
| `IngressController default` | `.spec.nodePlacement` | `node-role.kubernetes.io/infra: ""` | `{key: node-role.kubernetes.io/infra, effect: NoSchedule, operator: Exists}` |
| `config.imageregistry.operator.openshift.io/cluster` | `.spec.tolerations` | **null** (no nodeSelector) | `{key: node-role.kubernetes.io/infra, effect: NoSchedule, operator: Exists}` |

**Workloads landing on infra nodes:**

| Namespace | Workload | Notes |
|---|---|---|
| openshift-monitoring | prometheus-k8s | Via cluster-monitoring-config |
| openshift-monitoring | alertmanager-main | Via cluster-monitoring-config |
| openshift-monitoring | thanos-querier | Via cluster-monitoring-config |
| openshift-monitoring | prometheus-operator | Via cluster-monitoring-config |
| openshift-monitoring | prometheus-operator-admission-webhook | Via cluster-monitoring-config |
| openshift-monitoring | kube-state-metrics | Via cluster-monitoring-config |
| openshift-monitoring | metrics-server | Via cluster-monitoring-config |
| openshift-monitoring | monitoring-plugin | Via cluster-monitoring-config |
| openshift-monitoring | telemeter-client | Via cluster-monitoring-config |
| openshift-monitoring | openshift-state-metrics | Via cluster-monitoring-config |
| openshift-monitoring | configure-alertmanager-operator | ROSA Classic managed service |
| openshift-ingress | router-default | Via IngressController nodePlacement |
| openshift-ingress-canary | ingress-canary | DaemonSet with specific infra toleration |
| openshift-image-registry | image-registry | Via imageregistry CR toleration (no nodeSelector) |
| openshift-addon-operator | addon-operator-manager | ROSA Classic add-on operator |
| openshift-addon-operator | addon-operator-webhooks | ROSA Classic add-on operator |
| openshift-custom-domains-operator | custom-domains-operator | ROSA Classic managed |
| openshift-deployment-validation-operator | deployment-validation-operator | On infra (no nodeSelector — lands here by capacity) |
| openshift-managed-node-metadata-operator | managed-node-metadata-operator | ROSA Classic managed |
| openshift-must-gather-operator | must-gather-operator-registry | ROSA Classic managed |
| openshift-ocm-agent-operator | ocm-agent | ROSA Classic managed |
| openshift-ocm-agent-operator | ocm-agent-operator | ROSA Classic managed |
| openshift-osd-metrics | osd-metrics-exporter | ROSA Classic managed |
| openshift-package-operator | package-operator-manager | ROSA Classic managed |
| openshift-rbac-permissions | rbac-permissions-operator | ROSA Classic managed |
| openshift-route-monitor-operator | blackbox-exporter | ROSA Classic managed |
| openshift-route-monitor-operator | route-monitor-operator | ROSA Classic managed |
| openshift-splunk-forwarder-operator | splunk-forwarder-operator | ROSA Classic SRE tooling |

> **Note on image registry**: Classic sets only a toleration (no nodeSelector) on the imageregistry CR. The pods land on infra nodes because of available capacity and affinity, not a hard selector. Our HCP script sets an explicit nodeSelector for more deterministic placement.

---

## ROSA HCP

### Topology

**No dedicated infra nodes out of the box.** All platform workloads land on the default worker machine pool. Configuring infra nodes is a customer responsibility.

### DaemonSets on a fresh HCP cluster

HCP DaemonSets do **not** use wildcard `{operator: Exists}` tolerations. They have narrower or no custom tolerations, so they would NOT schedule onto infra-tainted nodes without patching. Our script adds the specific infra key toleration.

| Namespace | DaemonSet | Notes |
|---|---|---|
| kube-system | konnectivity-agent | HCP control-plane connectivity |
| kube-system | global-pull-secret-syncer | |
| openshift-cluster-csi-drivers | aws-ebs-csi-driver-node | Node storage |
| openshift-cluster-node-tuning-operator | tuned | |
| openshift-dns | dns-default | **Critical** — node DNS |
| openshift-dns | node-resolver | |
| openshift-image-registry | node-ca | |
| openshift-insights | insights-runtime-extractor | |
| openshift-machine-config-operator | kube-rbac-proxy-crio | |
| openshift-monitoring | node-exporter | |
| openshift-multus | multus | **Critical** — node networking |
| openshift-multus | multus-additional-cni-plugins | |
| openshift-multus | network-metrics-daemon | |
| openshift-network-diagnostics | network-check-target | |
| openshift-network-operator | iptables-alerter | |
| openshift-ovn-kubernetes | ovnkube-node | **Critical** — node networking |

### How to configure infra nodes on HCP

See [`hack/infra-nodes/configure-infra-nodes.sh`](../hack/infra-nodes/configure-infra-nodes.sh).

**Prerequisites:**
- Infra machine pool provisioned with label `node-role.kubernetes.io/infra: ""` and taint `node-role.kubernetes.io/infra:NoSchedule`
- Nodes are `Ready`

```bash
# Dry run first
DRY_RUN=true ./hack/infra-nodes/configure-infra-nodes.sh

# Apply
./hack/infra-nodes/configure-infra-nodes.sh
```

---

## HCP vs Classic delta

| Aspect | ROSA Classic | ROSA HCP |
|---|---|---|
| Infra nodes included by default | ✅ 3 nodes pre-provisioned | ❌ Customer adds infra pool |
| Infra taint applied by default | ✅ `NoSchedule` pre-applied by Hive | ❌ Customer applies via machine pool config |
| Platform workloads pre-configured for infra | ✅ Hive applies operator CRs at cluster creation | ❌ Customer runs configure-infra-nodes.sh post-deploy |
| DaemonSet toleration strategy | `{operator: Exists}` wildcard on all critical DaemonSets | Specific `node-role.kubernetes.io/infra` key added by script |
| `cluster-monitoring-config` | Hive-managed, infra placement pre-set | Customer-applied, same content |
| `IngressController` nodePlacement | Hive-set with infra nodeSelector + `operator: Exists` toleration | Script-set with infra nodeSelector + `effect: NoSchedule` toleration |
| Image registry CR | Toleration only (`operator: Exists`), no nodeSelector | Script sets explicit nodeSelector + toleration |
| ROSA-Classic-specific infra workloads | addon-operator, ocm-agent, osd-metrics, route-monitor, splunk-forwarder, backplane tooling | ❌ Not present in HCP |
| Machine config daemon on infra nodes | ✅ (wildcard toleration) | ❌ `machine-config-daemon` does not exist in HCP |
| Subscription cost benefit | ✅ Infra nodes excluded from worker entitlements | ✅ Same (label-based) |

### Notable differences

**`machine-config-daemon` does not exist in HCP** — this is managed by the hosted control plane. No equivalent DaemonSet to patch.

**Classic uses `operator: Exists` (wildcard); our HCP script uses `key: node-role.kubernetes.io/infra`** — both work, but wildcard is broader. Consider whether HCP DaemonSets should also use wildcard if additional taints are planned (e.g., spot instance taints).

**Image registry placement** — Classic relies on capacity/affinity to land registry pods on infra nodes (no nodeSelector). Our HCP script is more explicit with nodeSelector. Both approaches work; explicit is safer for HCP where infra nodes are optional and may not always exist.

---

## Audit commands

```bash
# Pods without infra toleration (what would go Pending after NoSchedule taint)
# Note: does not catch wildcard {operator: Exists} tolerations
oc get pods -A -o json | jq -r '
  .items[] |
  select(.status.phase == "Running" or .status.phase == "Pending") |
  select(
    ((.spec.tolerations // []) | map(.key) | contains(["node-role.kubernetes.io/infra"])) | not
  ) |
  [.metadata.namespace, .metadata.name, (.spec.nodeName // "unscheduled")] | @tsv
' | sort | column -t

# DaemonSets with wildcard {operator: Exists} toleration (Classic pattern)
oc get ds -A -o json | jq -r '
  .items[] |
  select(
    (.spec.template.spec.tolerations // []) |
    any(. | (.operator == "Exists") and (.key == null or .key == ""))
  ) |
  [.metadata.namespace, .metadata.name] | @tsv
' | sort | column -t

# All pods currently running on infra nodes
for node in $(oc get nodes -l node-role.kubernetes.io/infra -o name | cut -d/ -f2); do
  echo "=== $node ==="
  oc get pods -A --field-selector "spec.nodeName=${node}" -o wide --no-headers
done

# Verify infra nodes and taints
oc get nodes -l node-role.kubernetes.io/infra
oc describe nodes -l node-role.kubernetes.io/infra | grep -E "^Name:|Taints:"

# Check operator CR infra config
oc get configmap cluster-monitoring-config -n openshift-monitoring -o yaml
oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.spec.nodePlacement}'
oc get config.imageregistry.operator.openshift.io/cluster -o jsonpath='{.spec.nodeSelector} {.spec.tolerations}'
```
