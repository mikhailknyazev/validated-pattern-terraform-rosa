# Design: Dynamic bootstrap HTPasswd + optional break-glass admin

**Issue:** [#29](https://github.com/rh-mobb/validated-pattern-terraform-rosa/issues/29)  
**Date:** 2026-07-29  
**Status:** Implemented on `feat/29-dynamic-idp-passwords` (pending PR / e2e)  


## Problem

GitOps bootstrap only needs cluster API credentials for `oc login` during the bootstrap run. Previously Terraform always created a long-lived HTPasswd identity provider and stored the password in AWS Secrets Manager (and Terraform state). That over-exposed a privileged credential relative to how it is used.

## Goals

- Provide short-lived HTPasswd access for bootstrap `oc login` only.
- Do not persist the bootstrap password in Secrets Manager.
- Offer an optional customer break-glass cluster admin that bootstrap does **not** use.
- Manage identity with Terraform / `rhcs` resources (not `rosa` CLI for create/delete).
- Tear down bootstrap identity reliably, including on bootstrap failure after create.

## Non-goals

- External authentication providers or break-glass credentials (ROSA external-auth feature).
- Changing Argo CD / AVP secret allowlists (see #39).
- Replacing customer IdPs (OIDC, LDAP, etc.) after day-0.

## Approaches considered

| Approach | Pros | Cons |
|----------|------|------|
| A. `rosa create/delete admin` in bootstrap script | Simple CLI lifecycle | Less aligned with “Terraform-managed infra”; couples bootstrap to rosa login; harder to mirror in module form |
| B. Temp HTPasswd via `rosa create idp` + grant | Matches IDP model | Extra grant step; still CLI-driven; password handling ad hoc |
| **C. Terraform module toggled by bootstrap (`-target`)** | Fits repo patterns; clear enable flags; destroy via apply-false; reusable module | Password briefly in TF state; `-target` must be documented |

**Selected: C.**

## Design

### Variables (root)

| Variable | Type | Default | Purpose |
|----------|------|---------|---------|
| `enable_cluster_admin` | `bool` | `false` (examples set `true`) | Optional long-lived break-glass HTPasswd admin; stored in AWS Secrets Manager; **not** used by GitOps bootstrap |
| `enable_bootstrap_admin_user` | `bool` | `false` | Short-lived bootstrap HTPasswd user; enabled only for the duration of bootstrap via script |

Existing `admin_password_override` / dual-secret paths should be rationalized so break-glass uses a single credentials secret when `enable_cluster_admin` is true. Bootstrap must not depend on that secret.

### Shared module: `htpasswd-idp`

Path: `modules/infrastructure/htpasswd-idp/` — HTPasswd IDP + user + group membership (+ optional `random_password`).

Callers are **independent instances** (different `idp_name` / `username`), so bootstrap and break-glass can both exist:

| Caller | Module | Typical names |
|--------|--------|----------------|
| Bootstrap | `bootstrap-admin` → `htpasswd-idp` | `bootstrap` / `bootstrap` |
| Break-glass | `cluster` → `htpasswd-idp` | `admin` / `admin` |

### Module: `bootstrap_admin` (wrapper)

Path: `modules/infrastructure/bootstrap-admin/` (thin wrapper around `htpasswd-idp` with bootstrap defaults).

When `enable_bootstrap_admin_user = true`:

1. Password: optional module input. If null, generate via `random_password` (module usable standalone). Bootstrap script always supplies a generated password so login does not round-trip through terraform outputs after `-target`.
2. Create dedicated HTPasswd IDP (name e.g. `bootstrap`) with one user (e.g. `bootstrap`).
3. Add user to `cluster-admins` (or configurable group, default `cluster-admins`).
4. Expose sensitive Terraform outputs (`username`, `password`) for non-script callers; bootstrap script keeps the password in-process and prints `BOOTSTRAP_*` exports on create.

When `enable_bootstrap_admin_user = false`:

- No IDP / membership / password resources (count/for_each empty). Applying with `false` after a prior `true` destroys them.

**Must not** write bootstrap password to Secrets Manager. On bootstrap retry after a failed teardown, a new script password updates the existing IDP in place (acceptable).

### Break-glass: `enable_cluster_admin`

When `true`:

- Separate HTPasswd IDP/user from bootstrap (e.g. name/user `admin`).
- Persist credentials in AWS Secrets Manager for human/`make login` / `show-credentials`.
- Independent lifecycle from `enable_bootstrap_admin_user` so disabling bootstrap admin never removes break-glass.

When `false` (variable default): no break-glass HTPasswd from this stack. Example cluster tfvars set `true` for day-0 `make login`.

### Bootstrap script flow

Script (e.g. extended `bootstrap-gitops.sh` or a thin wrapper invoked by Make):

1. Ensure cluster infrastructure is already applied; API URL available from Terraform outputs.
2. **Create bootstrap admin** via `bootstrap-admin.sh create`:
   - Generate password in the script; pass as `TF_VAR_bootstrap_admin_password`.
   - Pass `bootstrap_admin_cluster_id` from `terraform output -raw cluster_id` (avoids `-target` depending on `module.cluster` / tag drift).
   - Targeted apply `enable_bootstrap_admin_user=true`.
   - Print `BOOTSTRAP_USERNAME` / `BOOTSTRAP_PASSWORD` / `CLUSTER_API_URL` on stdout for `eval` (password never read back from Terraform).
3. **Poll API login until success** (IDP propagation can take minutes):
   - Retry `oc login --username … --password …` with backoff/timeout.
   - Log attempt count; fail clearly if timeout exceeded.
4. Proceed with existing GitOps Helm bootstrap (workers ready, charts, etc.).
5. **Teardown** via `bootstrap-admin.sh destroy` (always after GitOps, preserve GitOps exit code). Prefer apply-false over `destroy -target`.

`-target` is intentional for bootstrap. Pass cluster id as a variable so the apply does not reconcile `module.cluster`.

### Login / credentials scripts

- GitOps bootstrap: use script-exported `BOOTSTRAP_*` env during the poll/login window only.
- `make cluster.<name>.login` / `show-credentials`: use break-glass secret when `enable_cluster_admin` is true; otherwise document that no long-lived cluster admin exists (customer IdP or out-of-band admin).

### Polling parameters (initial defaults; tunable via env)

| Parameter | Suggested default |
|-----------|-------------------|
| Max attempts | 30 |
| Sleep between attempts | 20s |
| Total budget | ~10 minutes |

Reuse/extend patterns already in `bootstrap-gitops.sh` (`check_api_server_ready`, login retry loop).

## Security notes

- Bootstrap password exists briefly in Terraform state while `enable_bootstrap_admin_user=true` (and in any state backup from that window). Mitigations: short window, mandatory teardown trap, no Secrets Manager copy, dedicated IDP name for easy audit.
- Break-glass password remains in Secrets Manager by design when enabled.
- AVP must not require `{cluster}-credentials` (see #39).

## Documentation updates

- Operator workflow: when break-glass exists, how bootstrap creates/destroys temp user, polling behavior, cleanup on failure.
- Variable reference for the two enable flags.
- PLAN.md / CHANGELOG when implementing.
- Note `-target` usage and why full reconcile is avoided during bootstrap identity toggle.

## Acceptance criteria (from #29, refined)

- [ ] Design flow: create temp HTPasswd user → poll until `oc login` works → bootstrap → destroy temp user
- [ ] Implemented with Terraform module + bootstrap script orchestration and clear logging
- [ ] Compatible with optional `enable_cluster_admin` break-glass (default off)
- [ ] Bootstrap password not stored in Secrets Manager (outputs only)
- [ ] Documented operator workflow and failure cleanup
- [ ] Tested end-to-end on a dev cluster
- [ ] No long-lived bootstrap IDP password left in the running cluster after successful bootstrap

## Open questions

None blocking implementation. Optional later: rename/consolidate legacy `admin_password_override` with `enable_cluster_admin` in the same PR or a follow-up.

## Related

- Issue #29 — dynamic IDP passwords via bootstrap
- Issue #39 / PR #40 — AVP must not auto-allowlist cluster credentials
- Current HTPasswd resources: `modules/infrastructure/cluster/30-identity-provider.tf`
- Bootstrap entrypoint: `scripts/cluster/bootstrap-gitops.sh`
