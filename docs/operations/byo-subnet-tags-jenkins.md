# Manage BYO subnet tags from Jenkins on Kubernetes

<!--
Purpose: Provide a complete IRSA-based Jenkins check, approval, cleanup, and evidence procedure.
What this is not: This guide does not use static AWS keys or discover subnets from a VPC.
Prerequisites: Jenkins Kubernetes agents, EKS IRSA, an OCM token Secret, and an approved tool image.
Authoritative references: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
-->

This path runs the same `scripts/operations/byo-subnet-tags.py` file as the
manual path. AWS authentication comes from IRSA. The OCM token is mounted as a
file; its value never enters command arguments or an echo-able environment
variable. The job archives its JSON report and any pre-delete snapshot.

## Prerequisites

- A Jenkins controller using the Kubernetes plugin.
- An EKS cluster with an IAM OIDC provider for
  [IAM roles for service accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html).
- An approved image pinned by digest and containing Python 3.11+, AWS CLI, and
  this repository checkout.
- The explicit BYO subnet ids and AWS region.
- A short-lived OCM token with visibility across every ROSA organization or
  account that can use the supplied subnets, available to the operator creating
  the Kubernetes Secret. A narrower inventory cannot prove global absence.

Copy `scripts/operations/byo-subnet-tags.py` and the complete
`examples/byo-subnet-tags/jenkins/` directory. Do not create a path-specific
copy of the Python tool.

## AWS identity and least privilege

Create one IAM role trusted only by the Jenkins ServiceAccount identity, then
attach `examples/byo-subnet-tags/jenkins/iam-policy.json` after replacing the
exact subnet ARN placeholders.

The policy deliberately uses two scopes:

- `ec2:DescribeTags` and `ec2:DescribeSubnets` require `"Resource": "*"`
  because their individual entries in the
  [EC2 service authorization table](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ec2.html)
  list no resource type.
- `ec2:DeleteTags` is limited to the named subnet ARNs and an `aws:TagKeys`
  condition matching only cluster ownership keys. Its service-authorization
  entry supports both controls.

To adopt only `check`, omit the entire `DeleteClusterKeysFromNamedSubnets`
statement. No write permission is needed.

Apply the ServiceAccount only after its role annotation names the intended
IRSA role.

```bash
# Covers: --server-side, --filename
# Does: Creates or updates only the reviewed Jenkins ServiceAccount manifest.
# Why: Server-side apply records field ownership for a later exact review or removal.
# Change: Replace namespace and role placeholders before applying; keep the object name aligned with pod.yaml.
# Trap: The annotation must contain the role ARN, not an instance-profile ARN or a static AWS key.
# Evidence: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
kubectl apply --server-side --filename examples/byo-subnet-tags/jenkins/serviceaccount.yaml
```

## OCM credential custody

Create a namespaced Secret from an owner-only token file. The Pod projects only
the `token` key at mode `0400`. The Secret and every Pod that can mount it are
credential-custody boundaries: anyone who can read the Secret or execute in the
Pod can act with that OCM token until it expires.

```bash
# Covers: env:OCM_TOKEN_FILE, --namespace, --from-file, --dry-run, --output, --filename
# Does: Builds the token Secret manifest locally and applies it without putting the token value in argv.
# Why: --from-file passes only the path; piping avoids a retained plaintext manifest.
# Change: Namespace must match serviceaccount.yaml and pod.yaml; refresh the Secret before a later run.
# Trap: Do not use --from-literal or a Jenkins string credential because either can expose the bearer in process or job data.
# Evidence: https://kubernetes.io/docs/concepts/configuration/secret/#use-case-pod-with-ssh-keys
export OCM_TOKEN_FILE="$HOME/.config/ocm/byo-subnet-tags.token"
kubectl create secret generic byo-subnet-tags-ocm \
  --namespace '<jenkins-namespace>' \
  --from-file="token=$OCM_TOKEN_FILE" \
  --dry-run=client \
  --output=yaml | kubectl apply --filename=-
```

## Pod and job configuration

Replace the image placeholder in `pod.yaml` with an approved immutable image
digest. Replace `AWS_REGION` in `Jenkinsfile`. The `SUBNET_IDS` build parameter
is a whitespace-delimited list of exact subnet ids. `ASSUME_ABSENT_IDS` is a
whitespace-delimited list of exact 32-character cluster ids whose absence the
operator has independently established; the Jenkinsfile passes each one as a
separate `--assume-absent` argument.

The `Inspect` stage always runs first and does not include `--apply`. The
`Apply exact deletions` stage runs only when `APPLY_CHANGES` is selected, and
the reviewed command contains both `--apply` and `--yes`. `--yes` skips only
the terminal prompt; it does not bypass inventory classification, snapshotting,
or complete-map verification.

Create or update the Jenkins Pipeline job from the shipped `Jenkinsfile`. In
**Build with Parameters**, set `SUBNET_IDS` to the exact ids, leave
`ASSUME_ABSENT_IDS` empty unless each named id has independent absence evidence,
and leave `APPLY_CHANGES` cleared for the first build.

Expected console output includes one `SUBNET` line per id, `TAG` rows with
`PROVED`, `ASSERTED`, or `NONE`, a `SUMMARY`, and `DRY_RUN no tags deleted`.
The build archives `artifacts/byo-subnet-tags.json`.

After reviewing every deletion row, open **Build with Parameters** again, keep
the exact same subnet and assertion values, select `APPLY_CHANGES`, and start
the explicitly enabled build. If the maps or inventory changed, the tool
reclassifies them and can still refuse before deletion.

Success prints `APPLIED deleted=<count> snapshot=<path>`. Jenkins archives the
JSON report and owner-only snapshot. Review them together; empty artifacts after
a refusal are not a successful clean. If a later delete is denied, the console
and JSON report name every earlier API-acknowledged exact key and the snapshot;
the tool does not roll back, so the operator must reconcile that extent.

## Cleanup

Delete the short-lived OCM Secret after the run. Remove the ServiceAccount and
its IAM role when the scheduled housekeeping job is retired. Retain sanitized
reports and snapshots under the build-record policy.

```bash
# Covers: kubectl delete secret, kubectl delete serviceaccount, --namespace, --ignore-not-found
# Does: Removes the two namespaced credential-bound objects shipped for this path.
# Why: The OCM bearer and IRSA assumption path should not outlive the reviewed housekeeping job.
# Change: Omit the ServiceAccount deletion while a scheduled job still intentionally uses it.
# Trap: Deleting Kubernetes objects does not delete the IAM role; remove that separately through its owning AWS process.
# Evidence: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_delete/
kubectl delete secret byo-subnet-tags-ocm --namespace '<jenkins-namespace>' --ignore-not-found
kubectl delete serviceaccount byo-subnet-tags --namespace '<jenkins-namespace>' --ignore-not-found
```

## Troubleshooting

| Signal | Meaning | Action |
|---|---|---|
| Pod has no AWS identity | IRSA trust, annotation, or OIDC provider does not match. | Inspect the ServiceAccount annotation and role trust; do not add static keys. |
| `OCM token file permits group or other access` | Projected file mode is broader than `0400`. | Restore `defaultMode: 256` and recreate the Pod. |
| `state=unobserved` | OCM did not establish presence or absence. | Refresh the Secret or supply one independently justified per-id assertion. |
| Apply stage is skipped | `APPLY_CHANGES` remained false. | Review the dry-run artifact before starting a new approved build. |
| Artifact set is empty | The tool refused before writing its report. | Read the console refusal; do not treat `allowEmpty` as success. |
| `APPLY_FAILED` | One exact delete failed; earlier `DELETED` rows, if any, were acknowledged by EC2. | Preserve the archived report and snapshot, then reconcile their exact extent before another build. |
| `post-delete maps differ` | A final complete tag map differs unexpectedly. | Preserve the snapshot and investigate every key before another run. |
