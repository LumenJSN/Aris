#!/bin/bash
# Live smoke test against the installed app's hook server (127.0.0.1:23350). No clicks needed.
set -u
URL=http://127.0.0.1:23350/hook
TOKEN="$(cat "$HOME/.config/aris/claude-hook-token")" || { echo "no token; run install-claude-hooks.py --apply"; exit 1; }
AUTH="X-Aris-Token: $TOKEN"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got '$2', want '$3')"; fail=1; fi; }
post() { curl -s -m 5 -X POST "$URL" -H "Content-Type: application/json" -H "$AUTH" -d "$1"; }
code() { curl -s -m 5 -o /dev/null -w '%{http_code}' -H "$AUTH" "$@"; }
anon() { curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST "$URL" -H 'Content-Type: application/json' "$@"; }

check "event accepted"   "$(post '{"hook_event_name":"UserPromptSubmit","session_id":"smoke","cwd":"/tmp/smoke"}')" "{}"
check "tool event"       "$(post '{"hook_event_name":"PreToolUse","session_id":"smoke","tool_name":"Edit","tool_input":{"file_path":"/tmp/a","old_string":"a","new_string":"b"}}')" "{}"
check "stop + message"   "$(post '{"hook_event_name":"Stop","session_id":"smoke","last_assistant_message":"All done"}')" "{}"
check "GET rejected"     "$(code "$URL")" "400"
check "wrong path"       "$(code -X POST http://127.0.0.1:23350/nope -d '{}')" "400"
check "browser Origin"   "$(code -X POST "$URL" -H 'Content-Type: application/json' -H 'Origin: https://evil.example' -d '{"hook_event_name":"Stop","session_id":"x"}')" "400"
check "form post (CSRF)" "$(code -X POST "$URL" -d '{"hook_event_name":"Stop","session_id":"x"}')" "400"
check "no token"         "$(anon -d '{"hook_event_name":"Stop","session_id":"x"}')" "401"
check "wrong token"      "$(anon -H 'X-Aris-Token: nope' -d '{"hook_event_name":"Stop","session_id":"x"}')" "401"
check "bad JSON"         "$(code -X POST "$URL" -H 'Content-Type: application/json' -d 'not json')" "400"
STATUS=http://127.0.0.1:23350/status
check "status accepted"  "$(curl -s -m 5 -X POST "$STATUS" -H "Content-Type: application/json" -H "$AUTH" -d '{"session_id":"smoke","context_window":{"used_percentage":12}}')" "{}"
check "status no token"  "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST "$STATUS" -H 'Content-Type: application/json' -d '{}')" "401"
check "status Origin"    "$(code -X POST "$STATUS" -H 'Content-Type: application/json' -H 'Origin: https://evil.example' -d '{}')" "400"
check "statusline line"  "$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":41.6}}' | "$HOME/.config/aris/statusline.sh")" "Opus · ctx 42%"
post '{"hook_event_name":"SessionEnd","session_id":"smoke"}' >/dev/null
exit $fail
