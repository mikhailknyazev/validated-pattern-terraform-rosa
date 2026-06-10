#!/usr/bin/env bash
# Build and smoke-test the ROSA GitOps CMP tools image with podman.
#
# Usage (from repo root or this directory):
#   ./hack/docker/gitops-tools/test-image.sh
#
# Optional env:
#   IMAGE=localhost/rosa-gitops-tools:test
#   BASE_IMAGE=registry.access.redhat.com/ubi9/ubi-minimal:9.5
#   OCP_VERSION=4.16.40
#   PLATFORM=linux/arm64   # or linux/amd64; defaults to host arch
#   CONTAINER_CMD=podman   # or docker

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_CMD="${CONTAINER_CMD:-podman}"
IMAGE="${IMAGE:-localhost/rosa-gitops-tools:test}"

if ! command -v "${CONTAINER_CMD}" >/dev/null 2>&1; then
	echo "error: ${CONTAINER_CMD} not found. Install podman or set CONTAINER_CMD=docker." >&2
	exit 1
fi

HOST_ARCH="$(uname -m)"
case "${HOST_ARCH}" in
x86_64) DEFAULT_PLATFORM="linux/amd64" ;;
aarch64 | arm64) DEFAULT_PLATFORM="linux/arm64" ;;
*)
	echo "error: unsupported host arch: ${HOST_ARCH}" >&2
	exit 1
	;;
esac
PLATFORM="${PLATFORM:-${DEFAULT_PLATFORM}}"

BASE_IMAGE="${BASE_IMAGE:-registry.access.redhat.com/ubi9/ubi-minimal:9.5}"
OCP_VERSION="${OCP_VERSION:-4.16.40}"

echo "==> Building ${IMAGE} (platform=${PLATFORM}, base=${BASE_IMAGE}, oc=${OCP_VERSION})"
"${CONTAINER_CMD}" build \
	--platform "${PLATFORM}" \
	--build-arg "BASE_IMAGE=${BASE_IMAGE}" \
	--build-arg "OCP_VERSION=${OCP_VERSION}" \
	-t "${IMAGE}" \
	"${SCRIPT_DIR}"

verify() {
	local cmd="$1"
	echo "==> ${cmd}"
	"${CONTAINER_CMD}" run --rm --platform "${PLATFORM}" "${IMAGE}" ${cmd}
}

verify "oc version --client"
verify "helm version --short"
verify "argocd-vault-plugin version"
verify "jq --version"
verify "find --version"
verify "git --version"

echo "==> CMP plugin discover (same command as avp-helm sidecar)"
"${CONTAINER_CMD}" run --rm --platform "${PLATFORM}" "${IMAGE}" \
	bash -c 'set -euo pipefail
mkdir -p /tmp/chart/templates
cat > /tmp/chart/Chart.yaml <<EOF
apiVersion: v2
name: smoke
version: 0.1.0
EOF
cat > /tmp/chart/values.yaml <<EOF
enabled: true
EOF
cd /tmp/chart
sh -c "find . -name '\''Chart.yaml'\'' && find . -name '\''values.yaml'\''"
'
"${CONTAINER_CMD}" run --rm --platform "${PLATFORM}" "${IMAGE}" \
	bash -c 'set -euo pipefail
mkdir -p /tmp/chart/templates
cat > /tmp/chart/Chart.yaml <<EOF
apiVersion: v2
name: smoke
version: 0.1.0
EOF
cat > /tmp/chart/templates/cm.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: smoke
data:
  hello: world
EOF
cd /tmp/chart
helm template smoke . | grep -q "kind: ConfigMap"
'

echo "==> AVP passthrough (AVP_TYPE set like in-cluster awssecretsmanager config)"
"${CONTAINER_CMD}" run --rm --platform "${PLATFORM}" "${IMAGE}" \
	bash -c 'set -euo pipefail
printf "%s\n" "apiVersion: v1" "kind: ConfigMap" "metadata:" "  name: smoke" "data:" "  hello: world" \
  | AVP_TYPE=awssecretsmanager AWS_REGION=us-east-1 argocd-vault-plugin generate - \
  | grep -q "hello: world"
'

echo "==> OK: ${IMAGE} ready for cluster-bootstrap defaultImage"
