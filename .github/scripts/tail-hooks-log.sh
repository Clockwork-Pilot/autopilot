#!/usr/bin/env bash
# Tail Claude's hooks.log and emit one human-readable line per JSON event.
#
# Usage: tail-hooks-log.sh [LOG_PATH]
#   LOG_PATH defaults to /workspace/.claude/hooks.log
#
# Intended to run inside the agent container alongside `claude -p`, so its
# stdout is captured by docker and surfaced to the workflow logs.
set -uo pipefail

LOG="${1:-/workspace/.claude/hooks.log}"

tail -F -n 0 "$LOG" 2>/dev/null | jq -R -r --unbuffered '
  . as $raw
  | (try (fromjson) catch null)
  | if . == null then "[parse-err] \($raw)"
    else
      ((.timestamp // "") | sub("^.*T";"") | sub("\\..*$";"")) as $t
      | (.event // "?") as $e
      | (.data // {}) as $d
      | if   $e == "SessionStart"     then "[\($t)] start model=\($d.model // "?") source=\($d.source // "?")"
        elif $e == "UserPromptSubmit" then "[\($t)] prompt \($d.prompt // "")"
        elif $e == "Edit" then "[\($t)] edit \($d.tool_input.file_path // "?") -\(($d.tool_input.old_string // "") | utf8bytelength) +\(($d.tool_input.new_string // "") | utf8bytelength)"
        elif $e == "Write" then "[\($t)] write \($d.tool_input.file_path // "?") +\(($d.tool_input.content // "") | utf8bytelength)"
        elif $e == "Notification"     then "[\($t)] notify \($d.message // "")"
        elif $e == "Stop"             then "[\($t)] stop \($d.last_assistant_message // "")"
        elif $e == "SessionEnd"       then "[\($t)] end reason=\($d.reason // "?")"
        else "[\($t)] \($e)"
        end
    end
'
