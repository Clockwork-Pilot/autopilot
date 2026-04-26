# ensure-image-local

Composite action that **ensures a local docker image tag exists on a self-hosted runner**, trusting the docker daemon's persistent layer cache.

For GitHub-hosted runners use [`ensure-image-hosted`](../ensure-image-hosted/README.md). For callers that need to switch at runtime, the [`ensure-docker-image`](../ensure-docker-image/README.md) dispatcher delegates to one of these two leaves.

## What it does

Two paths, selected by whether you pass a `dockerfile`:

| `dockerfile` input | Behavior |
|---|---|
| unset | Pulls `base_image`, tags it locally under a content-addressable tag. The daemon's local cache makes the second pull a no-op. |
| set | Builds the Dockerfile (via Buildx + `docker/build-push-action`) on top of `base_image`. No `cache-from`/`cache-to` — buildx reuses the daemon's local layer cache directly. |

Fast path (both modes): if a local image with the computed content-hashed tag already exists, the build/pull step is skipped entirely. On a long-lived self-hosted runner this means most invocations are no-ops.

## Caching strategy

The docker daemon's persistent local layer cache. No external cache, no `actions/cache`, no GHA layer cache. The runner is long-lived; layers stay between jobs.

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `dockerfile` | no | `""` | Dockerfile path (relative to `$GITHUB_WORKSPACE`). Unset = pull-and-tag mode. |
| `context` | no | `.` | Build context directory. Only used in build mode. |
| `build_args` | no | `""` | Newline-separated `KEY=VALUE`, forwarded to `--build-arg`. Included in the content hash. |
| `base_image` | **yes** | — | Image reference. Pulled and tagged locally; also the FROM contract for any Dockerfile. The action does not rewrite your Dockerfile's `FROM`. |
| `tag_prefix` | **yes** | — | Project namespace. The produced local tag is `<tag_prefix>:<hash>` — the REPOSITORY column in `docker images`. One docker daemon is typically shared across every repo that runs on the machine, so distinct projects MUST use distinct prefixes to keep `docker images` clean and avoid tag collisions. Pick something short and project-specific (`agent-img`, `check-img`). |

## Outputs

| Output | |
|---|---|
| `image` | Fully qualified local tag of the produced image. |
| `cache_hit` | `true` if the local tag pre-existed and neither build nor pull ran. |
| `digest` | Local image ID (`sha256:...`). |

## Usage

```yaml
jobs:
  build:
    runs-on: [self-hosted, my-label]
    steps:
      - uses: actions/checkout@v4
      - id: img
        uses: Clockwork-Pilot/autopilot/.github/actions/ensure-image-local@main
        with:
          dockerfile: Dockerfile.ci
          base_image: ghcr.io/acme/runtime:latest
          tag_prefix: agent-img
      - run: docker run --rm ${{ steps.img.outputs.image }} pytest
```
