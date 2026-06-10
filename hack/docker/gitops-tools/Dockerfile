# ROSA GitOps CMP repo-server tools image
#
# Multi-arch sidecar image for Argo CD ConfigManagementPlugin (avp-helm).
#
# CMP pipeline (cmp-plugin ConfigMap) requires:
#   discover: sh, find
#   init:     sh, helm  (helm dependency update)
#   generate: bash, helm, argocd-vault-plugin  (process substitution needs bash)
#
# UBI9 minimal already includes: bash, sh, curl, grep, sed, awk, core file utils.
# We add findutils + git; download oc, helm, argocd-vault-plugin.
#
# Build (single arch):
#   podman build -t rosa-gitops-tools:dev .
#
# Build multi-arch:
#   podman build --platform linux/amd64,linux/arm64 -t ghcr.io/<org>/gitops-tools:1.0.0 .

ARG BASE_IMAGE=registry.access.redhat.com/ubi9/ubi-minimal:9.5
FROM ${BASE_IMAGE}

ARG HELM_VERSION=3.16.4
ARG AVP_VERSION=1.18.1
ARG OCP_VERSION=4.16.40
ARG TARGETARCH

USER 0

# findutils: CMP discover runs `find . -name Chart.yaml`
# git: helm dependency update when charts declare git:// dependencies (fleet charts)
RUN microdnf install -y tar gzip shadow-utils jq findutils git \
	&& microdnf clean all \
	&& rm -rf /var/cache/yum

RUN set -eux; \
	case "${TARGETARCH}" in \
	amd64) ARCH=amd64; OC_TARBALL="openshift-client-linux-${OCP_VERSION}.tar.gz" ;; \
	arm64) ARCH=arm64; OC_TARBALL="openshift-client-linux-arm64-${OCP_VERSION}.tar.gz" ;; \
	*) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
	esac; \
	curl -fsSL "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/${OC_TARBALL}" \
	| tar -xz -C /usr/local/bin oc kubectl; \
	curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz" \
	| tar -xz -C /usr/local/bin --strip-components=1 "linux-${ARCH}/helm"; \
	curl -fsSL -o /usr/local/bin/argocd-vault-plugin \
		"https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v${AVP_VERSION}/argocd-vault-plugin_${AVP_VERSION}_linux_${ARCH}"; \
	chmod +x /usr/local/bin/oc /usr/local/bin/kubectl /usr/local/bin/helm /usr/local/bin/argocd-vault-plugin

RUN useradd -u 1001 -r -g 0 -d /home/default -s /sbin/nologin default \
	&& mkdir -p /home/default \
	&& chown -R 1001:0 /home/default

USER 1001

RUN oc version --client \
	&& kubectl version --client 2>/dev/null | head -1 \
	&& helm version --short \
	&& argocd-vault-plugin version \
	&& jq --version \
	&& find --version | head -1 \
	&& git --version
