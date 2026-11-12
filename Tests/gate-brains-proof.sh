#!/bin/bash
# The hand-off with a running turn (audit gate-2): builds the agent's sources (but its main) with gate-brains-proof/main.swift
# and runs it in a throwaway home whose only `claude` is a shell script. No real brain, no aris-tools run, no card on
# screen. Also checks that the built aris-tools (ARIS_TOOLS=<path>, optional) never runs a handed-off write itself inside
# a Claude's process: without a turn it stops, and nothing is sent anywhere.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/.."
OUT="${OUT:-$(mktemp -d)}"
mkdir -p "$OUT"
AGENT=()
for f in "$SRC"/ArisAgent/*.swift; do [ "$(basename "$f")" = main.swift ] || AGENT+=("$f"); done
swiftc -Onone -target arm64-apple-macos14.0 -o "$OUT/gate-brains-proof" "${AGENT[@]}" \
  "$SRC/Aris/private/Claude/HTTPRequestParser.swift" "$SRC/Aris/private/Claude/ClaudeHookToken.swift" "$SRC/Shared/ArisXPCTrust.swift" \
  "$SRC/Aris/private/Aris/ArisBrain.swift" "$SRC/Aris/private/Aris/ArisAgentReply.swift" "$SRC/Aris/private/Aris/ArisActionGrant.swift" \
  "$SRC/Aris/private/Aris/ArisNumbers.swift" "$SRC/ArisTools/ArisWindowGrid.swift" "$SRC/ArisTools/ArisProtectedPlaces.swift" "$SRC/ArisTools/ArisUndoArguments.swift" "$SRC/Aris/private/Aris/ArisTodos.swift" \
  "$SRC/Aris/private/Aris/ArisUsage.swift" \
  "$SRC/Aris/private/Aris/Team/ArisTeammate.swift" "$SRC/Aris/private/Aris/Team/ArisTeammateScope.swift" "$SRC/Aris/private/Aris/Team/ArisClaudeLaunch.swift" "$SRC/Aris/private/Aris/Team/ArisJob.swift" \
  "$SRC/Aris/private/Aris/Team/ArisDispatch.swift" "$SRC/Aris/private/Aris/Team/ArisWindowLocator.swift" \
  "$SRC/Aris/private/Aris/See/ArisCaptureRules.swift" "$SRC/Aris/private/Aris/See/ArisImageBudget.swift" "$SRC/Aris/private/Aris/See/ArisImageCodec.swift" \
  "$SRC/Aris/private/Aris/ArisTurnImage.swift" "$SRC/Aris/private/Aris/ArisImageCheck.swift" "$SRC/ArisTools/ArisSealedTools.swift" "$SRC/ArisTools/ArisTurnGate.swift" "$SRC/ArisTools/ArisReadGate.swift" "$SRC/ArisTools/ArisWebFetch.swift" "$SRC/Aris/private/Aris/ArisLogRotation.swift" "$SRC/Aris/private/Aris/ArisDataSafety.swift" \
  "$SRC/Aris/private/Aris/Dictation/ArisWritingStyle.swift" "$SRC/Aris/private/Aris/Dictation/ArisLearnedDictionary.swift" "$SRC/Aris/private/Aris/Dictation/ArisPolishPrompt.swift" \
  "$SRC/Shared/ArisBuildInfo.swift" "$SRC/Shared/ArisBuildStamp.swift" "$DIR/gate-brains-proof/main.swift" 2>&1 | { grep -E "error:" -A5 || true; }
[ -x "$OUT/gate-brains-proof" ] || { echo "PROOF BUILD FAILED"; exit 1; }
# The throwaway home: its own Aris folder, and the one `claude` there is: a script that announces a command and waits.
H="$(mktemp -d)"
mkdir -p "$H/Library/Preferences" "$H/.local/bin" "$H/.config/aris/aris" "$H/Desktop"
cat > "$H/.local/bin/claude" <<FAKE
#!/bin/sh
echo '{"type":"system","subtype":"init","tools":["Bash","Read","WebSearch","WebFetch"],"mcp_servers":[]}'
read -r line
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"$H/.config/aris/aris-tools trash ~/Desktop/qa-proof.txt"}}]}}'
# It waits as a brain waits on its command, and takes its sleep with it when it is ended.
trap 'kill \$SLEEPER 2>/dev/null; exit 0' TERM INT
sleep 120 &
SLEEPER=\$!
wait
FAKE
chmod +x "$H/.local/bin/claude"
STATUS=0
CFFIXED_USER_HOME="$H" HOME="$H" ARIS_PROOF_HOME="$H" "$OUT/gate-brains-proof" || STATUS=$?
# The fake claude (and the sleep it waits in) goes with the proof: only the script under this throwaway home.
pkill -f "$H/.local/bin/claude" 2>/dev/null || true
# The built aris-tools inside a Claude's process (its turn-gate folder set) with no turn: it stops; nothing is removed
# (the id names no schedule) and nothing is sent.
if [ -n "${ARIS_TOOLS:-}" ]; then
  SAID="$(CFFIXED_USER_HOME="$H" HOME="$H" ARIS_TURN_STATE="$H/turn" "$ARIS_TOOLS" schedule remove 00000000-0000-0000-0000-000000000000 2>&1 || true)"
  case "$SAID" in *"works only inside an Aris turn"*) echo "ok   proof: the built aris-tools hands a write off (and stops without a turn): $SAID" ;;
    *) echo "FAIL proof: the built aris-tools ran a handed-off write itself: $SAID"; STATUS=1 ;; esac
  SAID="$(CFFIXED_USER_HOME="$H" HOME="$H" ARIS_SEALED=1 ARIS_SEALED_HANDOFF=1 "$ARIS_TOOLS" schedule remove 00000000-0000-0000-0000-000000000000 2>&1 || true)"
  case "$SAID" in *"works only inside an Aris turn"*) echo "ok   proof: so does the sealed Claude's: $SAID" ;;
    *) echo "FAIL proof: the sealed Claude's aris-tools didn't hand it off: $SAID"; STATUS=1 ;; esac
fi
rm -rf "$H"
exit $STATUS
