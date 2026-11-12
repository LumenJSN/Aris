#!/bin/bash
# Builds and runs the skills sandbox probe (outside the test harness's own sandbox: sandbox-exec can't nest).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
A="$DIR/../../ArisAgent"
OUT="$(mktemp -d)"
# What ArisSkillProcess starts its child through (ArisChildren, security review 4) and what that is built from: each
# file only when the commit under test has it.
STARTS=()
for file in "$A"/ArisOrigin*.swift "$A/ArisChildren.swift" "$A/ArisAppBundle.swift" "$A/ArisProgramApproval.swift" "$A/../Shared/ArisXPCTrust.swift" \
            "$A/../Aris/private/Claude/ClaudeHookToken.swift" "$A/../Aris/private/Aris/ArisBrain.swift"; do
  [ -f "$file" ] && STARTS+=("$file")
done
swiftc -O -o "$OUT/probe" "$DIR/main.swift" "$A/ArisSkillSandbox.swift" "$A/ArisSkillProcess.swift" "$A/ArisProcessEnd.swift" "$A/ArisSkillFormat.swift" "$A/ArisExactProcess.swift" "${STARTS[@]}"
"$OUT/probe"
