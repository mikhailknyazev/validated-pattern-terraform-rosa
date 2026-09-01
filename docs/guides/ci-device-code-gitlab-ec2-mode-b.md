<!--
Purpose: Complete GitLab-on-EC2 procedure for a Secrets Manager-backed device-code session.
What this is not: This path creates no Entra app, ROSA provider or ROSA RBAC.
Prerequisites: GitLab Runner on EC2, external-auth-enabled ROSA HCP, public Entra client, instance profile and routed TLS access.
Authoritative references:
- https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2_instance-profiles.html
- https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html
- https://github.com/int128/kubelogin/blob/v1.36.2/docs/setup.md
-->

# GitLab on EC2: Mode B

Use this path when one accountable person seeds a refresh-capable session and
GitLab jobs restore it from AWS Secrets Manager. The EC2 runner receives AWS
credentials from an instance profile; Microsoft Entra and ROSA still
authenticate and authorize the person.

## Copy this path

Copy both directories without changing their relative placement:

```text
examples/ci-external-auth-device-code/common/
examples/ci-external-auth-device-code/gitlab-ec2/mode-b/
```

The entry point sources both common libraries. Set `ROSA_COMMON_DIR` only when
packaging cannot retain the documented layout. A missing library is a refusal.

## Prerequisites and runner identity

1. Configure a ROSA HCP external-auth provider for Microsoft Entra ID. Enable
   public-client device-code flows, include the client ID in the provider
   audience list, map a stable human claim and grant minimum RBAC to the
   realized subject. Follow the repository's
   [Entra external-auth guide](external-auth-entra-id.md).
2. Build an immutable EC2 runner image containing compatible `oc`, `kubectl`,
   `kubectl oidc-login`, GNU `timeout`, AWS CLI, tar, gzip and base64.
3. Permit HTTPS to Microsoft Entra, the ROSA API, AWS STS, Secrets Manager and
   the selected KMS endpoint. Supply the real ROSA cluster CA.
4. Create one customer-managed KMS key and one Secrets Manager secret for the
   seeded person and pipeline. Do not share the object across people or
   unrelated pipelines.
5. Create one IAM role, attach the sibling `iam-policy.json`, place the role in
   an instance profile, and attach that profile to the dedicated runner
   instance. An instance profile is the EC2 container for a role; the policy is
   attached to the role, not to a "role profile".

## Create the AWS custody objects

Replace the exact secret and KMS ARN placeholders in `iam-policy.json`. Create
the sentinel secret; it contains no token and is rejected until seed succeeds.

```bash
# Covers: --region, --name, --kms-key-id, --secret-string
# Does: Creates one KMS-encrypted Secrets Manager object in an explicit pre-seed state.
# Why: A named sentinel distinguishes an unused object from a malformed or empty archive.
# Change: Another region, key or name selects a different custody and IAM boundary.
# Trap: Never place real token material in this command or any process argument.
# Evidence: https://docs.aws.amazon.com/cli/latest/reference/secretsmanager/create-secret.html
aws secretsmanager create-secret \
  --region '<aws-region>' \
  --name '<secret-name>' \
  --kms-key-id '<kms-key-arn>' \
  --secret-string 'pending-seed'
```

Create `ec2-trust-policy.json` from this complete service trust. It grants only
the EC2 service permission to assume the role; the instance-profile association
below determines which runner receives it.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Then create and attach the profile:

```bash
# Covers: --role-name, --assume-role-policy-document, --policy-name, --policy-document, --instance-profile-name, --iam-instance-profile, --instance-id
# Does: Creates the EC2 role and instance profile, attaches exact cache permissions, and associates the profile with one runner instance.
# Why: EC2 supplies short-lived AWS credentials without static access keys in GitLab variables.
# Change: Another role, profile, policy or instance changes which runner can retrieve the human session.
# Trap: Refuse if the runner already has a different instance profile; replacing one can remove permissions unrelated jobs need.
# Evidence: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2_instance-profiles.html
aws iam create-role \
  --role-name '<runner-role-name>' \
  --assume-role-policy-document 'file://ec2-trust-policy.json'
aws iam put-role-policy \
  --role-name '<runner-role-name>' \
  --policy-name '<cache-policy-name>' \
  --policy-document 'file://iam-policy.json'
aws iam create-instance-profile --instance-profile-name '<runner-profile-name>'
aws iam add-role-to-instance-profile \
  --instance-profile-name '<runner-profile-name>' \
  --role-name '<runner-role-name>'
aws ec2 associate-iam-instance-profile \
  --iam-instance-profile Name='<runner-profile-name>' \
  --instance-id '<runner-instance-id>'
```

## Environment contract

Configure the following as protected GitLab CI/CD variables or immutable runner
environment. Do not store token material in a GitLab variable.

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

The entry point refuses a static template without `offline_access`. It measures
the packed archive and refuses values above Secrets Manager's 65,536-byte
string limit.

!!! danger "Human identity custody"
    Anyone who can run a job with this instance-profile role can act as the
    seeded person on the cluster, and the cluster audit trail will show that
    person. Restrict who can modify GitLab jobs, use the runner, attach or
    assume the role, read or replace the secret, and bind the resulting ROSA
    subject. Use a dedicated, accountable person; do not describe the session
    as a workload identity.

## Seed the session

Run seed once from the production runner with the instance profile attached.
Keep the process running while the person completes the printed device step.

```bash
# Covers: env:ROSA_AUTH_ROOT, env:ROSA_COMMON_DIR, env:AWS_REGION, env:ROSA_B_SECRET_ID, env:ENTRA_TENANT_ID, env:ENTRA_PUBLIC_CLIENT_ID, env:ROSA_API_ENDPOINT, env:ROSA_CLUSTER_CA_B64
# Does: Completes one bounded device-code sign-in and persists the archive only after whoami succeeds.
# Why: Seeding on the production runner proves the human mapping and the exact instance-profile custody path.
# Change: Another tenant, client, API, secret or runner selects another identity or authority boundary.
# Trap: Later cluster actions are attributed to this person; never seed a shared or unaccountable user.
# Evidence: https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code
export ROSA_AUTH_ROOT='examples/ci-external-auth-device-code/gitlab-ec2/mode-b'
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

Bind the full subject printed by `oc auth whoami` to minimum ROSA RBAC.

## GitLab CI file

The supplied `.gitlab-ci.yml` is the complete job for this path:

```yaml
# Covers: variables, ROSA_AUTH_ROOT, ROSA_COMMON_DIR, ROSA_B_PERSIST, ROSA_AUTH_TIMEOUT_SECONDS, TARGET_NAMESPACE, MANIFEST_DIR, DEPLOYMENT_NAME, HOME, stages, rosa-deploy, stage, timeout, resource_group, script, after_script, --namespace, --filename, --timeout
# Does: Uses the fixed Mode B entry point for restore, bounded identity, deployment, persistence and local cleanup.
# Why: The resource group prevents two jobs from overwriting one rotated human refresh session with stale state.
# Change: Another path, namespace, manifest directory or rollout target changes custody or deployment authority.
# Trap: Removing serialization creates last-writer-wins token rollback; archiving /tmp exports reusable human credentials.
# Evidence: https://docs.gitlab.com/ci/yaml/
variables:
  ROSA_AUTH_ROOT: "examples/ci-external-auth-device-code/gitlab-ec2/mode-b"
  ROSA_COMMON_DIR: "examples/ci-external-auth-device-code/common"
  ROSA_B_PERSIST: "auto"
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
  resource_group: rosa-oidc-device-code
  script:
    - set +x
    - umask 077
    - '"${ROSA_AUTH_ROOT}/rosa-auth.sh" status'
    - '"${ROSA_AUTH_ROOT}/rosa-auth.sh" prepare'
    - '"${ROSA_AUTH_ROOT}/rosa-auth.sh" whoami'
    - '"${ROSA_AUTH_ROOT}/rosa-auth.sh" run -- apply --namespace="${TARGET_NAMESPACE}" --filename="${MANIFEST_DIR}"'
    - '"${ROSA_AUTH_ROOT}/rosa-auth.sh" run -- rollout status "deployment/${DEPLOYMENT_NAME}" --namespace="${TARGET_NAMESPACE}" --timeout=4m'
  after_script:
    - 'set +x; umask 077; "${ROSA_AUTH_ROOT}/rosa-auth.sh" cleanup'
  # Never place OIDC_TOKEN_CACHE_DIR in cache: or artifacts:.
```

`resource_group` serializes jobs that share the secret. Do not archive the token
directory or split restore, deployment and persistence across GitLab jobs.

## Run and verify

A normal unattended job prints `mode=B`, an observed AWS caller, owner-only
local paths and the seeded ROSA subject without a browser prompt. An unchanged
archive produces a fingerprint skip; changed refresh state is persisted.

Read each authority independently: `aws sts get-caller-identity` for the
instance-profile role, `aws secretsmanager describe-secret` without requesting
the value for the custody object, `oc auth whoami` for the ROSA identity, and a
permitted Kubernetes resource for RBAC.

## No fixed unattended window

Refresh-token usability varies with tenant policy, inactivity and revocation.
Conditional Access sign-in frequency, administrator or user session revocation,
credential changes, risk policy and continuous access evaluation can each
require a new sign-in. See [refresh tokens](https://learn.microsoft.com/en-us/entra/identity-platform/refresh-tokens),
[session lifetime](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-session-lifetime),
[risk policies](https://learn.microsoft.com/en-us/entra/id-protection/howto-identity-protection-configure-risk-policies),
[revocation](https://learn.microsoft.com/en-us/entra/identity/users/users-revoke-access)
and [continuous access evaluation](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-continuous-access-evaluation).

Keep the 300-second wait bound. A device prompt during an unattended run is a
failure: notify the named re-seed owner and seed in a person-present session.
Measure actual silent refresh and re-seed events instead of assuming a fixed
interval.

## Cleanup, revocation and decommissioning

`after_script` always removes the local copy. Automatic persistence warns
instead of failing a successful deployment; explicit `persist` returns AWS
errors. To decommission, revoke the person's Entra sign-in sessions, disable
the pipeline and wait for active jobs, then delete the secret, detach/remove the
role and instance profile, and remove local copies. Deleting the secret does not
revoke copies held elsewhere.

## Troubleshooting

| Signal | Meaning and action |
| --- | --- |
| `common libraries missing` | Copy `common/` beside `gitlab-ec2/`, or set `ROSA_COMMON_DIR` exactly |
| `pending seed` or `run seed first` | Run seed on the production runner before unattended use |
| `Mode B kubeconfig must request offline_access` | Use the sibling Mode B template without removing refresh scope |
| `aws_caller=unobserved` | The instance-profile identity was unreadable; investigate before trusting cache operations |
| Secrets Manager access denied | Compare the attached instance profile, role policy and exact secret/KMS ARNs |
| packed archive exceeds 65536 bytes | Refuse and inspect unexpected cache growth; do not truncate |
| device prompt during an unattended job | Stop, notify the re-seed owner and seed interactively |
| automatic persistence warning | Deployment succeeded but cache rotation failed; repair AWS access before the next run |
| `Forbidden` after `whoami` | Authentication succeeded; fix ROSA RBAC for the exact subject |

## Evidence boundary

`[tested]` The offline suite parses Mode B kubeconfigs, exercises Secrets
Manager retrieval/persistence with fixtures, rejects direct argv token material,
checks fingerprints and verifies persistence failure handling.

`[to confirm]` The kit has not completed live end-to-end authentication or a
fresh-directory silent refresh. Offline output begins with
`evidence_class=offline_simulation` and does not establish this tenant's policy.
