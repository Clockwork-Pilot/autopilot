#!/bin/bash
set -e

# Generic workflow-step dispatcher.
# Runs a job's `run:` blocks with a simulated env, using the job's declared
# `env:` block as the single source of truth for inputs. Each expression
# `${{ expr }}` in an env value is resolved against the --inputs JSON,
# whose keys are the expression paths themselves (e.g. "needs.fetch-issue.outputs.title",
# "inputs.issue_number").
#
# Usage: act-step-dispatch.sh <workflow> <step_id> [--inputs JSON] [--artifact-server-path PATH] [-q|--quiet]

WORKFLOW="${1:?Workflow file required (e.g., coding-agent.yml)}"
STEP_ID="${2:?Step ID required (e.g., parse-issue)}"
INPUTS_JSON='{}'
export ARTIFACT_PATH='/tmp/act-artifacts'
QUIET=0
shift 2

while [[ $# -gt 0 ]]; do
  case $1 in
    --inputs) INPUTS_JSON="$2"; shift 2 ;;
    --artifact-server-path) ARTIFACT_PATH="$2"; export ARTIFACT_PATH; shift 2 ;;
    -q|--quiet) QUIET=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

WF=".github/workflows/$WORKFLOW"
if [ ! -f "$WF" ]; then
  echo "Error: Workflow not found: $WF" >&2
  exit 1
fi

if ! grep -q "^  $STEP_ID:" "$WF"; then
  echo "Error: Step '$STEP_ID' not found in $WORKFLOW" >&2
  exit 1
fi

# Resolve job's env: block. For each entry, if value is a ${{ expr }} literal,
# look up expr (stripped of the `${{ }}` wrapper, trimmed) in INPUTS_JSON.
# Otherwise use the literal value.
while IFS= read -r -d '' entry; do
  k="${entry%%=*}"
  v="${entry#*=}"
  [ -z "$k" ] && continue
  if [[ "$v" =~ ^\$\{\{[[:space:]]*(.+)[[:space:]]*\}\}$ ]]; then
    expr="${BASH_REMATCH[1]}"
    expr="${expr#"${expr%%[![:space:]]*}"}"
    expr="${expr%"${expr##*[![:space:]]}"}"
    resolved=$(echo "$INPUTS_JSON" | jq -r --arg k "$expr" '.[$k] // ""')
  else
    resolved="$v"
  fi
  export "$k=$resolved"
done < <(yq -j ".jobs[\"$STEP_ID\"].env // {} | to_entries[] | \"\(.key)=\(.value)\u0000\"" "$WF")

RUN_BLOCKS=$(yq -r ".jobs[\"$STEP_ID\"].steps[] | select(.run != null) | .run" "$WF")
if [ -z "$RUN_BLOCKS" ] || [ "$RUN_BLOCKS" = "null" ]; then
  echo "Error: No run steps found in job '$STEP_ID'" >&2
  exit 1
fi

mkdir -p "$ARTIFACT_PATH"
export GITHUB_OUTPUT="$ARTIFACT_PATH/github_output.txt"
: > "$GITHUB_OUTPUT"

if [ $QUIET -eq 1 ]; then
  bash -c "$RUN_BLOCKS" >/dev/null
else
  bash -c "$RUN_BLOCKS"
fi
