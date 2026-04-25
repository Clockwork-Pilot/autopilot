#!/bin/bash
set -e

# Generic workflow-step dispatcher.
#
# Two execution paths, decided by the job's shape:
#
# (A) Composite-action job — the job invokes a local composite via
#     `uses: ./.github/actions/<name>` plus a `with:` block. The dispatcher
#     loads `.github/actions/<name>/action.yml`, resolves `with:` expressions
#     against --inputs JSON, then walks `runs.steps[]` from action.yml,
#     evaluating each step's `env:` (substituting `${{ inputs.X }}`) and
#     executing its `run:` block. This exercises the action.yml contract on
#     every test run — malformed metadata fails the harness.
#
# (B) Inline-run job — the job has its own `env:` and `run:` steps. The
#     dispatcher resolves the job's `env:` block against --inputs JSON and
#     executes the `run:` blocks directly.
#
# `--inputs` JSON keys match the workflow's expression strings verbatim
# (e.g. "needs.fetch-issue.outputs.title", "inputs.issue_number"). Each
# `${{ expr }}` in env:/with: is resolved against that map.
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

mkdir -p "$ARTIFACT_PATH"
export GITHUB_OUTPUT="$ARTIFACT_PATH/github_output.txt"
: > "$GITHUB_OUTPUT"

# Resolve a `${{ expr }}` literal against $INPUTS_JSON. If the value is not
# a `${{ ... }}` wrapper, return it verbatim.
resolve_expr() {
  local v="$1"
  if [[ "$v" =~ ^\$\{\{[[:space:]]*(.+)[[:space:]]*\}\}$ ]]; then
    local expr="${BASH_REMATCH[1]}"
    expr="${expr#"${expr%%[![:space:]]*}"}"
    expr="${expr%"${expr##*[![:space:]]}"}"
    echo "$INPUTS_JSON" | jq -r --arg k "$expr" '.[$k] // ""'
  else
    echo "$v"
  fi
}

# Detect path (A): a `uses:` step pointing at ./.github/actions/<name>.
ACTION_REF=$(yq -r ".jobs[\"$STEP_ID\"].steps[] | select(.uses != null) | .uses | select(startswith(\"./.github/actions/\"))" "$WF" | head -1)

if [ -n "$ACTION_REF" ] && [ "$ACTION_REF" != "null" ]; then
  # ----- Path (A): composite action -----
  ACTION_DIR="${ACTION_REF#./}"
  ACTION_YML="$ACTION_DIR/action.yml"
  [ -f "$ACTION_YML" ] || { echo "Error: $ACTION_YML missing" >&2; exit 1; }

  # GATE: load action.yml. Malformed YAML fails here.
  yq '.' "$ACTION_YML" >/dev/null

  # Index of the matching `uses:` step, used to select its `with:` block.
  USES_IDX=$(yq -r "[.jobs[\"$STEP_ID\"].steps[] | .uses] | map(. == \"$ACTION_REF\") | index(true)" "$WF")

  # Resolve each `with:` value against INPUTS_JSON; populate INPUTS[name]=value.
  declare -A INPUTS
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    k="${line%%=*}"
    v="${line#*=}"
    INPUTS["$k"]="$(resolve_expr "$v")"
  done < <(yq -r ".jobs[\"$STEP_ID\"].steps[$USES_IDX].with // {} | to_entries[] | \"\(.key)=\(.value)\"" "$WF")

  export GITHUB_ACTION_PATH="$PWD/$ACTION_DIR"

  # Walk runs.steps[]: substitute `${{ inputs.X }}` in env values, export, exec run.
  step_count=$(yq -r '.runs.steps | length' "$ACTION_YML")
  for i in $(seq 0 $((step_count - 1))); do
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      k="${line%%=*}"
      v="${line#*=}"
      while [[ "$v" =~ \$\{\{[[:space:]]*inputs\.([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\}\} ]]; do
        name="${BASH_REMATCH[1]}"
        v="${v//${BASH_REMATCH[0]}/${INPUTS[$name]:-}}"
      done
      export "$k=$v"
    done < <(yq -r ".runs.steps[$i].env // {} | to_entries[] | \"\(.key)=\(.value)\"" "$ACTION_YML")

    RUN=$(yq -r ".runs.steps[$i].run // \"\"" "$ACTION_YML")
    [ -z "$RUN" ] && continue
    if [ $QUIET -eq 1 ]; then
      bash -c "$RUN" >/dev/null
    else
      bash -c "$RUN"
    fi
  done
  exit 0
fi

# ----- Path (B): inline-run job -----
# Resolve the job's `env:` block against INPUTS_JSON, export each entry.
while IFS= read -r line; do
  [ -z "$line" ] && continue
  k="${line%%=*}"
  v="${line#*=}"
  export "$k=$(resolve_expr "$v")"
done < <(yq -r ".jobs[\"$STEP_ID\"].env // {} | to_entries[] | \"\(.key)=\(.value)\"" "$WF")

RUN_BLOCKS=$(yq -r ".jobs[\"$STEP_ID\"].steps[] | select(.run != null) | .run" "$WF")
if [ -z "$RUN_BLOCKS" ] || [ "$RUN_BLOCKS" = "null" ]; then
  echo "Error: No run steps found in job '$STEP_ID'" >&2
  exit 1
fi

if [ $QUIET -eq 1 ]; then
  bash -c "$RUN_BLOCKS" >/dev/null
else
  bash -c "$RUN_BLOCKS"
fi
