<!--
Purpose: Complete Jenkins-on-EKS procedure for one device-code sign-in per run.
What this is not: This path does not create the Entra app, ROSA provider or ROSA RBAC.
Prerequisites: Jenkins Kubernetes plugin, external-auth-enabled ROSA HCP, public Entra client and routed TLS access.
Authoritative references:
- https://plugins.jenkins.io/kubernetes/
- https://github.com/int128/kubelogin/blob/v1.36.2/docs/setup.md
- https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code
-->

# Jenkins on EKS: Mode A

Use this path when a person can complete device authorization at the start of
every Jenkins run and no token state may cross job boundaries. The path requests
no `offline_access` scope and uses no AWS CLI, IAM policy, Secrets Manager
secret or KMS grant.

## Copy this path

Copy both directories without changing their relative placement:

```text
examples/ci-external-auth-device-code/common/
examples/ci-external-auth-device-code/jenkins-eks/mode-a/
```

`rosa-auth.sh` resolves `../../common` from its own location. Set
`ROSA_COMMON_DIR` only when packaging forces a different layout; a missing
library is a refusal, not a fallback.

## Prerequisites

1. Configure a ROSA HCP external-auth provider for Microsoft Entra ID. The
   Entra application must allow public-client device-code flows, and its client
   ID must be in the provider audience list. Follow the repository's
   [Entra external-auth guide](external-auth-entra-id.md).
2. Map a stable human claim and bind the complete subject returned by
   `oc auth whoami` to the minimum ROSA RBAC needed by this pipeline.
3. Give the Jenkins controller permission to create agent Pods in the selected
   EKS namespace. This is Kubernetes runner setup, not ROSA authorization.
4. Build an immutable agent image containing compatible `oc`, `kubectl`,
   `kubectl oidc-login` and GNU `timeout`. Do not download them during a job.
5. Permit HTTPS from the agent to Microsoft Entra and to the ROSA API. Supply
   the real cluster CA; insecure TLS is unsupported.

The sibling `pod.yaml` uses a non-root, read-only-root container with writable
`emptyDir` volumes for `/workspace` and `/tmp`. Replace its image placeholder
with an immutable digest. It intentionally has no cache-role ServiceAccount.

## Environment contract

Configure these values as reviewed Jenkins environment or credential bindings.
None is a bearer or client secret, but tenant and cluster identifiers can still
be sensitive inventory.

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
| `ROSA_AUTH_SKIP_KUBECONFIG_WRITE` | no | `1` uses the reviewed sibling template already mounted at `ROSA_KUBECONFIG` |
| `ROSA_COMMON_DIR` | no | Override for the expected `../../common` directory |

The static template is optional. The entry point parses its realized argument
and refuses it if `offline_access` is present.

## Jenkinsfile

The supplied Jenkinsfile is the complete CI definition for this path:

```groovy
// Covers: yamlFile, timeout, env:ROSA_AUTH_ROOT, env:ROSA_COMMON_DIR, env:ROSA_AUTH_TIMEOUT_SECONDS, env:TARGET_NAMESPACE, env:MANIFEST_DIR, env:DEPLOYMENT_NAME, env:HOME, --namespace, --filename, --timeout
// Does: Uses the fixed Mode A entry point for bounded identity, deployment, rollout and guaranteed cleanup.
// Why: One stage keeps the job-local ID-token cache available across every oc process without durable AWS custody.
// Change: Another path, namespace, manifest directory or rollout target changes security posture or deployment authority.
// Trap: Splitting authentication and deployment across Pods discards Mode A state and triggers another device-code sign-in.
// Evidence: https://www.jenkins.io/doc/book/pipeline/syntax/
pipeline {
  agent {
    kubernetes {
      yamlFile 'examples/ci-external-auth-device-code/jenkins-eks/mode-a/pod.yaml'
    }
  }
  options {
    timeout(time: 30, unit: 'MINUTES')
  }
  environment {
    ROSA_AUTH_ROOT = 'examples/ci-external-auth-device-code/jenkins-eks/mode-a'
    ROSA_COMMON_DIR = 'examples/ci-external-auth-device-code/common'
    ROSA_AUTH_TIMEOUT_SECONDS = '300'
    TARGET_NAMESPACE = '<target-namespace>'
    MANIFEST_DIR = '<reviewed-manifest-directory>'
    DEPLOYMENT_NAME = '<deployment-name>'
    HOME = '/tmp'
  }
  stages {
    stage('Authenticate and deploy') {
      steps {
        sh '''
          set +x
          umask 077
          "$ROSA_AUTH_ROOT/rosa-auth.sh" status
          "$ROSA_AUTH_ROOT/rosa-auth.sh" prepare
          echo "Complete the printed device-code step on a trusted browser."
          "$ROSA_AUTH_ROOT/rosa-auth.sh" whoami
          "$ROSA_AUTH_ROOT/rosa-auth.sh" run -- apply --namespace="$TARGET_NAMESPACE" --filename="$MANIFEST_DIR"
          "$ROSA_AUTH_ROOT/rosa-auth.sh" run -- rollout status "deployment/$DEPLOYMENT_NAME" --namespace="$TARGET_NAMESPACE" --timeout=4m
        '''
      }
    }
  }
  post {
    always {
      sh 'set +x; umask 077; "$ROSA_AUTH_ROOT/rosa-auth.sh" cleanup'
      deleteDir()
    }
  }
}
```

Replace all three deployment placeholders together. They delimit the namespace,
reviewed manifest tree and rollout object the job may change.

## Run and verify

Start the Jenkins build while the designated person is available. The
`whoami` command prints a Microsoft device URL and one-time code, then waits for
that person to finish in a trusted browser. The 300-second wrapper bound ends
the attempt rather than leaving the executor occupied indefinitely.

For a local rehearsal inside the prepared agent image:

```bash
# Covers: env:ROSA_AUTH_ROOT, env:ROSA_COMMON_DIR, env:ENTRA_TENANT_ID, env:ENTRA_PUBLIC_CLIENT_ID, env:ROSA_API_ENDPOINT, env:ROSA_CLUSTER_CA_B64, --namespace
# Does: Generates Mode A configuration, completes one bounded identity check and reads one permitted namespace.
# Why: The same entry point and environment used by Jenkins make the rehearsal representative of the job.
# Change: Another subject or namespace changes the identity or authorization being proved.
# Trap: Success proves this tenant and subject only; it does not prove another tenant's policy.
# Evidence: https://github.com/int128/kubelogin/blob/v1.36.2/docs/setup.md
export ROSA_AUTH_ROOT='examples/ci-external-auth-device-code/jenkins-eks/mode-a'
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

Expected signals:

- `prepare` prints `mode=A` and owner-only paths, never token content;
- `whoami` prints the exact mapped ROSA subject after browser completion;
- the namespace read succeeds only if ROSA RBAC permits that subject; and
- cleanup leaves `OIDC_TOKEN_CACHE_DIR` empty.

The owning APIs are different: Microsoft Entra sign-in logs establish the
human sign-in, `oc auth whoami` reads the ROSA API identity, and the Kubernetes
resource read establishes ROSA authorization.

## Cleanup and custody

Jenkins `post { always }` invokes cleanup and deletes the workspace. A static
agent must retain that block: Mode A's promise is job-local custody, not
ephemeral-agent custody. To abort manually, run `rosa-auth.sh cleanup` before
reusing the executor.

Mode A requests no refresh scope. A new job therefore starts a new device-code
flow; there is no AWS object to revoke or delete.

## Troubleshooting

| Signal | Meaning and action |
| --- | --- |
| `common library missing` | Copy `common/` beside `jenkins-eks/`, or set `ROSA_COMMON_DIR` to that exact directory |
| `Mode A kubeconfig must not request offline_access` | Mount the sibling Mode A template; do not edit a Mode B file at runtime |
| device-code wait exits after 300 seconds | The browser action did not finish inside the bound; start a fresh run with the person present |
| `x509` or unknown-authority error | Replace `ROSA_CLUSTER_CA_B64` with the cluster's real CA; never add an insecure flag |
| `Forbidden` after successful `whoami` | Authentication succeeded; bind the exact subject to narrower or correct ROSA RBAC |
| another prompt inside the same stage | Confirm every command uses the same `OIDC_TOKEN_CACHE_DIR`, HOME and Pod |

## Evidence boundary

`[tested]` The offline suite parses generated and static Mode A kubeconfigs,
proves no refresh scope, verifies missing-common and mismatched-template
refusals, and checks cleanup.

`[to confirm]` The corrected kit has not completed live end-to-end
authentication. Offline output begins with `evidence_class=offline_simulation`;
it does not establish Entra acceptance or ROSA RBAC in the reader's environment.
