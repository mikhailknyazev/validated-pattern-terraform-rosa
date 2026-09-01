<!--
Purpose: Route readers to one complete Jenkins/EKS or GitLab/EC2 device-code path.
What this is not: This hub is not an implementation procedure; each linked path guide stands alone.
Prerequisites: A ROSA HCP cluster using Entra external authentication and a decision about runner and custody mode.
Authoritative references:
- https://github.com/int128/kubelogin/blob/v1.36.2/docs/setup.md
- https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code
- https://learn.microsoft.com/en-us/entra/identity-platform/refresh-tokens
-->

# CI access to ROSA with Entra device code

Choose one path. Each guide includes the complete prerequisites, runner identity,
CI definition, environment contract, run sequence, cleanup and troubleshooting
for that path; the other three guides are not required reading.

| Runner | Mode A: person signs in every run | Mode B: seeded refresh session |
| --- | --- | --- |
| Jenkins agent on EKS | [Jenkins on EKS, Mode A](ci-device-code-jenkins-eks-mode-a.md) | [Jenkins on EKS, Mode B](ci-device-code-jenkins-eks-mode-b.md) |
| GitLab Runner on EC2 | [GitLab on EC2, Mode A](ci-device-code-gitlab-ec2-mode-a.md) | [GitLab on EC2, Mode B](ci-device-code-gitlab-ec2-mode-b.md) |

Only these four combinations are offered.

## Shared identity model

Three authorities participate and answer different questions:

1. **Microsoft Entra ID** authenticates a person through device code and decides
   whether a refresh session can continue.
2. **AWS IAM** exists only in Mode B. It decides which EKS Pod or EC2 runner can
   read and replace the encrypted token archive in Secrets Manager.
3. **ROSA external authentication and RBAC** map the Entra claims to a cluster
   subject, authorize that subject and record that person in the audit trail.

AWS access never authenticates the runner to ROSA. ROSA RBAC never grants access
to the Secrets Manager object.

## Choose the custody mode

| Property | Mode A | Mode B |
| --- | --- | --- |
| Browser action | Required once per pipeline run | Required for initial seed and whenever Entra requires reauthentication |
| `offline_access` | Not requested | Requested |
| Cross-job token state | None | Encrypted archive in one Secrets Manager secret |
| AWS CLI and cache IAM | Not used | Required |
| Main operational cost | A person must be present for every run | The runner role can act as the seeded person |

Mode A contains no durable-cache library, AWS CLI requirement, IAM policy,
secret or KMS grant. Its disk state exists only so multiple `oc` commands in one
job do not prompt repeatedly; cleanup deletes it.

Mode B restores one encrypted archive into job-local storage, persists it only
when its fingerprint changes and removes the local copy on every pipeline
outcome. The archive is refresh-token material, not an application secret.

!!! danger "Human identity custody"
    Anyone who can run a job with the Mode B IAM role can act as the seeded
    person on the cluster, and the cluster audit trail will show that person.
    Restrict who can modify jobs, assume the role, read or replace the secret,
    and bind the resulting ROSA subject. Use a dedicated, accountable person;
    do not describe the session as a workload identity.

## Why there is no fixed unattended window

A refresh token's usable life is not a constant. Microsoft documents default
lifetimes, but also documents that refresh tokens can be revoked before expiry
and that authorization policy is reevaluated when a token is refreshed. Tenant
controls and user state therefore overrule any calendar estimate.

These events can force another interactive sign-in:

- a Conditional Access sign-in-frequency control reaches its configured bound;
- an administrator or the user revokes sign-in sessions;
- a credential change invalidates the applicable token class;
- a user-risk or sign-in-risk policy requires remediation or blocks access; or
- continuous access evaluation communicates a supported critical event to a
  participating resource and client.

Sources: [refresh-token lifetime and revocation](https://learn.microsoft.com/en-us/entra/identity-platform/refresh-tokens),
[Conditional Access session lifetime](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-session-lifetime),
[risk policies](https://learn.microsoft.com/en-us/entra/id-protection/howto-identity-protection-configure-risk-policies),
[session revocation](https://learn.microsoft.com/en-us/entra/identity/users/users-revoke-access),
and [continuous access evaluation](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-continuous-access-evaluation).

Every path bounds an `oc` wait with `ROSA_AUTH_TIMEOUT_SECONDS` (default 300).
For Mode B, treat a silent refresh that turns into a device-code prompt as a
failed unattended run: stop the job, notify the named re-seed owner and run the
documented seed procedure in an operator-present session. Do not leave a CI job
waiting for an unknown person. Measure successful silent refreshes and actual
re-seed events in the tenant; do not schedule a fixed re-seed interval from a
nominal token lifetime.

## Evidence boundary

`[tested]` The offline suite parses realized kubeconfig values, enforces each
path's scope, checks byte identity between Jenkins and GitLab entry points,
exercises Secrets Manager persistence through fixtures and verifies cleanup and
failure propagation.

`[to confirm]` This corrected kit has not completed live end-to-end
authentication. The suite prints `evidence_class=offline_simulation` before any
other output and proves local orchestration only. It does not establish that a
particular tenant permits silent refresh or how long that tenant will permit it.

Observed behavior, not vendor-documented: a device-code session with the same
identity-provider shape reused a disk cache across an ID-token expiry. Treat
that observation as a reason to test the chosen tenant, not as a duration
promise for this kit.
