# ensure-docker-image

**Dispatcher** composite action: routes to one of two leaf actions based on the runner type, with a unified input/output surface so callers don't have to branch.

| Runner type | Routes to | Caching |
|---|---|---|
| GitHub-hosted (`ubuntu-latest`, etc.) | [`ensure-image-hosted`](../ensure-image-hosted/README.md) | `actions/cache` (pull) + Buildx `type=gha` (build) |
| Self-hosted | [`ensure-image-local`](../ensure-image-local/README.md) | docker daemon's persistent local layer cache |

The two leaves have very different caching strategies; this dispatcher exists for callers that genuinely need to switch at runtime. **In almost all cases the caller's runner type is static and you should call the leaf directly** — fewer indirections, README that matches the runtime, no dispatcher input plumbing.

## When to use which

```
runs-on: ubuntu-latest          → uses: …/ensure-image-hosted@main
runs-on: [self-hosted, label]   → uses: …/ensure-image-local@main
runs-on: <varies at runtime>    → uses: …/ensure-docker-image@main   (rare)
```

The reusable workflow [`workflows/ensure-docker-image.yml`](../../workflows/ensure-docker-image.yml) is a thin self-hosted-only wrapper that surfaces `outputs.docker_image` to downstream reusable workflows running on the same runner.

## Inputs

Same as the leaves — see [`ensure-image-hosted`](../ensure-image-hosted/README.md#inputs) or [`ensure-image-local`](../ensure-image-local/README.md#inputs). All inputs are forwarded as-is to the selected leaf.

| Input | Required | Default |
|---|---|---|
| `dockerfile` | no | `""` |
| `context` | no | `.` |
| `build_args` | no | `""` |
| `base_image` | **yes** | — |
| `tag_prefix` | **yes** | — |

## Outputs

| Output | |
|---|---|
| `image` | Fully qualified local tag of the produced image. |
| `cache_hit` | `true` if the local tag pre-existed and neither build nor pull ran. |
| `digest` | Local image ID (`sha256:...`). |

Outputs are merged from whichever leaf actually ran.

## Usage

```yaml
jobs:
  prep:
    runs-on: ${{ inputs.runs_on }}     # genuinely varies between calls
    steps:
      - uses: actions/checkout@v4
      - id: img
        uses: Clockwork-Pilot/autopilot/.github/actions/ensure-docker-image@main
        with:
          base_image: ghcr.io/acme/runtime:latest
          tag_prefix: ${{ github.repository }}-runtime
      - run: docker run --rm ${{ steps.img.outputs.image }} my-command
```

## See also

- [`ensure-image-hosted`](../ensure-image-hosted/README.md) — the GitHub-hosted leaf.
- [`ensure-image-local`](../ensure-image-local/README.md) — the self-hosted leaf.
- [`workflows/ensure-docker-image.yml`](../../workflows/ensure-docker-image.yml) — reusable workflow wrapper that pins this composite to `[self-hosted, runner_label]` so a downstream reusable workflow can land on the same runner.
