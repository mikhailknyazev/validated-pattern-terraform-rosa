<!--
Purpose: Complete Jenkins-on-EKS procedure for a Secrets Manager-backed device-code session.
What this is not: This path does not create the Entra app, ROSA provider or ROSA RBAC.
Prerequisites: Jenkins Kubernetes plugin, external-auth-enabled ROSA HCP, public Entra client, IRSA and routed TLS access.
Authoritative references:
- https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
- https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html
- https://github.com/int128/kubelogin/blob/v1.36.2/docs/setup.md
-->

# Jenkins on EKS: Mode B

Use this path when one accountable person seeds a refresh-capable session and
Jenkins jobs restore it from AWS Secrets Manager. EKS supplies temporary AWS
credentials through IAM roles for service accounts (IRSA); Microsoft Entra and
ROSA still authenticate and authorize the person.

## Copy this path

Copy both directories without changing their relative placement:

```text
examples/ci-external-auth-device-code/common/
examples/ci-external-auth-device-code/jenkins-eks/mode-b/
```

The entry point sources both files in `common/`. It refuses if either is absent.
`ROSA_COMMON_DIR` is available only for packaging that cannot retain the
documented relative layout.

## Prerequisites

1. Configure a ROSA HCP external-auth provider for Microsoft Entra ID. Enable
   public-client device-code flows, place the client ID in the provider audience
   list, map a stable human claim and plan minimum RBAC for the realized subject.
   Follow the repository's [Entra external-auth guide](external-auth-entra-id.md).
2. Build an immutable agent image containing compatible `oc`, `kubectl`,
   `kubectl oidc-login`, GNU `timeout`, AWS CLI, tar, gzip and base64.
3. Permit HTTPS from the agent to Microsoft Entra, the ROSA API, AWS STS,
   Secrets Manager and the selected KMS endpoint. Supply the real ROSA CA.
4. Create one customer-managed KMS key and one Secrets Manager secret for this
   pipeline. Do not share the object between people or unrelated jobs.
5. Create one IRSA role using the sibling permission and trust policies. Limit
   the trust policy to the exact EKS namespace and ServiceAccount.

## Create the AWS custody objects

Replace placeholders in `iam-policy.json` and `irsa-trust-policy.json`, then
create the sentinel secret. The sentinel is not a token and the script refuses
to unpack it before a successful seed.

```bash
# Covers: --region, --name, --kms-key-id, --secret-string
# Does: Creates one KMS-encrypted Secrets Manager object in an explicit pre-seed state.
# Why: A named sentinel distinguishes an unused object from a malformed or empty token archive.
# Change: Another region, key or name selects a different custody and IAM boundary.
# Trap: Never place real token material in this command or any process argument.
# Evidence: https://docs.aws.amazon.com/cli/latest/reference/secretsmanager/create-secret.html
aws secretsmanager create-secret \
  --region '<aws-region>' \
  --name '<secret-name>' \
  --kms-key-id '<kms-key-arn>' \
  --secret-string 'pending-seed'
```

Create the role from the reviewed files and attach only its inline cache policy:

```bash
# Covers: --role-name, --assume-role-policy-document, --policy-name, --policy-document, --filename
# Does: Creates one IRSA role, attaches exact secret/KMS actions and binds its Kubernetes ServiceAccount.
# Why: The Pod needs temporary AWS credentials without access keys in Jenkins or the container image.
# Change: Another role, policy or manifest changes who can retrieve and replace the human session.
# Trap: Apply placeholder-expanded copies from an owner-only directory; the public examples are not account-ready.
# Evidence: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
aws iam create-role \
  --role-name '<ci-role-name>' \
  --assume-role-policy-document 'file://irsa-trust-policy.json'
aws iam put-role-policy \
  --role-name '<ci-role-name>' \
  --policy-name '<cache-policy-name>' \
  --policy-document 'file://iam-policy.json'
kubectl apply --filename serviceaccount.yaml
```

The policy scopes `GetSecretValue`, `PutSecretValue` and `DescribeSecret` to one
secret ARN, and KMS `Decrypt`, `Encrypt` and `GenerateDataKey` to one key ARN.
The sibling `pod.yaml` names the IRSA ServiceAccount and uses an `emptyDir` for
the restored local archive.

## Environment contract

| Variable | Required | Meaning |
| --- | --- | --- |
| `ENTRA_TENANT_ID` | yes | Tenant used in the v2 issuer URL |
| `ENTRA_PUBLIC_CLIENT_ID` | yes | Public client accepted by the ROSA provider |
| `ROSA_API_ENDPOINT` | yes | ROSA API DNS name without `https://` |
| `ROSA_CLUSTER_CA_B64` | yes | Base64 cluster CA |
| `AWS_REGION` | yes | Region containing the secret |
| `ROSA_B_SECRET_ID` | yes | Secret name or ARN |
| `ROSA_B_PERSIST` | no | `auto` (default) or `never` |
| `ROSA_KUBECONFIG` | no | Generated file; default `/tmp/rosa-exec-kubeconfig` |
| `OIDC_TOKEN_CACHE_DIR` | no | Restored local state; default `/tmp/rosa-oidc-cache` |
| `ROSA_AUTH_TIMEOUT_SECONDS` | no | Positive integer; default `300` |
| `ROSA_HOME` | no | HOME for `oc`; default `/tmp` |
| `ROSA_AUTH_SKIP_KUBECONFIG_WRITE` | no | `1` uses the reviewed sibling template already at `ROSA_KUBECONFIG` |
| `ROSA_COMMON_DIR` | no | Override for the expected `../../common` directory |

The entry point refuses a static template that omits `offline_access`. The
packed base64 archive is measured before every write; values above the Secrets
Manager 65,536-byte string limit are refused rather than truncated.

!!! danger "Human identity custody"
    Anyone who can run a job with this IRSA role can act as the seeded person
    on the cluster, and the cluster audit trail will show that person. Restrict
    who can modify Jenkins jobs, use this ServiceAccount, assume the role, read
    or replace the secret, and bind the resulting ROSA subject. Use a dedicated,
    accountable person; do not describe the session as a workload identity.

## Seed the session

Run seed once from a trusted Jenkins agent using the same ServiceAccount and
environment as the unattended job. Keep the process running while the person
uses the printed URL and code in a trusted browser.

```bash
# Covers: env:ROSA_AUTH_ROOT, env:ROSA_COMMON_DIR, env:AWS_REGION, env:ROSA_B_SECRET_ID, env:ENTRA_TENANT_ID, env:ENTRA_PUBLIC_CLIENT_ID, env:ROSA_API_ENDPOINT, env:ROSA_CLUSTER_CA_B64
# Does: Completes one bounded device-code sign-in and persists the resulting archive only after whoami succeeds.
# Why: Seeding through the production role and path proves both the person-to-ROSA mapping and AWS custody route.
# Change: Another tenant, client, API or secret selects a different identity or authority boundary.
# Trap: Later cluster actions are attributed to this person; never seed a shared or unaccountable user.
# Evidence: https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code
export ROSA_AUTH_ROOT='examples/ci-external-auth-device-code/jenkins-eks/mode-b'
export ROSA_COMMON_DIR='examples/ci-external-auth-device-code/common'
export AWS_REGION='<aws-region>'
export ROSA_B_SECRET_ID='<secret-name-or-arn>'
export ENTRA_TENANT_ID='<tenant-id>'
export ENTRA_PUBLIC_CLIENT_ID='<public-client-id>'
export ROSA_API_ENDPOINT='api.<cluster-domain>'
export ROSA_CLUSTER_CA_B64='<base64-cluster-ca>'

"${ROSA_AUTH_ROOT}/rosa-auth.sh" seed
"${ROSA_AUTH_ROOT}/rosa-auth.sh" cleanup
```

Bind the complete subject printed by `oc auth whoami` to minimum ROSA RBAC.

## Jenkinsfile

The supplied Jenkinsfile is the complete CI definition for this path:

```groovy
// Covers: yamlFile, disableConcurrentBuilds, timeout, env:ROSA_AUTH_ROOT, env:ROSA_COMMON_DIR, env:ROSA_B_PERSIST, env:ROSA_AUTH_TIMEOUT_SECONDS, env:TARGET_NAMESPACE, env:MANIFEST_DIR, env:DEPLOYMENT_NAME, env:HOME, --namespace, --filename, --timeout
// Does: Uses the fixed Mode B entry point for restore, bounded identity, deployment, persistence and guaranteed local cleanup.
// Why: Serialization prevents two jobs from overwriting one rotated human refresh session with stale state.
// Change: Another path, namespace, manifest directory or rollout target changes custody or deployment authority.
// Trap: Removing serialization creates last-writer-wins token rollback; archiving /tmp exports reusable human credentials.
// Evidence: https://www.jenkins.io/doc/book/pipeline/syntax/
pipeline {
  agent {
    kubernetes {
      yamlFile 'examples/ci-external-auth-device-code/jenkins-eks/mode-b/pod.yaml'
    }
  }
  options {
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
  }
  environment {
    ROSA_AUTH_ROOT = 'examples/ci-external-auth-device-code/jenkins-eks/mode-b'
    ROSA_COMMON_DIR = 'examples/ci-external-auth-device-code/common'
    ROSA_B_PERSIST = 'auto'
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

Store the environment values in Jenkins bindings appropriate to your
organisation. Do not place the token directory in a stash, artifact or cache.

## Run and verify

Expected signals from a normal unattended build:

- `status` prints `mode=B` and an observed AWS caller, never token data;
- `prepare` restores the archive and prints owner-only local paths;
- `whoami` prints the seeded ROSA subject without a device prompt;
- the deployment and rollout commands succeed under that subject; and
- unchanged archives print a fingerprint skip; changed archives persist.

Verify the independent authorities: inspect the IRSA role with AWS IAM, inspect
the secret metadata with Secrets Manager without requesting `SecretString`, and
use `oc auth whoami` plus the target resource read for ROSA identity/RBAC.

## No fixed unattended window

Microsoft documents that refresh tokens can be revoked before expiry and that
authorization policy is reevaluated during refresh. Conditional Access sign-in
frequency, administrator or user session revocation, applicable credential
changes, risk policy and continuous access evaluation can therefore require a
new sign-in. See [refresh tokens](https://learn.microsoft.com/en-us/entra/identity-platform/refresh-tokens),
[session lifetime](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-session-lifetime),
[risk policies](https://learn.microsoft.com/en-us/entra/id-protection/howto-identity-protection-configure-risk-policies),
[revocation](https://learn.microsoft.com/en-us/entra/identity/users/users-revoke-access)
and [continuous access evaluation](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-continuous-access-evaluation).

Keep the 300-second bound. If silent refresh produces a device prompt, fail the
unattended job, notify the named re-seed owner and run seed in an
operator-present session. Measure real silent-refresh and re-seed events in the
tenant instead of scheduling a nominal interval.

## Cleanup, revocation and decommissioning

Jenkins always deletes the local copy. Automatic persistence warns instead of
turning a successful deployment into a failure; an explicit `persist` returns
the AWS error.

To decommission, first revoke the person's Entra sign-in sessions, then disable
the job and wait for active runs to stop. Delete the Secrets Manager secret and
remove the IAM policy, role, ServiceAccount and local copies. Deleting the AWS
object does not revoke a token already copied elsewhere.

## Troubleshooting

| Signal | Meaning and action |
| --- | --- |
| `common libraries missing` | Copy `common/` beside `jenkins-eks/`, or set `ROSA_COMMON_DIR` exactly |
| `pending seed` or `run seed first` | Run the bounded seed with the production IRSA role before unattended use |
| `Mode B kubeconfig must request offline_access` | Mount the sibling Mode B template without removing its scope |
| `aws_caller=unobserved` | AWS identity was not readable; investigate IRSA before trusting cache operations |
| Secrets Manager access denied | Compare the Pod ServiceAccount, trust-policy subject, role and exact secret/KMS ARNs |
| packed archive exceeds 65536 bytes | Refuse the run and inspect unexpected cache growth; do not raise a nonexistent backend choice |
| device prompt during an unattended job | Stop, notify the re-seed owner and seed interactively; do not wait through the job |
| automatic persistence warning | The ROSA operation succeeded but cache rotation did not; repair AWS access before the next run |
| `Forbidden` after `whoami` | Authentication succeeded; correct ROSA RBAC for the exact subject |

## Evidence boundary

`[tested]` The offline suite parses Mode B kubeconfigs, exercises
Secrets Manager retrieval/persistence with fixtures, rejects direct argv token
material, checks fingerprint behavior and verifies persistence failure handling.

`[to confirm]` The corrected kit has not completed live end-to-end
authentication or fresh-directory silent refresh. Offline output begins with
`evidence_class=offline_simulation` and does not establish this tenant's policy.
