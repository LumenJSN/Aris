#!/bin/sh
# Aris: hands one Claude Code hook event (JSON on stdin) to the notch and prints the notch's answer (an approval's
# decision) for Claude Code. Put in ~/.claude/settings.json as a command hook by Settings › Claude Code 연결, so that
# file holds no secret: the token is read here from ~/.config/aris/claude-hook-token (0600, made by aris-agent) and
# handed to curl on a here-document, never as an argument (arguments show in the process list).
# Usage: aris-claude-hook.sh <seconds to wait for the notch>. Never fails Claude Code: no notch, no answer.
wait="${1:-2}"
token_file="$HOME/.config/aris/claude-hook-token"
[ -r "$token_file" ] || exit 0
token=$(cat "$token_file")
payload=$(cat)
[ -n "$payload" ] && [ -n "$token" ] || exit 0
# The coding agent's own process (this hook's parent, or the parent of the shell that ran it): Aris drops the session
# once that process is gone, even when it never said SessionEnd (killed while it waited for an answer). Not looked up
# for the tool calls (the most frequent events, and Aris keeps the session's last one): ps takes ~20 ms.
agent_pid=""
case "$payload" in
  *'"hook_event_name":"PreToolUse"'*|*'"hook_event_name":"PostToolUse"'*) ;;
  *) agent_pid=$PPID
     case "$(ps -o comm= -p "$agent_pid" 2>/dev/null)" in
       *sh) agent_pid=$(ps -o ppid= -p "$agent_pid" 2>/dev/null | tr -d ' ') ;;
     esac ;;
esac
printf '%s' "$payload" | curl -sf --connect-timeout 0.3 -m "$wait" -H @/dev/fd/3 -H "Content-Type: application/json" \
  -H "X-Term-Program: ${TERM_PROGRAM:-}" -H "X-Warp-Focus: ${WARP_FOCUS_URL:-}" -H "X-Iterm-Session: ${ITERM_SESSION_ID:-}" \
  -H "X-Tmux-Pane: ${TMUX_PANE:-}" -H "X-Bundle-Id: ${__CFBundleIdentifier:-}" -H "X-Claude-Pid: ${agent_pid:-}" \
  --data-binary @- http://127.0.0.1:23350/hook 3<<HEADERS
X-Aris-Token: $token
HEADERS
exit 0
