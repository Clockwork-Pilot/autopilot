#!/usr/bin/env bash
# Parses issue title/body into structured agent-run inputs.
# Required env: TITLE, BODY_RAW, ISSUE_NUMBER, GITHUB_OUTPUT.
set -u

TITLE="${TITLE:-}"
BODY_RAW="${BODY_RAW:-}"
ISSUE_NUMBER_IN="${ISSUE_NUMBER:-}"

BODY_RAW=$(printf '%s' "$BODY_RAW" | tr -d '\r')

BRANCH_SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-\+/-/g;s/^-//;s/-$//' | cut -c1-100)

DELIM_COUNT=$(printf '%s\n' "$BODY_RAW" | grep -c '^---[[:space:]]*$' || true)
if [ "${DELIM_COUNT:-0}" -ge 2 ]; then
  AGENT_TASK_TEXT=$(printf '%s\n' "$BODY_RAW" | sed '0,/^---[[:space:]]*$/d' | sed '0,/^---[[:space:]]*$/d')
  YAML_PART=$(printf '%s\n' "$BODY_RAW" | sed -n '/^---[[:space:]]*$/,/^---[[:space:]]*$/p' | sed '1d;$d')
else
  AGENT_TASK_TEXT="$BODY_RAW"
  YAML_PART=""
fi

PR_BRANCH=""
BASE_BRANCH=""
TIMEOUT_MINS=""
MODEL=""
MERGE_INTO_UPSTREAM=""
if [ -n "$YAML_PART" ]; then
  PR_BRANCH=$(echo "$YAML_PART" | yq -r '.pr_branch // ""')
  BASE_BRANCH=$(echo "$YAML_PART" | yq -r '.base_branch // ""')
  TIMEOUT_MINS=$(echo "$YAML_PART" | yq -r '.timeout // ""')
  MODEL=$(echo "$YAML_PART" | yq -r '.model // ""')
  MERGE_INTO_UPSTREAM=$(echo "$YAML_PART" | yq -r '.merge_into_upstream // ""')
fi
[ "$PR_BRANCH" = "null" ] && PR_BRANCH=""
[ "$BASE_BRANCH" = "null" ] && BASE_BRANCH=""
[ "$TIMEOUT_MINS" = "null" ] && TIMEOUT_MINS=""
[ "$MODEL" = "null" ] && MODEL=""
[ "$MERGE_INTO_UPSTREAM" = "null" ] && MERGE_INTO_UPSTREAM=""
if [ "$MERGE_INTO_UPSTREAM" = "true" ]; then
  MERGE_INTO_UPSTREAM="true"
else
  MERGE_INTO_UPSTREAM=""
fi

TIMEOUT_SECS=$(( ${TIMEOUT_MINS:-10} * 60 ))
MODEL="${MODEL:-claude-haiku-4-5}"
AGENT_BRANCH_DEFAULT="agent/${ISSUE_NUMBER_IN}-${BRANCH_SLUG}"

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"
echo "pr_branch=$PR_BRANCH" >> "$GITHUB_OUTPUT"
echo "base_branch=$BASE_BRANCH" >> "$GITHUB_OUTPUT"
echo "timeout_secs=$TIMEOUT_SECS" >> "$GITHUB_OUTPUT"
echo "model=$MODEL" >> "$GITHUB_OUTPUT"
echo "agent_branch_default=$AGENT_BRANCH_DEFAULT" >> "$GITHUB_OUTPUT"
echo "merge_into_upstream=$MERGE_INTO_UPSTREAM" >> "$GITHUB_OUTPUT"
echo "agent_task_text<<EOF_AGENT_TASK_TEXT" >> "$GITHUB_OUTPUT"
printf '%s\n' "$AGENT_TASK_TEXT" >> "$GITHUB_OUTPUT"
echo "EOF_AGENT_TASK_TEXT" >> "$GITHUB_OUTPUT"
