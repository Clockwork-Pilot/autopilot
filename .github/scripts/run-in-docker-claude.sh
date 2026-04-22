#!/usr/bin/env bash
# Run `claude -p` inside the agent docker image with standard mounts.
# Hooks log is truncated on the host, then followed from inside the container
# so events stream to docker's stdout (which the workflow captures) without
# any host-side tailer process.
#
# Usage: run-in-docker-claude.sh [--allow-git-commit]
# Required env: MODEL, PROMPT, DOCKER_FILES, GITHUB_WORKSPACE
# Optional env: TIMEOUT_SECS (0 or unset = no timeout), CLAUDE_EXTRA_DOCKER_ARGS
# Returns claude's exit code (or timeout's).
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

RUN=(timeout "$TIMEOUT_SECS" docker run --rm
  -e CLAUDE_FILE_RULES=/docker-scripts/y2-plugin-deny-file-rules.json
  -e CLAUDE_HOOKS_LOG_FILE
  "${PROXY_WRAPPER[@]}"
  -e DISABLE_STOP_HOOK=
  -e MODEL
  -e PROMPT
  -v "$DOCKER_FILES/.cargo:/home/node/.cargo:Z"
  -v "$DOCKER_FILES/.credentials:/home/node/.claude:Z"
  -v "$DOCKER_FILES/.claude.local.json:/home/node/.claude.json:Z"
  -v "$DOCKER_FILES/.local:/home/node/.local:Z"
  -v "$GITHUB_WORKSPACE:/workspace:Z"
  ${CLAUDE_EXTRA_DOCKER_ARGS:-}
  "$AGENT_IMAGE"
  bash -c '
    /workspace/.github/scripts/tail-hooks-log.sh "$CLAUDE_HOOKS_LOG_FILE" &
    TAIL_PID=$!
    trap "kill $TAIL_PID 2>/dev/null || true" EXIT
    source /docker-scripts/user-entrypoint.sh
    claude --dangerously-skip-permissions --model "$MODEL" --plugin-dir /plugin -p "$PROMPT"
  '
)

"${RUN[@]}"

