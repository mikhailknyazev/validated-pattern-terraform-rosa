# Replace AVP with External Secrets Operator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Argo CD Vault Plugin (AVP) as the GitOps secrets path and standardize on Red Hat External Secrets Operator (ESO) syncing AWS Secrets Manager into Kubernetes Secrets.

**Architecture:** Today bootstrap charts wire an AVP CMP sidecar + `vplugin` IRSA (`*-rosa-secretsmanager-role-iam`), and cluster-config defaults force `plugin: true` on every infrastructure Application—even though live configs have no `<path:>` placeholders. ESO is already charted and deployed on spokes for Kuadrant/Route53 and NetObserv Loki. We will (1) add first-class ESO IRSA in Terraform, (2) flip cluster-config / app-of-apps to native Helm (`plugin: false`), (3) make AVP optional then remove it from bootstrap charts, (4) update docs and close related AVP allowlist work (#39).

**Tech Stack:** Terraform (AWS IAM + OIDC IRSA), OpenShift GitOps / Argo CD, Red Hat External Secrets Operator (`external-secrets.io/v1`), Helm charts in `rh-mobb/validated-pattern-helm-charts`, cluster-config in `rh-mobb/rosa-cluster-config`.

**Tracking:** GitHub issue [#43](https://github.com/rh-mobb/validated-pattern-terraform-rosa/issues/43)

## Global Constraints

- Target operator is **Red Hat External Secrets Operator** (OLM from `redhat-operators`), not AVP and not CSI/ASCP unless a later issue says otherwise.
- Do **not** break clusters that still have `plugin: true` until cluster-config defaults are flipped and validated.
- Dual-trust IAM during transition: trust both `openshift-gitops:vplugin` and `external-secrets-operator:external-secrets-sa` until AVP is removed.
- Secrets Manager access stays least-privilege: explicit secret ARN allowlists (existing `additional_secrets` pattern).
- Zero-egress clusters must keep private image pulls; do not reintroduce a hard dependency on public GHCR for secret sync (ESO comes from Red Hat operators catalog / mirrored catalog).
- Work spans three repos; land Terraform IAM first (or in parallel), then helm-charts, then cluster-config defaults.
- Reference clones live under `reference/` in this workspace but are separate git remotes—commit/push in each repo as needed.
- Update `CHANGELOG.md` / docs only for changes landing in the Terraform repo PR; chart and cluster-config repos use their own changelogs if present.
- Follow PLAN.md; document any architecture deviation in PLAN.md Architecture Decisions.

## File map (by repo)

### A. `validated-pattern-terraform-rosa` (this repo)

| Path | Responsibility |
|------|----------------|
| `modules/infrastructure/iam/40-secrets-manager-iam.tf` | Evolve Secrets Manager IRSA from AVP-only to ESO (+ temporary AVP dual-trust) |
| `modules/infrastructure/iam/01-variables.tf` | Variable descriptions / any new toggles |
| `modules/infrastructure/iam/90-outputs.tf` | Export role ARN (keep name or add `external_secrets_role_arn` alias) |
| `modules/infrastructure/iam/README.md` | Document ESO SA trust + usage |
| `terraform/01-variables.tf` | Root variable descriptions |
| `terraform/10-main.tf` | Pass-through (likely unchanged) |
| `terraform/90-outputs.tf` | Output descriptions / alias |
| `docs/deployment/enablement.md` | Replace AVP CMP guidance with ESO |
| `docs/guides/zero-egress-ecr-access.md` | Cross-link ESO as shared pattern |
| `PLAN.md` | Architecture decision: ESO replaces AVP |
| `CHANGELOG.md` | Unreleased delta for this PR |
| `hack/docker/gitops-tools/` | Later: drop `argocd-vault-plugin` once charts no longer need it |

### B. `rh-mobb/validated-pattern-helm-charts` (`reference/validated-pattern-helm-charts/`)

| Path | Responsibility |
|------|----------------|
| `charts/cluster-bootstrap/templates/cmp-plugin.yaml` | AVP CMP (make optional / remove) |
| `charts/cluster-bootstrap/templates/default-vault-plugin-config.yaml` | `vplugin` SA + AVP env (optional / remove) |
| `charts/cluster-bootstrap/templates/argocd-crd.yaml` | Sidecar mounting AVP tools |
| `charts/cluster-bootstrap/values.yaml` | `argocd.plugin` defaults |
| `charts/cluster-bootstrap-acm-spoke/` (same templates) | Spoke bootstrap parity |
| `charts/app-of-apps-infrastructure/templates/infrastructure.yaml` | `plugin` vs native `helm` source switch |
| `charts/app-of-apps-infrastructure/values.yaml` | Example defaults (`plugin: false`) |
| `charts/external-secrets-operator/` | Canonical ESO install + ClusterSecretStore |
| `charts/network-observability-operator/templates/loki-s3-externalsecret.yaml` | Existing ESO consumer (leave; use as pattern) |

### C. `rh-mobb/rosa-cluster-config` (`reference/rosa-cluster-config/`)

| Path | Responsibility |
|------|----------------|
| `dev/*/infrastructure.yaml` | Flip `defaults.plugin` to `false`; ensure ESO chart entry + Terraform role ARN |
| `example/dev/example-cluster/infrastructure.yaml` | Same for the documented example |
| `dev/*/applications-ns.yaml` | Drop unused `AVP_TYPE` defaults if present |

---

### Task 1: Re-confirm inventory (no live AVP placeholders)

**Files:**
- Read: `reference/rosa-cluster-config/**/*.yaml`
- Read: `reference/cluster-config/**/*.yaml`
- Read: `reference/validated-pattern-helm-charts/charts/**/*.{yaml,yml,tpl}`
- Test: shell inventory commands below

**Interfaces:**
- Consumes: none
- Produces: go/no-go note in #43 if any live `<path:` appears outside `reference/pfoster/` and `archive/`

- [ ] **Step 1: Scan active cluster-config for AVP placeholders**

```bash
rg -n '<path:' reference/rosa-cluster-config reference/cluster-config --glob '*.{yml,yaml}'
```

Expected: no matches (or only comments).

- [ ] **Step 2: Scan active helm charts (exclude archive) for AVP placeholders**

```bash
rg -n '<path:' reference/validated-pattern-helm-charts/charts --glob '*.{yml,yaml,tpl}'
```

Expected: only commented examples (e.g. app-of-apps-infrastructure values).

- [ ] **Step 3: List configs that still force `plugin: true`**

```bash
rg -n 'plugin:\s*true' reference/rosa-cluster-config reference/cluster-config --glob '*.yaml'
```

Expected: defaults blocks in infrastructure.yaml files (candidates for Task 5).

- [ ] **Step 4: Comment go/no-go on #43**

If Step 1/2 find unexpected live `<path:` usage, stop and discuss before IAM/chart changes. Otherwise comment that inventory still matches prior findings and proceed.

```bash
gh issue comment 43 --body "Task 1 inventory complete on branch \`feature/43-replace-avp-with-eso\`. No blocking live \`<path:>\` placeholders in active cluster-config/charts; proceeding to ESO IAM."
```

- [ ] **Step 5: Commit** (docs-only if you recorded inventory notes; otherwise skip commit)

No code change required for this task.

---

### Task 2: Terraform — dual-trust Secrets Manager IRSA for ESO + AVP

**Files:**
- Modify: `modules/infrastructure/iam/40-secrets-manager-iam.tf`
- Modify: `modules/infrastructure/iam/01-variables.tf` (descriptions)
- Modify: `modules/infrastructure/iam/90-outputs.tf`
- Modify: `modules/infrastructure/iam/README.md`
- Modify: `terraform/01-variables.tf` (root description)
- Modify: `terraform/90-outputs.tf` (description + optional alias output)
- Test: `make tf-fmt-check tf-validate`

**Interfaces:**
- Consumes: existing `enable_secrets_manager_iam`, `additional_secrets`, OIDC endpoint locals
- Produces:
  - IAM role trust for:
    - `system:serviceaccount:openshift-gitops:vplugin` (temporary)
    - `system:serviceaccount:external-secrets-operator:external-secrets-sa` (ESO chart default)
  - Output `secrets_manager_role_arn` (unchanged name)
  - Output `external_secrets_role_arn` (alias = same ARN) for cluster-config clarity

- [ ] **Step 1: Update trust policy to dual-trust both service accounts**

In `modules/infrastructure/iam/40-secrets-manager-iam.tf`, change the role assume policy `Condition` from a single `StringEquals` sub to allow either SA. Prefer `ForAnyValue:StringEquals` on `${oidc}:sub`:

```hcl
Condition = {
  "ForAnyValue:StringEquals" = {
    "${local.oidc_endpoint_url_normalized}:sub" = [
      "system:serviceaccount:openshift-gitops:vplugin",
      "system:serviceaccount:external-secrets-operator:external-secrets-sa",
    ]
  }
}
```

Update file header comments: role is for ESO (primary) and AVP (deprecated/temporary).

- [ ] **Step 2: Update variable / output descriptions**

Root + module descriptions should say the role is for External Secrets Operator (and temporarily AVP `vplugin`), not “ArgoCD Vault Plugin” only.

Add alias output in IAM module and root:

```hcl
output "external_secrets_role_arn" {
  description = "Alias of secrets_manager_role_arn for External Secrets Operator IRSA (null if enable_secrets_manager_iam is false)"
  value       = length(aws_iam_role.secrets_manager) > 0 ? aws_iam_role.secrets_manager[0].arn : null
  sensitive   = false
}
```

- [ ] **Step 3: Update IAM module README**

Document:
- Enable with `enable_secrets_manager_iam = true`
- Annotate ESO SA: `eks.amazonaws.com/role-arn: <external_secrets_role_arn>`
- Chart values path: `external-secrets-operator.serviceAccount.roleArn`
- AVP `vplugin` trust is temporary until bootstrap charts drop AVP

- [ ] **Step 4: Format and validate**

```bash
make lint-fix
make tf-fmt-check tf-validate
```

Expected: all checks pass.

- [ ] **Step 5: Commit**

```bash
git add modules/infrastructure/iam/40-secrets-manager-iam.tf \
  modules/infrastructure/iam/01-variables.tf \
  modules/infrastructure/iam/90-outputs.tf \
  modules/infrastructure/iam/README.md \
  terraform/01-variables.tf \
  terraform/90-outputs.tf
git commit -m "$(cat <<'EOF'
feat(iam): trust ESO SA on Secrets Manager IRSA role

Allow external-secrets-operator SA to assume the existing
secretsmanager role alongside temporary AVP vplugin trust for #43.
EOF
)"
```

---

### Task 3: Helm charts — document ESO as default; stop requiring AVP for apps

**Repo:** `reference/validated-pattern-helm-charts` (remote: `rh-mobb/validated-pattern-helm-charts`)

**Files:**
- Modify: `charts/app-of-apps-infrastructure/values.yaml`
- Modify: `charts/app-of-apps-infrastructure/README.md`
- Modify: `charts/external-secrets-operator/README.md` (create/update if missing)
- Modify: `charts/cluster-bootstrap/values.yaml` (comment AVP as optional/deprecated)
- Modify: `charts/cluster-bootstrap-acm-spoke/values.yaml` (same)
- Test: `helm template` on app-of-apps-infrastructure with `plugin: false`

**Interfaces:**
- Consumes: Task 2 role ARN naming (`external_secrets_role_arn` / `*-rosa-secretsmanager-role-iam`)
- Produces: chart defaults and docs that prefer native Helm + ESO; AVP still installable for one release if `plugin: true`

- [ ] **Step 1: Change example defaults to `plugin: false`**

In `charts/app-of-apps-infrastructure/values.yaml`, ensure commented examples show:

```yaml
# defaults:
#   plugin: false
#   # AVP_TYPE / AWS_REGION only needed if plugin: true (deprecated)
```

Do **not** break the template logic in `infrastructure.yaml` that already supports native `helm:` when plugin is false.

- [ ] **Step 2: Verify native Helm rendering path**

Create a minimal values file and template:

```bash
cd reference/validated-pattern-helm-charts
cat > /tmp/aoa-eso-test.yaml <<'EOF'
teamName: cluster-config
defaults:
  clusterName: test
  gitopsNamespace: openshift-gitops
  helmRepoUrl: https://example.invalid/charts
  path: charts
  plugin: false
infrastructure:
  - chart: external-secrets-operator
    targetRevision: 1.1.3
    namespace: external-secrets-operator
    values:
      serviceAccount:
        roleArn: arn:aws:iam::123456789012:role/test-rosa-secretsmanager-role-iam
EOF
helm template test charts/app-of-apps-infrastructure -f /tmp/aoa-eso-test.yaml | rg -n 'kind: Application|plugin:|helm:|external-secrets' | head -40
```

Expected: Application uses `helm:` values block, **not** `plugin:`.

- [ ] **Step 3: Mark AVP bootstrap values as deprecated**

In both bootstrap `values.yaml` files, annotate `argocd.plugin` as deprecated in favor of ESO; keep defaults working for existing installs this release.

- [ ] **Step 4: Commit and push chart branch**

```bash
cd reference/validated-pattern-helm-charts
git checkout -b feature/43-replace-avp-with-eso
git add charts/app-of-apps-infrastructure charts/cluster-bootstrap charts/cluster-bootstrap-acm-spoke charts/external-secrets-operator
git commit -m "$(cat <<'EOF'
docs: prefer ESO over AVP for Secrets Manager

Default app-of-apps examples to native Helm; mark AVP plugin
path deprecated ahead of removal.
EOF
)"
# push + PR when ready
```

---

### Task 4: Helm charts — gate AVP CMP resources behind a value

**Repo:** `reference/validated-pattern-helm-charts`

**Files:**
- Modify: `charts/cluster-bootstrap/templates/cmp-plugin.yaml`
- Modify: `charts/cluster-bootstrap/templates/default-vault-plugin-config.yaml`
- Modify: `charts/cluster-bootstrap/values.yaml`
- Modify: `charts/cluster-bootstrap-acm-spoke/templates/cmp-plugin.yaml`
- Modify: `charts/cluster-bootstrap-acm-spoke/templates/default-vault-plugin-config.yaml`
- Modify: `charts/cluster-bootstrap-acm-spoke/values.yaml`
- Modify: `charts/cluster-bootstrap/templates/argocd-crd.yaml` (sidecar only if AVP enabled—or leave sidecar if still used for helm tools; prefer leaving sidecar if other tooling needs it, but stop requiring AVP binary path)
- Test: `helm template` with `argocd.plugin.enabled: false`

**Interfaces:**
- Consumes: none
- Produces: `argocd.plugin.enabled` (bool, default `true` for one release, then `false` in follow-up)

- [ ] **Step 1: Add `argocd.plugin.enabled` flag**

```yaml
# values.yaml
argocd:
  plugin:
    enabled: true   # deprecated; set false when cluster-config uses plugin: false
    AVP_TYPE: awssecretsmanager
```

- [ ] **Step 2: Wrap AVP ConfigMap / vplugin SA / vault Secret in `if .Values.argocd.plugin.enabled`**

Apply the same guard in hub and acm-spoke charts.

- [ ] **Step 3: Template both modes**

```bash
helm template boot charts/cluster-bootstrap \
  --set clusterName=test --set domain=example.com \
  --set argocd.plugin.enabled=false | rg -n 'vplugin|argocd-vault|cmp-plugin' || true
```

Expected: no `vplugin` / `argocd-vault-plugin-helm` resources when disabled.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(bootstrap): gate AVP CMP resources behind argocd.plugin.enabled"
```

---

### Task 5: cluster-config — disable AVP defaults; standardize ESO entry

**Repo:** `reference/rosa-cluster-config` (remote: `rh-mobb/rosa-cluster-config`)

**Files:**
- Modify: each `dev/*/infrastructure.yaml` and `example/dev/example-cluster/infrastructure.yaml`
- Modify: matching `applications-ns.yaml` if they only exist to carry `AVP_TYPE`
- Test: visual diff + ensure ESO chart block present where secrets are needed

**Interfaces:**
- Consumes: Terraform output `external_secrets_role_arn` / `secrets_manager_role_arn`
- Produces: `defaults.plugin: false` everywhere active; ESO `serviceAccount.roleArn` set to cluster’s secretsmanager role when ESO is used

- [ ] **Step 1: For each active infrastructure.yaml, set**

```yaml
defaults:
  plugin: false
  # Remove or comment AVP_TYPE / AWS_REGION unless a chart still needs plugin: true
```

- [ ] **Step 2: Ensure ESO chart values use Terraform role**

Where `external-secrets-operator` is listed, set:

```yaml
serviceAccount:
  roleArn: arn:aws:iam::<ACCOUNT>:role/<cluster>-rosa-secretsmanager-role-iam
```

Replace any one-off role names (e.g. `connectivity-link-eso-...`) only after confirming the Terraform role ARN is applied in that account (`enable_secrets_manager_iam = true`). If a cluster still uses a hand-built ESO role, leave it and document the exception in the PR.

- [ ] **Step 3: Per-chart override**

If a single chart truly still needs AVP (should be none), set `plugin: true` on that list item only—not in defaults.

- [ ] **Step 4: Commit / PR in rosa-cluster-config**

```bash
cd reference/rosa-cluster-config
git checkout -b feature/43-replace-avp-with-eso
git add dev example
git commit -m "$(cat <<'EOF'
fix: default infrastructure apps to native Helm (no AVP)

Stop forcing plugin: true / AVP_TYPE; rely on External Secrets
Operator for AWS Secrets Manager sync.
EOF
)"
```

---

### Task 6: Terraform docs + PLAN + enablement (this repo)

**Files:**
- Modify: `docs/deployment/enablement.md` (CMP / AVP sections → ESO)
- Modify: `PLAN.md` (Architecture Decisions entry)
- Modify: `CHANGELOG.md` (`[Unreleased]`)
- Modify: `modules/infrastructure/cluster/01-variables.tf` (`gitops_tools_image` description—no longer “avp-helm”-only)
- Optional: `docs/guides/zero-egress-ecr-access.md` cross-link

**Interfaces:**
- Consumes: Tasks 2–5 behavior
- Produces: operator-facing docs that match the new default path

- [ ] **Step 1: Rewrite enablement “GitOps CMP tools container” section**

State that:
- Secret sync is ESO → ClusterSecretStore → ExternalSecret
- CMP/`gitops_tools_image` is optional tooling for Helm CMP if still enabled; not required for Secrets Manager
- Link to `external-secrets-operator` chart and `enable_secrets_manager_iam`

- [ ] **Step 2: Add PLAN.md Architecture Decision**

Short AD:
- Decision: ESO replaces AVP for AWS Secrets Manager
- Status: accepted
- Consequences: `plugin: false` default; IAM trusts ESO SA; AVP removed after one deprecation release

- [ ] **Step 3: CHANGELOG `[Unreleased]` entry**

```markdown
### Changed
- **Secrets Manager IRSA for ESO (#43)**: Secrets Manager IAM role trusts External Secrets Operator SA (`external-secrets-operator:external-secrets-sa`) in addition to temporary AVP `vplugin`; docs prefer ESO over Argo CD Vault Plugin.
```

- [ ] **Step 4: Validate docs links resolve to real paths**

```bash
rg -n 'AVP|argocd-vault|External Secrets|enable_secrets_manager' docs/deployment/enablement.md PLAN.md CHANGELOG.md | head -40
```

- [ ] **Step 5: Commit**

```bash
git add docs/deployment/enablement.md PLAN.md CHANGELOG.md modules/infrastructure/cluster/01-variables.tf
git commit -m "$(cat <<'EOF'
docs: prefer External Secrets Operator over AVP

Document ESO as the GitOps Secrets Manager path for #43.
EOF
)"
```

---

### Task 7: Validation on a real or dry-run cluster

**Files:** none (operational)

**Interfaces:**
- Consumes: applied Terraform with `enable_secrets_manager_iam = true`, updated charts, updated cluster-config
- Produces: evidence comment on #43

- [ ] **Step 1: Confirm IAM trust after apply**

```bash
aws iam get-role --role-name "<cluster>-rosa-secretsmanager-role-iam" \
  --query 'Role.AssumeRolePolicyDocument' --output json
```

Expected: both `vplugin` and `external-secrets-sa` subjects present.

- [ ] **Step 2: Confirm ESO can sync a test ExternalSecret**

```bash
oc -n external-secrets-operator get sa external-secrets-sa -o yaml | rg role-arn
oc get clustersecretstore aws-secrets-manager -o yaml
oc -n <target-ns> get externalsecret,secret
```

Expected: ExternalSecret `SecretSynced` / Ready; target Secret populated.

- [ ] **Step 3: Confirm infrastructure apps no longer use CMP plugin**

```bash
oc -n openshift-gitops get applications.argoproj.io -o yaml | rg -n 'plugin:|helm:' | head -40
```

Expected: infrastructure apps show `helm:` values, not `plugin:`.

- [ ] **Step 4: Comment results on #43**

---

### Task 8: Remove AVP (follow-up commit / PR after validation)

**Do not start until Task 7 passes on at least one hub or spoke.**

**Files:**
- Helm: delete or permanently default-off AVP templates (`argocd.plugin.enabled: false` default)
- Terraform: remove `vplugin` from trust policy in `40-secrets-manager-iam.tf`
- Optional: remove `argocd-vault-plugin` from `hack/docker/gitops-tools/`
- Close or update #39 as obsolete

**Interfaces:**
- Consumes: Task 7 success
- Produces: AVP-free bootstrap; ESO-only IRSA trust

- [x] **Step 1: Default `argocd.plugin.enabled` to `false` in bootstrap charts; remove templates in a subsequent minor if desired** (done in chart 0.5.19 / 0.6.14; templates remain gated)

- [x] **Step 2: Narrow IAM trust to ESO SA only**

```hcl
Condition = {
  StringEquals = {
    "${local.oidc_endpoint_url_normalized}:sub" = "system:serviceaccount:external-secrets-operator:external-secrets-sa"
  }
}
```

- [x] **Step 3: `make tf-fmt-check tf-validate` + chart `helm template`**

- [x] **Step 4: Close #39 with comment pointing to #43 completion (or mark duplicate/obsolete)**

```bash
gh issue comment 39 --body "Superseded by #43: AVP allowlisting is moot once AVP is removed. Closing in favor of ESO."
gh issue close 39 --reason "not planned"
```

Only close #39 when AVP is actually removed, not during dual-trust.

- [x] **Step 5: Commit + CHANGELOG**

```markdown
### Removed
- **Argo CD Vault Plugin IRSA trust (#43)**: Secrets Manager IAM role trusts only External Secrets Operator after AVP removal.
```

---

## Execution order (summary)

```text
Task 1 inventory
    → Task 2 Terraform dual-trust IAM  (this repo)
    → Task 3–4 Helm chart PRs          (validated-pattern-helm-charts)
    → Task 5 cluster-config PR         (rosa-cluster-config)
    → Task 6 docs/PLAN/CHANGELOG       (this repo)
    → Task 7 validate
    → Task 8 remove AVP                (all repos)
```

## Out of scope

- Migrating Paul’s archived hub `<path:>` values in `reference/pfoster/` (document only; migrate if that config is revived).
- Replacing ESO with Secrets Store CSI / ASCP.
- Changing how admin `{cluster}-credentials` is written by Terraform (login scripts remain AWS CLI → Secrets Manager).
- Forcing every cluster to install ESO if it has no SM-backed workloads (optional chart entry stays opt-in per cluster-config).
