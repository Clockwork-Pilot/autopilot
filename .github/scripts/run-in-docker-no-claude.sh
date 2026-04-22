#!/usr/bin/env bash
# Run an arbitrary bash command inside the agent docker image with only the
# workspace mounted. No claude credentials, caches, or claude-specific env —
# for callers that just need the toolchain image (e.g. constraint checks).
#
# Required env: GITHUB_WORKSPACE
# Usage: run-in-docker-no-claude.sh <bash command string>
set -uo pipefail

: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE required}"
: "${AGENT_IMAGE:?AGENT_IMAGE required (digest-pinned ref like repo@sha256:...)}"
CMD="${1:?bash command string required}"

docker run --rm \
  -v "$GITHUB_WORKSPACE:/workspace" \
  "$AGENT_IMAGE" \
  bash -c "source /docker-scripts/user-entrypoint.sh; $CMD"
