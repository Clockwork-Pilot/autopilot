#!/usr/bin/env bash
# Picks the agent work branch and base branch given override precedence.
# Required env: PR_BRANCH, AGENT_BRANCH_DEFAULT, EXISTING_AGENT_BRANCH,
#   BASE_FROM_ISSUE, DEFAULT_BRANCH, GITHUB_OUTPUT.
set -u

BRANCH="${PR_BRANCH:-${EXISTING_AGENT_BRANCH:-$AGENT_BRANCH_DEFAULT}}"
BASE="${BASE_FROM_ISSUE:-$DEFAULT_BRANCH}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"
echo "branch=$BRANCH" >> "$GITHUB_OUTPUT"
echo "base_branch=$BASE" >> "$GITHUB_OUTPUT"
