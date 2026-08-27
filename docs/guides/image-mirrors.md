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
image_mirrors = {
  # source repository path        =  ordered list of mirrors
  "registry.redhat.io"            = ["mirror.example.com/redhat"]
  "quay.io/prometheus"            = ["mirror.example.com/quay-prometheus"]
  "cp.icr.io/cp"                  = ["mirror.example.com/cp"]
}
```

Then apply as usual. The mirrors are created after the cluster exists; adding, removing
or reordering mirrors for an existing source is an in-place update.

Confirm what was actually created — the plan shows what you asked for, this shows what
the management plane holds:

```bash
terraform output image_mirror_ids
```

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
replaces one mirror and leaves the rest untouched.

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
