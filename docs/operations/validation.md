# Validation Scripts

Pre-deployment validation for ROSA HCP clusters. Checks account readiness and VPC configuration (when applicable) before `terraform apply`.

## Makefile usage

```bash
# Full validation (account + network from tfvars) — primary entry point
make cluster.public.validate

# Subsets (optional)
make cluster.public.validate-account   # tools, OCM role, quotas, connectivity
make cluster.my-byo.validate-network     # VPC/subnets/endpoints only

# Terraform syntax (separate from prerequisites)
make cluster.public.validate-terraform
```

`validate-prereqs` is an alias for `validate` (backward compatible).

## Scripts

| Script | Purpose |
|--------|---------|
| [`account.sh`](https://github.com/rh-mobb/validated-pattern-terraform-rosa/blob/main/scripts/validate/account.sh) | Operator tools, AWS creds, ROSA/OCM linking, quotas, URL connectivity |
| [`byo-network.sh`](https://github.com/rh-mobb/validated-pattern-terraform-rosa/blob/main/scripts/validate/byo-network.sh) | VPC DNS, subnets, tags, endpoints, route tables |
| [`prereqs.sh`](https://github.com/rh-mobb/validated-pattern-terraform-rosa/blob/main/scripts/validate/prereqs.sh) | Combined validation driven by cluster `terraform.tfvars` |

## Direct usage

```bash
# Account validation only
./scripts/validate/account.sh --region ap-southeast-2

# Skip URL checks (restricted CI networks)
./scripts/validate/account.sh --region us-east-1 --skip-connectivity

# BYO VPC validation
./scripts/validate/byo-network.sh \
  --vpc-id vpc-0abc123 \
  --region ap-southeast-2 \
  --zero-egress \
  --multi-az

# Full cluster validation (same as make cluster.<name>.validate)
./scripts/validate/prereqs.sh public
```

## When to run

| Phase | Command |
|-------|---------|
| Before `init` / `apply` | `make cluster.<name>.validate` |
| BYO VPC handoff only | `make cluster.<name>.validate-network` |
| Account/tools check only | `make cluster.<name>.validate-account` |

Network validation runs automatically when:

- `network_type = existing` and `existing_vpc_id` is set (BYO), or
- Terraform is initialized and `vpc_id` output exists (post-init full-stack)

## What is not checked

- **Per-cluster HCP account roles** — created by `module.iam` on `terraform apply`
- **`rosa verify permissions`** — non-STS clusters only
- **User role** — OCM web console only

## Exit codes

- `0` — all checks passed
- `1` — one or more FAIL items; fix before proceeding

WARN and INFO items are informational and do not fail the script.

## Dependencies

- `aws`, `jq`, `curl` (required)
- `rosa` >= 1.2.64 (required for OCM role checks)
- AWS credentials and `rosa login` (or OCM token)

## Related

- [Account Prerequisites](../prerequisites/account.md)
- [BYO Network Requirements](../prerequisites/byo/network.md)
- [Choose Your Path](../prerequisites/index.md)

## Reference

Validation patterns adapted from Red Hat zero-egress ROSA HCP prerequisite checks.
