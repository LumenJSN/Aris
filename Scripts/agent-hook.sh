#!/bin/sh
# Aris: hands one Codex or Gemini CLI hook event (JSON on stdin) to the notch, like Claude's http hooks.
# Usage (from the agent's hook config): agent-hook.sh codex|gemini
# Never blocks the agent and prints nothing (an empty answer means "carry on"). The token is read by curl from a
# 0600 header file, so it never shows up in the process list.
agent="$1"
dir="$HOME/.config/aris"
payload=$(cat)
[ -n "$payload" ] && [ -r "$dir/agent-hook-headers" ] || exit 0
printf '%s' "$payload" | curl -s -o /dev/null --connect-timeout 0.3 -m 1 \
  -H @"$dir/agent-hook-headers" -H "Content-Type: application/json" -H "X-Agent: $agent" \
  -H "X-Term-Program: ${TERM_PROGRAM:-}" -H "X-Warp-Focus: ${WARP_FOCUS_URL:-}" \
  -H "X-Iterm-Session: ${ITERM_SESSION_ID:-}" -H "X-Tmux-Pane: ${TMUX_PANE:-}" -H "X-Bundle-Id: ${__CFBundleIdentifier:-}" \
  --data-binary @- http://127.0.0.1:23350/hook >/dev/null 2>&1
exit 0
