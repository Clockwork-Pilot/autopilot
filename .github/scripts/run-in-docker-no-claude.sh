#!/usr/bin/env bash
# Run an arbitrary bash command inside the agent docker image with only the
# workspace mounted. No claude credentials, caches, or claude-specific env —
# for callers that just need the toolchain image (e.g. constraint checks).
#
# Env (optional, with local-friendly defaults):
#   GITHUB_WORKSPACE — defaults to $PWD so the script is usable outside CI.
#   AGENT_IMAGE      — defaults to ghcr.io/clockwork-pilot/autopilot-ws:latest.
# Usage: run-in-docker-no-claude.sh <bash command string>
set -uo pipefail

: "${GITHUB_WORKSPACE:=$PWD}"
: "${AGENT_IMAGE:=ghcr.io/clockwork-pilot/autopilot-ws:latest}"
CMD="${1:?bash command string required}"

if command -v docker >/dev/null 2>&1; then
  docker run --rm \
    -v "$GITHUB_WORKSPACE:/workspace" \
    "$AGENT_IMAGE" \
    bash -c "source /docker-scripts/user-entrypoint.sh; $CMD"
else
  # No docker available (local dev / minimal sandbox): run the command
  # directly against the host shell. Tooling must be in PATH.
  CLAUDE_PROJECT_ROOT="$GITHUB_WORKSPACE" bash -c "$CMD"
fi
