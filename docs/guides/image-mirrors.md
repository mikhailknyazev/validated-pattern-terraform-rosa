# Registry Image Mirrors

Redirect the cluster's image pulls to a mirror registry, so workload images can be
served from somewhere reachable instead of from a vendor's public registry. This is what
makes third-party operator content — ISV bundles, partner catalogs, internal builds —
installable on a `zero_egress = true` cluster.

## Why this is not an in-cluster object

On classic OpenShift you would apply an `ImageDigestMirrorSet` to the cluster. On a
hosted control plane that does not work: mirror configuration is owned by the management
plane and projected down to the guest, and the guest rejects locally-authored mirror
objects by admission so the two cannot diverge.

The supported path is the management-plane API, which this pattern exposes as the
`image_mirrors` variable.

!!! tip "If you already tried the in-cluster object"
    Run `oc apply --dry-run=server -f your-idms.yaml`. A server-side dry run performs
    full admission and persists nothing, so it reproduces the exact rejection message
    without changing the cluster — useful evidence for a support case.

## Usage

Add the mirrors to your cluster's `terraform.tfvars`:

```hcl
# Covers: image_mirrors
# Does: Maps each source repository to its ordered digest-mirror candidates.
# Why: Source-keyed identity matches the API and makes duplicate sources impossible.
# Change: Reordering changes preference; changing a key replaces that mirror object.
# Trap: Entries are repository paths, never URLs, tags, or digest references.
# Evidence: https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/image_mirror
image_mirrors = {
  # source repository path        =  ordered list of mirrors
  "registry.redhat.io"            = ["mirror.example.com/redhat"]
  "quay.io/prometheus"            = ["mirror.example.com/quay-prometheus"]
  "cp.icr.io/cp"                  = ["mirror.example.com/cp"]
}
```

Then apply as usual. The mirrors are created after the cluster exists. Editing the
ordered mirror list for an existing source plans as an in-place provider update, but
that path has not been measured on a live cluster.

!!! warning "Observed behavior, not vendor-documented — ROSA HCP 4.22.5"
    Creating or deleting an `rhcs_image_mirror` was followed by managed worker
    replacement beginning roughly 7.5 minutes after create and 14 minutes after delete,
    and settling within about 30 minutes. The guest `ImageDigestMirrorSet` converged
    earlier, so guest convergence was not lifecycle convergence. Routes kept returning
    `200`, at least three workers remained Ready, and no ClusterOperator degraded; the
    measured cost was node churn and surge capacity, not service loss. Batch mirror
    additions into one apply and treat it as a disruption window.

## Confirm it took effect

`terraform output image_mirror_ids` is not one of these reads. It prints identifiers
recorded in Terraform state at the last apply; it makes no management or guest API call.

1. **Management plane — did the service accept the mapping?**

   ```bash
   # Covers: --cluster
   # Does: Scopes the live management-plane read to the intended cluster.
   # Why: An unscoped list can mix unrelated clusters and hide missing acceptance.
   # Change: Changing the id reads a different cluster's mirror inventory.
   # Trap: This read proves service acceptance, not guest realization.
   # Evidence: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/cli_tools/rosa-cli
   rosa list image-mirrors --cluster <cluster-id>
   ```

   This reads the ROSA management API. The `rhcs_image_mirrors` data source is the
   Terraform equivalent when a machine-readable live read is preferable.

2. **Guest — was the mapping projected to the cluster?** Poll; do not sleep once.

   ```bash
   until oc get imagedigestmirrorset -o yaml | grep -F '<source-host>/<source-repository>'; do
     sleep 15
   done
   ```

   This reads the guest Kubernetes API. Management acceptance does not imply guest
   realization. On the same service version, first successful reads already contained
   the mapping at upper bounds of about 403 and 11,995 seconds; failed reads in between
   timed out and do not prove absence. Use a predicate, not a fixed realization delay.

3. **Workload — can an uncached digest-pinned pull succeed?**

   ```yaml
   # Covers: apiVersion, kind, metadata, name, spec, restartPolicy, containers, image, imagePullPolicy, command
   # Does: Creates one disposable Pod that always performs a digest-pinned image pull.
   # Why: A fresh pull prevents node cache from masquerading as mirror success.
   # Change: A tag reference bypasses this digest mapping; cache policy weakens proof.
   # Trap: Success proves redirection only when the original source is independently unreachable.
   # Evidence: https://kubernetes.io/docs/concepts/containers/images/#image-pull-policy
   apiVersion: v1
   kind: Pod
   metadata:
     name: mirror-verification
   spec:
     restartPolicy: Never
     containers:
       - name: probe
         image: <source-host>/<source-repository>@sha256:<manifest-digest>
         imagePullPolicy: Always
         command: ["sleep", "300"]
   ```

   Apply the manifest, then run `oc wait --for=condition=Ready pod/mirror-verification
   --timeout=5m`. This reads workload state through the guest API. On a zero-egress test
   where the source is unreachable and only the mirror is reachable, success proves the
   rewrite by construction. Elsewhere, use node-level `crictl` when mirror provenance is
   required; successful kubelet Events echo the source reference from the Pod spec.

## The three layers

A correctly configured mirror still fails if one of the layers beneath it is missing.
They fail differently, and the hostname in the error tells you which one you are on.

| Layer | What it does | Where it is configured | Failure signature |
|---|---|---|---|
| **Rewrite** | Redirects the pull to your mirror | `image_mirrors` (this guide) | The **source** hostname still appears in the pull error |
| **Reachability** | Nodes can reach the mirror | Your VPC: routing, DNS, VPC endpoints, egress proxy | Timeout or DNS failure naming the **mirror** host |
| **Trust** | Node trusts the mirror's certificate | Cluster registry configuration (`additional_trusted_ca`) | `x509: certificate signed by unknown authority` |
| **Auth** | Credentials for the mirror | Cluster pull secret — **not managed by Terraform** | `401 Unauthorized` from the mirror |

## Limits worth knowing before you rely on this

### Digest references only

The API accepts one mirror type, `digest`, so this produces `ImageDigestMirrorSet`
-equivalent configuration. Only references pinned by digest
(`registry/repo@sha256:...`) are rewritten. **References by tag
(`registry/repo:v1.2.3`) are not.**

For ISV bundles this is the most common surprise: the catalog and bundle images are
usually digest-pinned, but sidecars, init containers and anything overridable in a Helm
values file are frequently tag-referenced, and those keep reaching for the original
registry.

!!! warning "Audit your manifests for tag references"
    Before concluding a mirror is broken, check whether the failing image is referenced
    by tag. If it is, the mirror was never going to apply to it.

### The digests must match

Digest mirroring matches on the content digest, so the mirror has to hold byte-identical
manifests. A copy that preserves manifests (for example `skopeo copy --all`) keeps the
digests. Images that were rebuilt, re-tagged, or pushed through a registry that rewrites
manifest lists will have **different digests and will silently never match** — the pull
simply is not redirected, with no error saying why.

Verify one image end to end before mirroring a whole catalog.

### `source` is a repository path

Give the repository path you actually pull from — `quay.io/prometheus`, not
`https://quay.io` and not `quay.io/prometheus/prometheus:v2.51.0`. The variable rejects a
URL scheme, a digest suffix and a tag suffix for this reason. A registry port
(`mirror.example.com:5000`) is accepted.

### `source` is immutable

Changing a source destroys and recreates that mirror object — the API marks it
replace-forcing. Since the map key *is* the source, editing a key in `image_mirrors`
leaves the other Terraform resource addresses unchanged. It does not imply that the
managed worker lifecycle is untouched; see the observed create/delete behavior above.

### Fallback to the source cannot be suppressed

Upstream `ImageDigestMirrorSet` has a `mirrorSourcePolicy` field (`NeverContactSource`);
it is not exposed by this API. On a zero-egress cluster the runtime still attempts the
original source after exhausting the mirrors, so a missing image shows up as **slow
pulls and long `ImagePullBackOff`** rather than a clean failure. Do not read that timeout
as a misconfigured mirror.

### Credentials live outside Terraform

The ROSA HCP cluster resource exposes no pull-secret attribute. If your mirror requires
authentication, add it to the cluster pull secret separately. This is the layer teams
most often forget to automate, because the other two are visible in the plan and this one
is not.

## Troubleshooting order

1. Is the failing image referenced by **tag**? If so, the mirror does not apply to it.
2. Does the pull error name the **source** host or the **mirror** host? Source means the
   rewrite is not matching; mirror means you are past the rewrite and on to reachability,
   trust or auth.
3. Compare the digest at the source with the digest at your mirror.
4. From a node's perspective, is the mirror host reachable at all?
5. `x509` error → trust. `401` → pull secret.

## References

- [RHCS provider — image mirrors guide](https://github.com/terraform-redhat/terraform-provider-rhcs/blob/main/docs/guides/image-mirrors.md)
- [RHCS provider — `rhcs_image_mirror` resource](https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/image_mirror)
- [ROSA — image registry configuration on hosted control planes](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/images/image-configuration-hcp#images-registry-mirroring_image-configuration-hcp)
- [HyperShift — IDMS/ICSP for management clusters](https://hypershift-docs.netlify.app/how-to/disconnected/idms-icsp-for-management-clusters/)
- [Zero Egress ECR Access](zero-egress-ecr-access.md) — the companion pattern for pulling
  application images from ECR on a zero-egress cluster
