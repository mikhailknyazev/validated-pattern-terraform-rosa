#!/usr/bin/env bash
# Purpose: Offline behavioral and distribution-shape tests for all four device-code paths.
# What this is not: This test contacts no Entra tenant, AWS account or ROSA API.
# Prerequisites: Bash 4+, Python with PyYAML, tar, gzip, base64, grep and the complete example tree.
# Authoritative references:
# - https://github.com/int128/kubelogin/blob/v1.36.2/docs/setup.md
# - https://yaml.org/spec/1.2.2/#73-flow-scalar-styles
# Covers: env:ROOT, env:AUTH_ROOT, env:WORKDIR, env:COMMON_AUTH, env:COMMON_CACHE, env:JENKINS_A, env:JENKINS_B, env:GITLAB_A, env:GITLAB_B, env:CUSTODY_BIN, env:FAKE_BIN, env:ROSA_KUBECONFIG, env:OIDC_TOKEN_CACHE_DIR, env:ENTRA_TENANT_ID, env:ENTRA_PUBLIC_CLIENT_ID, env:ROSA_API_ENDPOINT, env:ROSA_CLUSTER_CA_B64, env:ROSA_AUTH_SKIP_KUBECONFIG_WRITE, env:AWS_REGION, env:ROSA_B_SECRET_ID, env:ROSA_B_PERSIST, env:ROSA_B_FP_FILE, env:ROSA_COMMON_DIR, env:PATH, env:AWS_ARGV_LOG, --token-cache-storage, --grant-type, --oidc-extra-scope, --oidc-issuer-url, --oidc-client-id, --token-cache-dir, --secret-string, --help
# Does: Parses realized kubeconfigs and exercises fixed-mode entry points, distribution invariants, token packing and refusal paths.
# Why: Consumer-form assertions catch malformed YAML, mode drift, missing common code and credential argv leakage that source presence checks miss.
# Change: Removing a path, fixture or failure assertion can let one offered distribution diverge without detection.
# Trap: This offline simulation proves local orchestration only; it is not live authentication evidence.
# Evidence: Syntax-only: placeholder fixtures exercise the public files without remote contact.

set -euo pipefail

readonly EVIDENCE_CLASS="offline_simulation"
printf 'evidence_class=%s\n' "${EVIDENCE_CLASS}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTH_ROOT="${ROOT}/examples/ci-external-auth-device-code"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

pass() {
	printf 'ok: %s\n' "$*"
}

assert_realized_kubeconfig() {
	local path="$1" expected_scope="$2"
	python3 - "${path}" "${OIDC_TOKEN_CACHE_DIR}" "${expected_scope}" <<'PY'
import sys

import yaml

path, expected_cache_dir, expected_scope = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    kubeconfig = yaml.safe_load(stream)

cluster = kubeconfig["clusters"][0]["cluster"]
assert cluster["server"] == "https://api.cluster.example:443"
assert cluster["certificate-authority-data"] == "YWJjZGVm"
args = kubeconfig["users"][0]["user"]["exec"]["args"]
expected = {
    "--oidc-issuer-url=https://login.microsoftonline.com/<tenant-id>/v2.0",
    "--oidc-client-id=<public-client-id>",
    f"--token-cache-dir={expected_cache_dir}",
}
assert expected <= set(args), sorted(expected - set(args))
assert all("'" not in item and '"' not in item for item in args), args
assert ("--oidc-extra-scope=offline_access" in args) is (expected_scope == "present")
PY
}

COMMON_AUTH="${AUTH_ROOT}/common/rosa-auth-common.sh"
COMMON_CACHE="${AUTH_ROOT}/common/rosa-cache-common.sh"
JENKINS_A="${AUTH_ROOT}/jenkins-eks/mode-a/rosa-auth.sh"
JENKINS_B="${AUTH_ROOT}/jenkins-eks/mode-b/rosa-auth.sh"
GITLAB_A="${AUTH_ROOT}/gitlab-ec2/mode-a/rosa-auth.sh"
GITLAB_B="${AUTH_ROOT}/gitlab-ec2/mode-b/rosa-auth.sh"

# shellcheck source=examples/ci-external-auth-device-code/common/rosa-auth-common.sh
source "${COMMON_AUTH}"
# shellcheck source=examples/ci-external-auth-device-code/common/rosa-cache-common.sh
source "${COMMON_CACHE}"

cmp -s "${JENKINS_A}" "${GITLAB_A}" || fail "Mode A entry points differ"
cmp -s "${JENKINS_B}" "${GITLAB_B}" || fail "Mode B entry points differ"
[[ ! -x "${COMMON_AUTH}" && ! -x "${COMMON_CACHE}" ]] || fail "common libraries must not be executable"
for script in "${JENKINS_A}" "${JENKINS_B}" "${GITLAB_A}" "${GITLAB_B}"; do
	[[ -x "${script}" ]] || fail "specific entry point is not executable: ${script}"
done
[[ -z "$(bash -c 'source "$1"' _ "${COMMON_AUTH}")" ]] || fail "auth common emitted output while sourced"
[[ -z "$(bash -c 'source "$1"' _ "${COMMON_CACHE}")" ]] || fail "cache common emitted output while sourced"
pass "common libraries and byte-identical entry points"

if grep -RqiE 'source .*rosa-cache-common|aws[[:space:]]+(secretsmanager|sts)' \
	"${AUTH_ROOT}/jenkins-eks/mode-a" "${AUTH_ROOT}/gitlab-ec2/mode-a"; then
	fail "Mode A path carries durable-cache or AWS material"
fi
if find "${AUTH_ROOT}/jenkins-eks/mode-a" "${AUTH_ROOT}/gitlab-ec2/mode-a" \
	-type f -name '*iam*' -print -quit | grep -q .; then
	fail "Mode A path carries an IAM example"
fi
pass "Mode A paths exclude durable-cache and AWS material"

missing_common="${WORKDIR}/missing-common"
for script in "${JENKINS_A}" "${JENKINS_B}" "${GITLAB_A}" "${GITLAB_B}"; do
	if ROSA_COMMON_DIR="${missing_common}" "${script}" --help >"${WORKDIR}/missing.out" 2>&1; then
		fail "entry point accepted a missing common directory: ${script}"
	fi
	grep -q 'ROSA_COMMON_DIR' "${WORKDIR}/missing.out" || fail "missing-common refusal omitted override name"
	grep -q "${missing_common}" "${WORKDIR}/missing.out" || fail "missing-common refusal omitted resolved path"
done
pass "missing common directory refuses clearly"

export ROSA_KUBECONFIG="${WORKDIR}/kubeconfig"
export OIDC_TOKEN_CACHE_DIR="${WORKDIR}/tokens"
export ENTRA_TENANT_ID="<tenant-id>"
export ENTRA_PUBLIC_CLIENT_ID="<public-client-id>"
export ROSA_API_ENDPOINT="api.cluster.example"
export ROSA_CLUSTER_CA_B64="YWJjZGVm"
export AWS_REGION="<aws-region>"
export ROSA_B_SECRET_ID="<secret-id>"
export ROSA_B_PERSIST="auto"
export ROSA_B_FP_FILE="${WORKDIR}/mode-b.fingerprint"

rosa_auth_wipe_token_dir
rosa_auth_write_kubeconfig A
assert_realized_kubeconfig "${ROSA_KUBECONFIG}" absent
rosa_auth_write_kubeconfig B
assert_realized_kubeconfig "${ROSA_KUBECONFIG}" present
pass "generated kubeconfigs realize fixed scopes and quoted values"

python3 - \
	"${AUTH_ROOT}/jenkins-eks/mode-a/exec-kubeconfig.tmpl.yaml" \
	"${AUTH_ROOT}/jenkins-eks/mode-b/exec-kubeconfig.tmpl.yaml" \
	"${AUTH_ROOT}/gitlab-ec2/mode-a/exec-kubeconfig.tmpl.yaml" \
	"${AUTH_ROOT}/gitlab-ec2/mode-b/exec-kubeconfig.tmpl.yaml" <<'PY'
import sys

import yaml

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as stream:
        kubeconfig = yaml.safe_load(stream)
    args = kubeconfig["users"][0]["user"]["exec"]["args"]
    expected = "/mode-b/" in path
    assert ("--oidc-extra-scope=offline_access" in args) is expected, path
    assert "--token-cache-storage=disk" in args, path
    assert all("'" not in item and '"' not in item for item in args), path
PY
pass "all static templates parse with path-specific scope"

export ROSA_AUTH_SKIP_KUBECONFIG_WRITE=1
cp "${AUTH_ROOT}/jenkins-eks/mode-b/exec-kubeconfig.tmpl.yaml" "${ROSA_KUBECONFIG}"
if "${JENKINS_A}" prepare >/dev/null 2>&1; then
	fail "Mode A entry point accepted a refresh-capable static template"
fi
cp "${AUTH_ROOT}/jenkins-eks/mode-a/exec-kubeconfig.tmpl.yaml" "${ROSA_KUBECONFIG}"
if "${JENKINS_B}" prepare >/dev/null 2>&1; then
	fail "Mode B entry point accepted a static template without refresh scope"
fi
unset ROSA_AUTH_SKIP_KUBECONFIG_WRITE
pass "specific scripts enforce static-template scope"

rosa_auth_wipe_token_dir
printf '{"id_token":"x","refresh_token":"y"}\n' >"${OIDC_TOKEN_CACHE_DIR}/token.json"
chmod 600 "${OIDC_TOKEN_CACHE_DIR}/token.json"
packed="$(rosa_cache_pack)"
[[ -n "${packed}" && "${packed}" != *$'\n'* ]] || fail "packed archive is empty or wrapped"
rosa_auth_wipe_token_dir
rosa_cache_unpack "${packed}"
grep -q refresh_token "${OIDC_TOKEN_CACHE_DIR}/token.json" || fail "unpacked archive differs"
rosa_cache_remember_fp
rosa_cache_fp_unchanged || fail "unchanged archive fingerprint did not match"
printf 'changed\n' >>"${OIDC_TOKEN_CACHE_DIR}/token.json"
rosa_cache_fp_unchanged && fail "changed archive fingerprint matched" || true
pass "Mode B archive and fingerprint lifecycle"

CUSTODY_BIN="${WORKDIR}/custody-bin"
AWS_ARGV_LOG="${WORKDIR}/aws-argv.log"
mkdir -p "${CUSTODY_BIN}"
cat >"${CUSTODY_BIN}/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${AWS_ARGV_LOG:?}"
previous=""
for argument in "$@"; do
	printf '%s\n' "${argument}" >>"${AWS_ARGV_LOG}"
	if [[ "${previous}" == --secret-string && "${argument}" != file://* ]]; then
		exit 91
	fi
	previous="${argument}"
done
EOF
chmod +x "${CUSTODY_BIN}/aws"
export AWS_ARGV_LOG
: >"${AWS_ARGV_LOG}"
PATH="${CUSTODY_BIN}:${PATH}" rosa_cache_put || fail "owner-only file-reference write failed"
grep -Fx -- '--secret-string' "${AWS_ARGV_LOG}" >/dev/null || fail "Secrets Manager write option missing"
awk 'previous == "--secret-string" { found = index($0, "file://") == 1 } { previous = $0 } END { exit found ? 0 : 1 }' \
	"${AWS_ARGV_LOG}" || fail "token archive appeared directly on argv"
pass "Secrets Manager write keeps token material off argv"

FAKE_BIN="${WORKDIR}/fake-bin"
mkdir -p "${FAKE_BIN}"
cat >"${FAKE_BIN}/oc" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"${FAKE_BIN}/aws" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
chmod +x "${FAKE_BIN}/oc" "${FAKE_BIN}/aws"
rosa_auth_wipe_token_dir
printf 'refresh-cache-fixture\n' >"${OIDC_TOKEN_CACHE_DIR}/token.json"
rm -f "${ROSA_B_FP_FILE}"
if ! PATH="${FAKE_BIN}:${PATH}" "${JENKINS_B}" whoami 2>"${WORKDIR}/persist.stderr"; then
	fail "automatic persist failure changed successful oc result"
fi
grep -q 'automatic cache persistence failed' "${WORKDIR}/persist.stderr" || fail "automatic persist did not warn"
if PATH="${FAKE_BIN}:${PATH}" "${JENKINS_B}" persist >/dev/null 2>&1; then
	fail "explicit persist hid the AWS write failure"
fi
status_output="$(PATH="${FAKE_BIN}:${PATH}" "${JENKINS_B}" status)"
grep -Fx 'aws_caller=unobserved' <<<"${status_output}" >/dev/null || fail "failed caller read was not unobserved"
pass "persistence failure and caller observation remain three-state"

a_help="$("${JENKINS_A}" --help)"
b_help="$("${JENKINS_B}" --help)"
grep -q 'prepare|whoami|run|status|cleanup' <<<"${a_help}" || fail "Mode A usage omits its verbs"
grep -Eq '\b(seed|persist)\b' <<<"${a_help}" && fail "Mode A usage exposes Mode B verbs" || true
grep -q 'prepare|whoami|run|seed|persist|status|cleanup' <<<"${b_help}" || fail "Mode B usage omits its verbs"
pass "path-specific usage exposes only valid commands"

printf '\nall tests passed\n'
