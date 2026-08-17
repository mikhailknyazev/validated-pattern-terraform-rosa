# Private GitOps with In-Cluster Gitea

This guide has been consolidated into **[Local Multi-Repo Development](local-multi-repo-dev.md)**.

The primary local development workflow is:

```bash
make cluster.<profile>.bootstrap-private
make dev.private.sync DEV_CLUSTER_NAME=<profile>
```

See the [full guide](local-multi-repo-dev.md) for architecture, prerequisites, troubleshooting, and the optional `apply-local` escape hatch.
