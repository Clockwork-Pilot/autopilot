# Template for building your own agent image.
#
# Start from the pinned autopilot base image and layer in your dependencies.
# The RUN block below is where you'd paste the contents of an
# `image_setup_script` that has outgrown being inlined in the caller workflow.
#
# Pin to a digest (`@sha256:...`) rather than `:latest` for reproducibility.
# Look up the current digest with:
#   docker manifest inspect ghcr.io/clockwork-pilot/autopilot-ws:latest \
#     | jq -r '.manifests[0].digest // .config.digest'
FROM ghcr.io/clockwork-pilot/autopilot-ws:latest

USER 0

RUN set -euo pipefail \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      # add your system packages here, e.g.:
      # ffmpeg \
      # libsndfile1 \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# The base image defines USER node; restate it here so any future edits that
# add RUN layers above this line can't accidentally leave the image running as
# root. coding-agent.yml relies on the container default being unprivileged.
USER node
