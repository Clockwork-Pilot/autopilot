# ensure-image-hosted

Composite action that **ensures a local docker image tag exists on a GitHub-hosted runner**, using GHA-side caches because the runner is ephemeral.

For self-hosted runners use [`ensure-image-local`](../ensure-image-local/README.md). For callers that genuinely need to switch by runner type at runtime, the [`ensure-docker-image`](../ensure-docker-image/README.md) dispatcher delegates to one of these two leaves.

## What it does

Two paths, selected by whether you pass a `dockerfile`:

| `dockerfile` input | Behavior |
|---|---|
| unset | Pulls `base_image`, tags it locally under a content-addressable tag, caches the tarball via `actions/cache` keyed by the base digest. |
| set | Builds the Dockerfile (via Buildx + `docker/build-push-action`) on top of `base_image`, with Buildx's GHA layer cache (`type=gha`, scoped by `tag_prefix`). |

Fast path: if a local image with the computed content-hashed tag already exists, build/pull is skipped. (Rarely useful on hosted runners since the daemon doesn't persist across runs, but free.)

## Caching strategy

| Path | Cache |
|---|---|
| Pull | `actions/cache` over a `docker save` tarball, key = `<tag_prefix>-pullimg-<base-digest>`. Survives runner teardown. |
| Build | Buildx GHA cache (`type=gha,mode=max,scope=<tag_prefix>-buildimg`). Per-layer reuse across runs. |

GitHub already isolates the Actions cache per repo, so cross-repo poisoning isn't a risk. Within a single repo, the `tag_prefix` partitions cache scopes when the repo builds multiple images.

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `dockerfile` | no | `""` | Dockerfile path (relative to `$GITHUB_WORKSPACE`). Unset = pull-and-tag mode. |
| `context` | no | `.` | Build context directory. Only used in build mode. |
| `build_args` | no | `""` | Newline-separated `KEY=VALUE`, forwarded to `--build-arg`. Included in the content hash. |
| `base_image` | **yes** | — | Image reference. Pulled and tagged locally; also the FROM contract for any Dockerfile. The action does not rewrite your Dockerfile's `FROM`. |
| `tag_prefix` | **yes** | — | Project namespace, dual-purpose: produced docker tag (`<tag_prefix>:<hash>`) **and** GHA cache scope (`<tag_prefix>-buildimg` / `<tag_prefix>-pullimg-<digest>`). Pick something short and project-specific. Distinct projects in the same repo MUST use distinct prefixes. Do not include volatile fields (`github.sha`, run id, date) — the action already content-hashes Dockerfile + args + base digest into the tag. |

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
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - id: img
        uses: Clockwork-Pilot/autopilot/.github/actions/ensure-image-hosted@main
        with:
          dockerfile: Dockerfile.ci
          base_image: ghcr.io/acme/runtime:latest
          tag_prefix: ${{ github.repository }}-ci-img
          build_args: |
            PYTHON_VERSION=3.12
      - run: docker run --rm ${{ steps.img.outputs.image }} pytest
```
