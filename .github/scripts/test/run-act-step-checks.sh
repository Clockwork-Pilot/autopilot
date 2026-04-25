#!/bin/bash
# Usage: run-act-step-checks.sh <workflow> <step>
# Dispatches <step> from <workflow> against every fixture under
# .github/actions/<step>/fixtures/<case>/ and compares the step's
# $GITHUB_OUTPUT (parsed into JSON) against the fixture's expected.json.
#
# Negative fixtures: a case dir whose name starts with "negative-" inverts
# the diff polarity — the case is OK when actual ≠ expected. Use this to
# prove the harness's diff actually fires (a positive fixture passing alone
# does not rule out a tautological harness).
set -u

WORKFLOW="${1:?workflow required (e.g. coding-agent.yml)}"
STEP="${2:?step id required (e.g. parse-issue)}"

FIX_ROOT="${FIXTURES_OVERRIDE:-.github/actions/$STEP/fixtures}"
[ -d "$FIX_ROOT" ] || { echo "No fixtures dir: $FIX_ROOT" >&2; exit 1; }

parse_github_output_to_json() {
  python3 - "$1" <<'PY'
import json, re, sys
with open(sys.argv[1]) as f:
    lines = f.read().splitlines()
out, i = {}, 0
while i < len(lines):
    m = re.match(r'^([^=<]+)<<(.+)$', lines[i])
    if m:
        key, delim = m.group(1), m.group(2)
        i += 1
        buf = []
        while i < len(lines) and lines[i] != delim:
            buf.append(lines[i]); i += 1
        out[key] = "\n".join(buf)
    elif '=' in lines[i]:
        k, v = lines[i].split('=', 1)
        out[k] = v
    i += 1
print(json.dumps(out, sort_keys=True, indent=2))
PY
}

FAIL=0
for case_dir in "$FIX_ROOT"/*/; do
  case=$(basename "$case_dir")
  negative=0
  [[ "$case" == negative-* ]] && negative=1
  ART=$(mktemp -d)
  if ! .github/scripts/test/act-step-dispatch.sh "$WORKFLOW" "$STEP" \
         --inputs "$(cat "$case_dir/input.json")" \
         --artifact-server-path "$ART" -q; then
    echo "FAIL: $STEP/$case (dispatch)"
    FAIL=1; continue
  fi
  ACTUAL=$(parse_github_output_to_json "$ART/github_output.txt")
  EXPECTED=$(jq -S . "$case_dir/expected.json")
  if diff <(echo "$EXPECTED") <(echo "$ACTUAL" | jq -S .) >/dev/null; then
    matched=1
  else
    matched=0
  fi
  if [ $negative -eq 1 ]; then
    if [ $matched -eq 0 ]; then
      echo "OK:   $STEP/$case (negative: diff fired as expected)"
    else
      echo "FAIL: $STEP/$case (negative: expected mismatch but harness matched — diff is tautological)"
      FAIL=1
    fi
  else
    if [ $matched -eq 1 ]; then
      echo "OK:   $STEP/$case"
    else
      diff <(echo "$EXPECTED") <(echo "$ACTUAL" | jq -S .)
      echo "FAIL: $STEP/$case"
      FAIL=1
    fi
  fi
done
exit $FAIL
