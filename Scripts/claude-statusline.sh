#!/bin/bash
# Aris status line: forwards Claude Code's status JSON (plan limits, context use)
# to the notch, then prints a short line for the terminal.
# Installed to ~/.config/aris/statusline.sh by install-claude-hooks.py.
input=$(cat)
token_file="$HOME/.config/aris/claude-hook-token"
if [ -r "$token_file" ]; then
  # Backgrounded with its output detached, so a closed notch never slows the status line down.
  # The token goes to curl as a header file on a pipe, never as an argument (arguments show in the process list).
  printf '%s' "$input" | curl -s -m 1 -o /dev/null -X POST "http://127.0.0.1:23350/status" \
    -H "Content-Type: application/json" -H @<(printf 'X-Aris-Token: %s\n' "$(cat "$token_file")") \
    --data-binary @- >/dev/null 2>&1 &
fi
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$input" | jq -r '[
    .model.display_name,
    (.context_window.used_percentage // empty | "ctx \(round)%"),
    (.rate_limits.five_hour.used_percentage // empty | "5h \(ceil)%"),
    (.rate_limits.seven_day.used_percentage // empty | "7d \(ceil)%")
  ] | map(select(. != null)) | join(" · ")' 2>/dev/null
else
  # macOS 14 has no jq (Apple ships it from 15): the same line from the system's own JavaScript, which every macOS has.
  # The status JSON is read from stdin, not passed as an argument.
  printf '%s' "$input" | /usr/bin/osascript -l JavaScript -e 'ObjC.import("Foundation"); function run() {
    var data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
    var text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;
    var status; try { status = JSON.parse(text); } catch (error) { return ""; }
    function part(value, label, round) {
      return (value === null || value === undefined || value === false) ? null : label + " " + round(value) + "%";
    }
    var limits = status.rate_limits || {};
    return [
      (status.model || {}).display_name,
      part((status.context_window || {}).used_percentage, "ctx", Math.round),
      part((limits.five_hour || {}).used_percentage, "5h", Math.ceil),
      part((limits.seven_day || {}).used_percentage, "7d", Math.ceil)
    ].filter(function (piece) { return piece !== null && piece !== undefined; }).join(" · ");
  }' 2>/dev/null
fi
