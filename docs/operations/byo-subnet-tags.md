# BYO subnet tag lifecycle

<!--
Purpose: Route operators to one read-only check and one explicitly approved cleanup path.
What this is not: This guide is not a VPC-wide scanner or an automatic destroy hook.
Prerequisites: Explicit BYO subnet ids, AWS read credentials, and a chosen manual or Jenkins path.
Authoritative references: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html
-->

ROSA HCP adds `kubernetes.io/cluster/<cluster-id>=shared` to BYO subnets.
Those keys consume EC2's 50 user-tag limit. In observed ROSA HCP 4.20.30
destroy runs, the service did not reliably remove its ownership keys. This is
observed behavior, not vendor-documented behavior.

`scripts/operations/byo-subnet-tags.py` has two verbs:

| Verb | Purpose | Mutation boundary |
|---|---|---|
| `check` | Report user-tag count, remaining slots, and cluster keys for each explicitly named subnet. | Read-only under every option. |
| `clean` | Classify exact cluster keys and report deletion candidates. | Dry-run unless `--apply` is supplied; automation must also supply `--yes`. |

Neither verb discovers subnets. Enumerate the intended subnet ids before
calling the tool. There is no VPC-wide or account-wide mode.

## Choose a run path

- [Manual workstation](byo-subnet-tags-manual.md): ambient AWS credentials,
  an owner-only OCM token file or explicit per-id assertions, and an interactive
  deletion confirmation.
- [Jenkins on Kubernetes](byo-subnet-tags-jenkins.md): AWS credentials through
  IRSA, an OCM token mounted as a file, explicit non-interactive approval, and
  an archived JSON report.

Both paths execute the same Python file. They differ only in credential source,
approval mechanism, and report destination; those are configuration choices,
not different security postures.

## Safety contract

The tool requires `DescribeTags` and `DescribeSubnets` to return identical tag
maps before it reports or mutates. This guards against the observed lag of the
EC2 tag index. A disagreement is a refusal, not an empty result.

For `clean`, every cluster id is one of four report states:

| State | Meaning | Deletable |
|---|---|---|
| `absent` | OCM answered and returned no exact cluster id. | Yes, marked `PROVED`. |
| `present` | OCM returned the exact cluster id. | No, under every option. |
| `unobserved` | OCM could not be read, including authentication, rate-limit, and timeout failures. | No. |
| `asserted-absent` | OCM was unobserved and the caller named that exact id with `--assume-absent`. | Yes, marked `ASSERTED`. |

An assertion fills an evidence gap; it cannot override a `present` result.
There is no `--force` or global skip.

An `absent` result is authoritative only within the OCM token's complete
visibility. A credential narrower than every ROSA organization or account that
can use the supplied subnets cannot prove absence; treat that result as an
evidence gap and establish each id independently before asserting it.

Before deletion, the tool writes every complete subnet tag map to an owner-only
snapshot. It then re-reads the maps, deletes only exact approved keys, and
requires the final maps to equal the snapshots byte-for-byte except for those
keys. Any change to another key or value is a failure and the snapshot path is
reported. The tool never restores a tag automatically.

## Evidence boundary

Live tests on ROSA HCP 4.20.30 established exact-key deletion, complete-map
snapshot and byte-equality verification, user-tag arithmetic excluding `aws:`
keys, and recovered-slot counts of 43, 45, and 45. They also observed ownership
keys surviving ROSA destroy.

Batch candidate discovery, three-state inventory classification,
`--assume-absent`, and the Jenkins runner are unit-tested only. They have not
been exercised as a live batch workflow.

The tool is intentionally not wired into destroy. Destroy has the strongest
cluster-to-tag identity join, but safe unattended execution required credential
refresh, retry, independent checks, and restoration machinery. A human-run or
explicitly enabled housekeeping job can expose each evidence decision directly
and remain substantially smaller.

AWS documents the [EC2 tag limit and reserved `aws:` prefix](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html#tag-restrictions).
