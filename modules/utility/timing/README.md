# Timing Module

Captures timestamps at different stages of deployment to measure duration. Useful for debugging and performance analysis.

## Usage

```hcl
module "cluster_timing" {
  source = "../modules/utility/timing"

  enabled = var.enable_timing
  stage   = "cluster-creation"

  # Track cluster completion - timing ends when cluster is ready
  dependency_ids = [module.cluster.cluster_id]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| enabled | Enable timing capture. When false, no resources are created. | `bool` | `false` | no |
| stage | Name of the stage being timed (e.g., 'cluster-creation', 'full-deployment'). | `string` | `"cluster-creation"` | no |
| dependency_ids | List of resource IDs or values that this timing depends on. The end time is captured after all dependencies complete. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| start_time | Timestamp when deployment started (RFC3339 format). |
| end_time | Timestamp when deployment completed (RFC3339 format). |
| duration_seconds | Total deployment duration in seconds. |
| duration_minutes | Total deployment duration in whole minutes. |
| duration_human | Human-readable duration (e.g., '15m 32s'). |
| timing_summary | Complete timing summary for the stage. |

## Reference

Based on: `./reference/rosa-tf/modules/utility/timing/`
