# Manage BYO subnet tags from a workstation

<!--
Purpose: Provide a complete manual check, dry-run, approval, and evidence procedure.
What this is not: This guide does not discover subnets or automate cleanup during destroy.
Prerequisites: Python 3, AWS CLI, OCM CLI, explicit subnet ids, and the bundle's scripts.
Authoritative references: https://docs.aws.amazon.com/cli/latest/reference/ec2/delete-tags.html
-->

This path runs `scripts/operations/byo-subnet-tags.py` from a trusted
workstation. `check` needs only EC2 read permission. `clean` needs write
permission only when `--apply` is supplied.

## Prerequisites

- Python 3.11 or newer.
- AWS CLI credentials for the target account and region.
- The exact BYO subnet ids to inspect. The tool never discovers them.
- For proved absence, an OCM access token in an owner-only file with visibility
  across every ROSA organization or account that can use the supplied subnets.
  A narrower inventory cannot prove global absence. When complete inventory is
  unavailable, use one `--assume-absent` for each id you have independently
  proved absent.

For `check`, grant only `ec2:DescribeTags` and `ec2:DescribeSubnets`. The
[EC2 service authorization table](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ec2.html)
lists no resource type for either read action, so AWS requires
`"Resource": "*"`. Do not grant `ec2:DeleteTags` to read-only users.

For `clean --apply`, add `ec2:DeleteTags` on only the intended subnet ARNs and
limit `aws:TagKeys` to `kubernetes.io/cluster/*`. The same service authorization
table lists the `subnet` resource type and the `aws:TagKeys` condition for
`DeleteTags`.

## Environment contract

Use placeholders; do not retain real identifiers in shared transcripts.

```bash
# Covers: env:AWS_REGION, env:SUBNET_IDS, env:REPORT_JSON
# Does: Selects one region, an explicit subnet list, and an owner-readable report destination.
# Why: Explicit ids make the read scope reviewable before the command runs.
# Change: Add or remove only the subnets intended for this one operation.
# Trap: Do not replace SUBNET_IDS with a VPC query; the lifecycle tool has no discovery mode by design.
# Evidence: https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-subnets.html
export AWS_REGION='<aws-region>'
export SUBNET_IDS='subnet-<id-a> subnet-<id-b>'
export REPORT_JSON='./artifacts/byo-subnet-tags-check.json'
```

## Read-only check

```bash
# Covers: run-check.sh
# Does: Reports total user tags, remaining slots, and every cluster ownership key per named subnet.
# Why: Running the non-mutating verb first establishes headroom and the exact candidate set.
# Change: None; the runner accepts no mutation option.
# Trap: A read error or disagreement between EC2 read APIs fails rather than reporting free slots.
# Evidence: https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-tags.html
examples/byo-subnet-tags/manual/run-check.sh
```

Expected output has one `SUBNET` line per id, zero or more `CLUSTER_KEY` lines,
and a final `SUMMARY`. `status=WARNING` means five or fewer user-tag slots
remain. `status=FULL` exits non-zero because no user-tag slot remains. Keys with
the reserved `aws:` prefix do not count toward the 50-user-tag limit.

## Prepare owning-inventory evidence

Write a fresh OCM token to an owner-only file. Its value must not be put in an
argument, environment variable, transcript, or report.

```bash
# Covers: env:OCM_TOKEN_FILE
# Does: Creates a file readable only by its owner and writes the current OCM access token into it.
# Why: The tool sends the bearer value only in the HTTPS Authorization header.
# Change: Refresh the file before a later run; this tool deliberately has no token-exchange or retry machinery.
# Trap: Group- or other-readable token files make cluster state unobserved and therefore non-deletable.
# Evidence: https://api.openshift.com/api/clusters_mgmt/v1/openapi
umask 077
export OCM_TOKEN_FILE="$HOME/.config/ocm/byo-subnet-tags.token"
ocm token >"$OCM_TOKEN_FILE"
chmod 0600 "$OCM_TOKEN_FILE"
```

If OCM cannot observe an id, first establish absence through an independent
owning inventory, then place only that exact 32-character ROSA cluster id in
`ASSUME_ABSENT_IDS`. This changes its report state from `unobserved` to
`asserted-absent`. It cannot override `present`.

## Dry-run clean

```bash
# Covers: env:ASSUME_ABSENT_IDS, env:APPLY_CHANGES, env:SNAPSHOT_DIR, env:REPORT_JSON
# Does: Classifies all exact cluster keys while leaving deletion disabled.
# Why: The human report must show PROVED, ASSERTED, and refused rows before approval.
# Change: Add an id only when you accept responsibility for its asserted absence; leave APPLY_CHANGES false.
# Trap: A typo that does not match a candidate key refuses instead of silently authorizing nothing.
# Evidence: Syntax-only: environment contract consumed by the bundled manual runner.
export ASSUME_ABSENT_IDS=''
export APPLY_CHANGES=false
export SNAPSHOT_DIR='./artifacts/snapshots'
export REPORT_JSON='./artifacts/byo-subnet-tags-clean.json'
examples/byo-subnet-tags/manual/run-clean.sh
```

Expected `TAG` rows include `state`, `action`, and `absence`. The final line is
`DRY_RUN no tags deleted`. Review the JSON report and verify every `delete` row
names the intended subnet, exact key, and either `PROVED` or `ASSERTED`.

## Apply exact deletions

```bash
# Covers: env:APPLY_CHANGES
# Does: Enables mutation and asks the operator to type the exact number of keys before any deletion.
# Why: Interactive confirmation keeps manual approval separate from classification.
# Change: Return APPLY_CHANGES to false immediately after the run.
# Trap: Approval never changes a present or unobserved row into a deletable row.
# Evidence: https://docs.aws.amazon.com/cli/latest/reference/ec2/delete-tags.html
export APPLY_CHANGES=true
examples/byo-subnet-tags/manual/run-clean.sh
export APPLY_CHANGES=false
```

Success prints `APPLIED deleted=<count> snapshot=<path>`. Retain both the JSON
report and the owner-only snapshot. The tool has already re-read every complete
map and proved that all non-target keys and values are byte-equal. A failure
while deleting reports each API-acknowledged exact key by subnet, names the
snapshot, and records the same outcome in the JSON report. The tool does not
roll back; reconcile the reported extent against the snapshot before issuing
another command.

## Cleanup

Remove the short-lived local token when the review record is complete. Retain
the sanitized report and snapshot under your normal evidence policy.

```bash
# Covers: OCM_TOKEN_FILE
# Does: Removes the local bearer-token file after the inventory reads are complete.
# Why: The report and snapshot contain no token and are the only artifacts needed for review.
# Change: Delay removal only while another immediate classification read is planned.
# Trap: Never archive or commit the token file with the JSON artifacts.
# Evidence: Syntax-only: local file lifecycle for the token created earlier in this guide.
rm -f -- "$OCM_TOKEN_FILE"
```

## Troubleshooting

| Signal | Meaning | Action |
|---|---|---|
| `DescribeTags and DescribeSubnets disagree` | EC2 read surfaces have not converged. | Wait, then run `check` again. Do not clean from either partial view. |
| `state=unobserved` | OCM did not establish presence or absence. | Refresh the owner-only token, or independently prove and assert that one id. |
| `cannot override present` | An assertion conflicts with owning-API evidence. | Keep the tag and investigate the cluster. |
| `changed before deletion` | Tags changed after the snapshot. | Review the new map and start again. |
| `APPLY_FAILED` | One exact delete failed; earlier `DELETED` rows, if any, were acknowledged by EC2. | Preserve the snapshot and report, then reconcile their exact extent before another command. |
| `post-delete maps differ` | The final complete map is not the exact expected result. | Stop, preserve the snapshot, and investigate every difference. |
