# Dynamic Bootstrap HTPasswd Implementation Plan

> **For agentic workers:** Implement task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Short-lived Terraform-managed HTPasswd bootstrap user (targeted apply/destroy) plus optional break-glass `enable_cluster_admin` (default false).

**Architecture:** New `bootstrap-admin` module toggled by `enable_bootstrap_admin_user`; bootstrap Make/script applies with `-target`, polls `oc login`, tears down via apply-false + trap. Break-glass uses existing cluster IDP path gated by `enable_cluster_admin`.

**Tech Stack:** Terraform, rhcs provider, bash bootstrap scripts, Make

**Spec:** `docs/superpowers/specs/2026-07-29-dynamic-bootstrap-htpasswd-design.md`

## Global Constraints

- Bootstrap password: sensitive TF outputs only (no Secrets Manager)
- `enable_cluster_admin` default `false`; `enable_bootstrap_admin_user` default `false`
- Prefer apply-true / apply-false with `-target=module.bootstrap_admin`
- Relates to #29

### Task 1: bootstrap-admin module
### Task 2: Root wiring + enable_cluster_admin
### Task 3: Bootstrap script orchestration + login poll
### Task 4: Docs / CHANGELOG / PLAN + validate
