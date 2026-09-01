# Verification guarantees

The automated suite emits `evidence_class=offline_simulation` as its first
line. It parses generated and static kubeconfigs and exercises fixture-backed
cache transitions without contacting Microsoft Entra, AWS or a ROSA API. Live
authentication and fresh-directory silent refresh remain `[to confirm]`.

| Guarantee | Test that proves it |
| --- | --- |
| Jenkins and GitLab run the same authentication behavior for a given mode | Byte-for-byte comparison of both Mode A scripts and both Mode B scripts |
| Common files are libraries, not entry points | Source-only execution check confirms no output or action; mode scripts alone are executable |
| A missing common directory fails closed | Each specific script is invoked with an absent expected path and reports both that path and `ROSA_COMMON_DIR` |
| Mode A contains no durable-cache or AWS path | Directory scan rejects cache-library sourcing, AWS commands and IAM examples in both Mode A paths |
| Generated kubeconfig arguments realize without literal quote bytes | Python parses the YAML and asserts issuer, client ID, cache directory, server and CA values |
| Mode A never requests `offline_access`; Mode B always requests it | Semantic parsing covers generated and all four static templates |
| A static template cannot cross the mode boundary | Each script refuses a template with the opposite scope, including `ROSA_AUTH_SKIP_KUBECONFIG_WRITE=1` |
| Job-local files are owner-only and removable | Preparation checks file modes; cleanup proves the token directory is empty |
| A seed sentinel is not treated as an archive | Fixture-backed retrieval of `pending-seed` refuses with a seed instruction |
| Empty cache state cannot be persisted | Archive packing refuses a token directory without files |
| Secrets Manager payloads never appear directly in process arguments | Fake AWS argv proves `--secret-string` receives an owner-only `file://` reference |
| Oversized archives cannot be truncated into Secrets Manager | The measured base64 payload is refused above 65,536 bytes |
| Unchanged cache state does not cause a write | Fingerprint fixtures prove the persistence skip |
| Cache archives are portable between supported runner environments | Explicit tar-to-gzip packing is unpacked and compared byte-for-byte |
| AWS caller identity has three outcomes | Fixtures prove observed, refused and `unobserved`; unreadable is never reported as empty |
| A failed automatic persist cannot overturn a successful cluster command | The `run` fixture returns the cluster command status and emits a persistence warning |
| An explicit persist reports its own failure | The `persist` fixture propagates the Secrets Manager write error |
| Mode-specific usage exposes only supported verbs | Help output is asserted separately for Mode A and Mode B |

YAML's single-quoted scalar rules are defined by the
[YAML 1.2.2 specification](https://yaml.org/spec/1.2.2/#73-flow-scalar-styles).
Semantic parsing is required because flag-presence checks cannot establish the
realized exec argument value.
