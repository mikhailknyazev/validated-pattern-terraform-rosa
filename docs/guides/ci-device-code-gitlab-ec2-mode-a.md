<!--
Purpose: Complete GitLab-on-EC2 procedure for one device-code sign-in per job.
What this is not: This path creates no Entra, ROSA, IAM or RBAC object.
Prerequisites: GitLab Runner on EC2, external-auth-enabled ROSA HCP, a public Entra client and routed TLS access.
Authoritative references:
- https://docs.gitlab.com/runner/install/
- https://github.com/int128/kubelogin/blob/v1.36.2/docs/setup.md
- https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code
-->

# GitLab on EC2: Mode A

Use this path when a person can complete device authorization at the start of
every GitLab job and no token state may cross job boundaries. It requests no
`offline_access` scope and needs no AWS CLI, instance-profile permission,
Secrets Manager secret or KMS grant.

## Copy this path

Copy both directories without changing their relative placement:

```text
examples/ci-external-auth-device-code/common/
examples/ci-external-auth-device-code/gitlab-ec2/mode-a/
```

`rosa-auth.sh` resolves `../../common` from its location. Set
`ROSA_COMMON_DIR` only when packaging requires another layout. A missing common
library is a refusal, not a fallback.

## Prerequisites and runner identity

1. Configure a ROSA HCP external-auth provider for Microsoft Entra ID. Allow
   public-client device-code flows, include the client ID in the provider
   audience list, map a stable human claim and grant the realized subject only
   the ROSA RBAC the job needs. Follow the repository's
   [Entra external-auth guide](external-auth-entra-id.md).
2. Install GitLab Runner on a dedicated EC2 instance. Its AWS instance profile
   needs no cache permission for this path; do not add one merely because the
   runner is on AWS.
3. Build an immutable runner image containing compatible `oc`, `kubectl`,
   `kubectl oidc-login` and GNU `timeout`. Do not download executables during a
   job.
4. Permit HTTPS from the runner to Microsoft Entra and the ROSA API. Supply the
   real cluster CA; insecure TLS is unsupported.
5. Use a shell executor or another executor that preserves one filesystem for
   the complete job. Splitting the commands across jobs loses Mode A state.

## Environment contract

Configure these values as protected GitLab CI/CD variables. They are inventory,
not bearer credentials, but tenant and cluster identifiers can still be
sensitive.

| Variable | Required | Meaning |
| --- | --- | --- |
| `ENTRA_TENANT_ID` | yes | Tenant used in the v2 issuer URL |
| `ENTRA_PUBLIC_CLIENT_ID` | yes | Public client accepted by the ROSA provider |
| `ROSA_API_ENDPOINT` | yes | ROSA API DNS name without `https://` |
| `ROSA_CLUSTER_CA_B64` | yes | Base64 cluster CA |
| `ROSA_KUBECONFIG` | no | Generated file; default `/tmp/rosa-exec-kubeconfig` |
| `OIDC_TOKEN_CACHE_DIR` | no | Job-local state; default `/tmp/rosa-oidc-cache` |
| `ROSA_AUTH_TIMEOUT_SECONDS` | no | Positive integer; default `300` |
| `ROSA_HOME` | no | HOME for `oc`; default `/tmp` |
| `ROSA_AUTH_SKIP_KUBECONFIG_WRITE` | no | `1` uses the reviewed sibling template already at `ROSA_KUBECONFIG` |
| `ROSA_COMMON_DIR` | no | Override for the expected `../../common` directory |

The entry point parses a static template's realized arguments and refuses it if
`offline_access` is present.

## GitLab CI file

The supplied `.gitlab-ci.yml` is the complete job for this path:

```yaml
# Covers: variables, ROSA_AUTH_ROOT, ROSA_COMMON_DIR, ROSA_AUTH_TIMEOUT_SECONDS, TARGET_NAMESPACE, MANIFEST_DIR, DEPLOYMENT_NAME, HOME, stages, rosa-deploy, stage, timeout, script, after_script, --namespace, --filename, --timeout
# Does: Uses the fixed Mode A entry point for bounded identity, deployment, rollout and guaranteed cleanup.
# Why: One job keeps the job-local ID-token cache available across every oc process without durable AWS custody.
# Change: Another path, namespace, manifest directory or rollout target changes security posture or deployment authority.
# Trap: Splitting authentication and deployment across jobs discards Mode A state and triggers another device-code sign-in.
# Evidence: https://docs.gitlab.com/ci/yaml/
variables:
  ROSA_AUTH_ROOT: "examples/ci-external-auth-device-code/gitlab-ec2/mode-a"
  ROSA_COMMON_DIR: "examples/ci-external-auth-device-code/common"
  ROSA_AUTH_TIMEOUT_SECONDS: "300"
  TARGET_NAMESPACE: "<target-namespace>"
  MANIFEST_DIR: "<reviewed-manifest-directory>"
  DEPLOYMENT_NAME: "<deployment-name>"
  HOME: "/tmp"

stages:
  - deploy

rosa-deploy:
  stage: deploy
  timeout: 15m
  script:
    - set +x
    - umask 077
    - '"${ROSA_AUTH_ROOT}/rosa-auth.sh" status'
    - '"${ROSA_AUTH_ROOT}/rosa-auth.sh" prepare'
    - 'echo "Complete the printed device-code step on a trusted browser."'
    - '"${ROSA_AUTH_ROOT}/rosa-auth.sh" whoami'
    - '"${ROSA_AUTH_ROOT}/rosa-auth.sh" run -- apply --namespace="${TARGET_NAMESPACE}" --filename="${MANIFEST_DIR}"'
    - '"${ROSA_AUTH_ROOT}/rosa-auth.sh" run -- rollout status "deployment/${DEPLOYMENT_NAME}" --namespace="${TARGET_NAMESPACE}" --timeout=4m'
  after_script:
    - 'set +x; umask 077; "${ROSA_AUTH_ROOT}/rosa-auth.sh" cleanup'
  # Never place OIDC_TOKEN_CACHE_DIR in cache: or artifacts:.
```

Replace all three deployment placeholders together. They delimit the namespace,
reviewed manifest tree and rollout object the job may change.

## Run and verify

Run the job while the designated person is available. `whoami` prints a device
URL and one-time code, then waits for completion in a trusted browser. The
300-second wrapper bound ends the attempt rather than occupying the runner
indefinitely.

For a local rehearsal on the runner:

```bash
# Covers: env:ROSA_AUTH_ROOT, env:ROSA_COMMON_DIR, env:ENTRA_TENANT_ID, env:ENTRA_PUBLIC_CLIENT_ID, env:ROSA_API_ENDPOINT, env:ROSA_CLUSTER_CA_B64, --namespace
# Does: Generates Mode A configuration, completes one bounded identity check and reads one permitted namespace.
# Why: The same entry point and environment used by GitLab make the rehearsal representative of the job.
# Change: Another subject or namespace changes the identity or authorization being proved.
# Trap: Success proves this tenant and subject only; it does not prove another tenant's policy.
# Evidence: https://github.com/int128/kubelogin/blob/v1.36.2/docs/setup.md
export ROSA_AUTH_ROOT='examples/ci-external-auth-device-code/gitlab-ec2/mode-a'
export ROSA_COMMON_DIR='examples/ci-external-auth-device-code/common'
export ENTRA_TENANT_ID='<tenant-id>'
export ENTRA_PUBLIC_CLIENT_ID='<public-client-id>'
export ROSA_API_ENDPOINT='api.<cluster-domain>'
export ROSA_CLUSTER_CA_B64='<base64-cluster-ca>'

"${ROSA_AUTH_ROOT}/rosa-auth.sh" prepare
"${ROSA_AUTH_ROOT}/rosa-auth.sh" whoami
"${ROSA_AUTH_ROOT}/rosa-auth.sh" run -- get namespace '<target-namespace>'
"${ROSA_AUTH_ROOT}/rosa-auth.sh" cleanup
```

Expected signals are `mode=A` from `prepare`, the complete mapped subject from
`whoami`, a permitted Kubernetes read and an empty local token directory after
cleanup. Entra sign-in logs establish the human sign-in; `oc auth whoami` reads
the ROSA identity; the Kubernetes resource read establishes authorization.

## Cleanup and custody

`after_script` runs cleanup on success and failure. Do not configure GitLab
`cache:` or `artifacts:` for the token directory. Mode A requests no refresh
scope, so every new job starts a new device-code flow and has no AWS object to
revoke or delete.

## Troubleshooting

| Signal | Meaning and action |
| --- | --- |
| `common library missing` | Copy `common/` beside `gitlab-ec2/`, or set `ROSA_COMMON_DIR` to that exact directory |
| `Mode A kubeconfig must not request offline_access` | Use the sibling Mode A template without adding refresh scope |
| device-code wait exits after 300 seconds | Start a fresh job with the person available; do not raise an unbounded wait |
| `x509` or unknown-authority error | Replace `ROSA_CLUSTER_CA_B64` with the cluster's real CA |
| `Forbidden` after successful `whoami` | Authentication succeeded; fix RBAC for the exact subject |
| another prompt in the same job | Confirm all commands share `OIDC_TOKEN_CACHE_DIR`, HOME and executor filesystem |

## Evidence boundary

`[tested]` The offline suite parses generated and static Mode A kubeconfigs,
proves the absence of refresh scope, verifies missing-common and template-scope
refusals, and checks cleanup.

`[to confirm]` The kit has not completed live end-to-end authentication.
Offline output begins with `evidence_class=offline_simulation` and does not
establish Entra acceptance or ROSA RBAC in the reader's environment.
