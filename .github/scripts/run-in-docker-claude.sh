#!/usr/bin/env bash
# Run agent with single prompt inside the docker image with standard mounts.
# Hooks log is truncated on the host, then followed from inside the container
# so events stream to docker's stdout (which the workflow captures) without
# any host-side tailer process.
#
# Usage: run-in-docker-claude.sh [--allow-git-commit]
# Required env: MODEL, PROMPT, DOCKER_FILES, GITHUB_WORKSPACE
# Optional env: TIMEOUT_SECS (0 or unset = no timeout), EXTRA_DOCKER_ARGS
# Returns container's exit code (or timeout's).
set -uo pipefail

MODEL="${MODEL:-claude-haiku-4-5}"
: "${PROMPT:?PROMPT required}"
: "${DOCKER_FILES:?DOCKER_FILES required}"
: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE required}"
: "${AGENT_IMAGE:?AGENT_IMAGE required (digest-pinned ref like repo@sha256:...)}"
TIMEOUT_SECS="${TIMEOUT_SECS:-180}"

PROXY_WRAPPER=(-e PROXY_WRAPPER_CONFIG=/docker-scripts/proxy_wrapper_config.json)
[ "${1:-}" = "--allow-git-commit" ] && PROXY_WRAPPER=()

export CLAUDE_HOOKS_LOG_FILE=/home/node/.claude/hooks.log

# Capture the container id so we can `docker kill` it on cancellation. Without
# this, GitHub's cancel signal kills the runner step but the docker daemon
# keeps the container running, so the agent finishes its turn anyway.
# `timeout --foreground` propagates signals to `docker run`.
CIDFILE=$(mktemp -u)
trap 'CID=$(cat "$CIDFILE" 2>/dev/null || true); [ -n "$CID" ] && docker kill "$CID" >/dev/null 2>&1 || true; rm -f "$CIDFILE"' EXIT INT TERM

RUN=(timeout --foreground "$TIMEOUT_SECS" docker run --rm --cidfile "$CIDFILE"
  -e AGENT_FILE_ACCESS_RULES=/docker-scripts/y2-plugin-deny-file-rules.json
  -e CLAUDE_HOOKS_LOG_FILE
  "${PROXY_WRAPPER[@]}"
  -e DISABLE_STOP_HOOK=
  -e MODEL
  -e PROMPT
  # Match the host runner's UID/GID so the entrypoint chowns the
  # bind-mounted workspace and docker-files dirs to the same UID that
  # already owns them on the host, and gosu-drops the process there.
  # Avoids host file-ownership mutation that would break post-job
  # git cleanup and other host-side steps.
  -e "HOST_UID=$(id -u)"
  -e "HOST_GID=$(id -g)"
  -v "$DOCKER_FILES/.cargo:/home/node/.cargo:Z"
  -v "$DOCKER_FILES/.credentials:/home/node/.claude:Z"
  -v "$DOCKER_FILES/.claude.local.json:/home/node/.claude.json:Z"
  -v "$DOCKER_FILES/.local:/home/node/.local:Z"
  -v "$GITHUB_WORKSPACE:/workspace:Z"
  ${EXTRA_DOCKER_ARGS:-}
  "$AGENT_IMAGE"
  bash -c '
    /docker-scripts/tail-hooks-log.sh "$CLAUDE_HOOKS_LOG_FILE" &
    TAIL_PID=$!
    trap "kill $TAIL_PID 2>/dev/null || true" EXIT
    source /docker-scripts/user-entrypoint.sh
    claude --dangerously-skip-permissions --model "$MODEL" --plugin-dir /plugin -p "$PROMPT"
  '
)

"${RUN[@]}"

