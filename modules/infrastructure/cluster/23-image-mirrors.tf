# Registry Image Mirrors
#
# Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/image_mirror
# Reference: https://github.com/terraform-redhat/terraform-provider-rhcs/blob/main/docs/guides/image-mirrors.md
# Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/images/image-configuration-hcp#images-registry-mirroring_image-configuration-hcp
# Reference: https://hypershift-docs.netlify.app/how-to/disconnected/idms-icsp-for-management-clusters/
#
# WHY THIS EXISTS
# On hosted control planes the mirror configuration is owned by the management plane and
# projected down to the guest cluster. ImageDigestMirrorSet objects authored directly on
# the guest are rejected by admission so that the two cannot diverge, which makes
# rhcs_image_mirror the supported way to configure mirroring on ROSA HCP. This matters
# most for zero-egress clusters (zero_egress = true), where workload images have to come
# from a reachable mirror rather than from the vendor's public registry.
#
# SCOPE AND LIMITS -- read before using
#
#   1. Digest references only. The API accepts a single value for the mirror type
#      ("digest"), which the provider enforces with a single-value enum validator. That
#      produces ImageDigestMirrorSet-equivalent configuration, so only image references
#      pinned by digest (registry/repo@sha256:...) are rewritten. References by TAG
#      (registry/repo:v1.2.3) are NOT rewritten. There is deliberately no `type` input
#      below: if tag mirroring is added to the API later it is a different object with
#      different semantics, and it belongs in its own variable rather than as an option
#      on this one.
#
#   2. The digests must match. Digest mirroring matches on content digest, so the mirror
#      must hold byte-identical manifests. A copy that preserves manifests (for example
#      `skopeo copy --all`) keeps the digests; images that were rebuilt, re-tagged or
#      pushed through a registry that rewrites manifest lists will have different digests
#      and will silently never match.
#
#   3. Source fallback cannot be suppressed. Upstream ImageDigestMirrorSet has a
#      mirrorSourcePolicy field (NeverContactSource); it is not exposed by this API. On a
#      zero-egress cluster the runtime still attempts the original source after the
#      mirrors are exhausted, which appears as slow pulls and long ImagePullBackOff rather
#      than as a clean failure.
#
#   4. Credentials are not managed here. If a mirror requires authentication, its entry
#      must exist in the cluster pull secret. The ROSA HCP cluster resource exposes no
#      pull-secret attribute, so that step lives outside Terraform.
#
# Applied after cluster creation; changing mirrors is an in-place update. Changing the
# source is not -- see the note on for_each keys in the variable description.

resource "rhcs_image_mirror" "this" {
  # Keyed by source repository path so that each mirror has a stable, readable address in
  # the plan, and so that a duplicate source is impossible to express.
  for_each = local.persists_through_sleep ? var.image_mirrors : {}

  cluster_id = one(rhcs_cluster_rosa_hcp.main[*].id)

  # The source repository path being mirrored, e.g. "registry.redhat.io" or
  # "quay.io/prometheus". Immutable: the provider marks this RequiresReplace, so editing a
  # source destroys and recreates the mirror object.
  source = each.key

  # Mirrors are tried in the order given -- put the closest or most reliable first.
  mirrors = each.value

  # "digest" is the only value the API accepts today. Set explicitly rather than left to
  # the provider default so that the constraint is visible at the call site.
  type = "digest"

  depends_on = [rhcs_cluster_rosa_hcp.main]
}
