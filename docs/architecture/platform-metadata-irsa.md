# Platform metadata and IRSA bootstrap

**Status:** Accepted  
**Related:** [#51](https://github.com/rh-mobb/validated-pattern-terraform-rosa/issues/51) (BGP / ESO dynamic config), ESO-over-AVP (#43)  
**Audience:** Human operators and AI agents working in this repo

## Problem (chicken-and-egg)

External Secrets Operator (ESO) needs an IRSA role ARN on its ServiceAccount before it can read AWS Secrets Manager. That ARN includes the **AWS account ID** and a **per-cluster** role name:

```text
arn:aws:iam::ACCOUNT:role/{cluster}-rosa-secretsmanager-role-iam
```

Constraints:

1. **Terraform** creates the IAM role (OIDC trust is per ROSA cluster). Roles must **not** be shared across clusters or accounts.
2. **Git / cluster-config** should stay portable. Hardcoding account-specific ARNs in `infrastructure.yaml` does not scale to multi-account fleets.
3. **ESO cannot fetch its own role ARN from Secrets Manager first** — that requires IRSA already bound (circular).
4. **Argo CD Helm values from git do not read cluster ConfigMaps** at render time without plugins, fragile `lookup`, or a sync Job.

So: something with Terraform/AWS context must inject identity into the cluster **once**. That something is **bootstrap**, not GitOps content.

## Decision

| Layer | Owns |
|-------|------|
| **Terraform** | AWS IAM roles, OIDC trust, Secrets Manager secret *payloads* (e.g. `{cluster}-bgp-config`) |
| **Bootstrap** | Cluster-local **platform metadata** ConfigMap + optional direct IRSA wiring (cert-manager / awspca precedent) |
| **GitOps (cluster-config)** | Declare operators and sync rules — **not** AWS account IDs or IRSA ARNs |
| **ESO (after bind)** | Ongoing sync of app secrets from Secrets Manager |

### Platform metadata ConfigMap

Bootstrap publishes (idempotent) a ConfigMap:

- **Name:** `rosa-platform-metadata`
- **Namespace:** `openshift-gitops` (created by cluster-bootstrap)

Typical keys (omit empty):

| Key | Meaning |
|-----|---------|
| `clusterName` | ROSA cluster name |
| `awsAccountId` | AWS account ID |
| `awsRegion` | Cluster region |
| `secretsManagerRoleArn` | Full ARN for ESO IRSA (`terraform output secrets_manager_role_arn`) |
| `bgpConfigSecretName` | `{cluster}-bgp-config` when Route Server is enabled |
| `certManagerRoleArn` | Full ARN when cert-manager IAM is enabled |

Prefer **full ARNs from Terraform outputs** over reconstructing names in charts (survives renames; multi-account safe).

### Chart contract

Charts that need IRSA or Terraform-owned secret names:

1. Prefer `platformMetadata.enabled: true` (read ConfigMap via sync Job / hook).
2. Keep optional explicit `serviceAccount.roleArn` for break-glass / migration only.
3. Do **not** require account-specific ARNs in cluster-config for the happy path.

**ESO chart:** with `platformMetadata.enabled`, install SA + `ClusterSecretStore` without values `roleArn`; a Job annotates the SA from `secretsManagerRoleArn`.

**CUDN BGP chart:** Terraform secret `{cluster}-bgp-config` holds operator role ARN / region / routeServerIDs (#51). Chart ExternalSecret + apply Job consume that secret. ESO role comes from platform metadata, not from BGP values.

### Precedent: cert-manager / AWS PCA

`bootstrap-gitops.sh` already constructs or uses `CERT_MANAGER_ROLE_ARN` and passes it to Helm at bootstrap (`--set certManagerRole=...`). Platform metadata **generalizes** that idea for **GitOps-managed** charts that cannot receive `--set` from bootstrap.

## What not to do

- Hardcode `arn:aws:iam::ACCOUNT:role/...` in shared cluster-config recipes
- Share one ESO or operator IAM role across clusters (OIDC trust is per issuer)
- Expect ESO to bootstrap its own IRSA from Secrets Manager
- Rely on Helm `lookup` alone for first-sync correctness

## Mental model

```text
Git  = desired operators and sync rules (portable)
TF   = AWS roles and secret payloads (account-specific)
Boot = bind TF identity into the cluster (once) via rosa-platform-metadata
ESO  = ongoing secret sync after the bind exists
Apps = ExternalSecrets / Jobs that consume SM + metadata
```

## Rollout

1. **ESO + BGP** — first consumers of this pattern (this change set).
2. **Other charts** — [#52](https://github.com/rh-mobb/validated-pattern-terraform-rosa/issues/52) (NetObserv Loki, Kuadrant credentials, cert-manager GitOps path, etc.).

## References

- Enablement: [CUDN BGP / VPC Route Server](../deployment/enablement.md#cudn-bgp--vpc-route-server)
- Agent rules: `AGENTS.md` → Platform metadata / IRSA bootstrap
- Route Server module: `modules/infrastructure/route-server/README.md`
- Bootstrap script: `scripts/cluster/bootstrap-gitops.sh` (`publish_platform_metadata`)
