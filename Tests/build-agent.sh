#!/bin/bash
# Compiles aris-agent and aris-tools into a folder (OUT, default a temp folder); nothing is installed.
# This is the one list of the source files they are built from: install-aris-agent.sh runs this script (with OUT set to
# its staging folder), so what the tests build is what gets installed.
# ARIS_COMMIT=<commit>: compiled into both programs (`aris-tools --version`, the agent's log) in place of "dev".
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/.."
OUT="${OUT:-$(mktemp -d)}"
# Built for the app's own lowest macOS, never just the build host's (QA's macOS 26 VM: an agent built on 27 died in dyld on
# a FoundationModels symbol). FoundationModels exists only from 26, so it is weak-linked; its use is behind #available.
MIN_OS="$(grep -m1 -o 'MACOSX_DEPLOYMENT_TARGET = [0-9.]*' "$SRC/Aris.xcodeproj/project.pbxproj" | awk '{print $3}')"
TARGET=(-target "arm64-apple-macos$MIN_OS" -Xlinker -weak_framework -Xlinker FoundationModels)
# The build stamp: the repository's file says "dev"; with ARIS_COMMIT a generated copy carrying that commit is compiled
# instead (letters, digits, dots and dashes only: it becomes a Swift string).
mkdir -p "$OUT"
STAMP="$SRC/Shared/ArisBuildStamp.swift"
if [ -n "${ARIS_COMMIT:-}" ]; then
  case "$ARIS_COMMIT" in *[!0-9a-zA-Z._-]*) echo "ARIS_COMMIT may hold only letters, digits, dots and dashes: $ARIS_COMMIT"; exit 1 ;; esac
  STAMP="$OUT/ArisBuildStamp.swift"
  printf 'enum ArisBuildStamp {\n    static let marked = "aris-build-commit:%s"\n}\n' "$ARIS_COMMIT" > "$STAMP"
fi
BUILD_INFO=("$SRC/Shared/ArisBuildInfo.swift" "$STAMP")
swiftc -O "${TARGET[@]}" -o "$OUT/aris-agent" "$SRC"/ArisAgent/*.swift \
  "$SRC/Aris/private/Claude/HTTPRequestParser.swift" "$SRC/Aris/private/Claude/ClaudeHookToken.swift" "$SRC/Shared/ArisXPCTrust.swift" \
  "$SRC/Aris/private/Aris/ArisBrain.swift" "$SRC/Aris/private/Aris/ArisAgentReply.swift" "$SRC/Aris/private/Aris/ArisFix.swift" "$SRC/Aris/private/Aris/ArisActionGrant.swift" \
  "$SRC/Aris/private/Aris/ArisNumbers.swift" "$SRC/ArisTools/ArisWindowGrid.swift" "$SRC/ArisTools/ArisProtectedPlaces.swift" "$SRC/ArisTools/ArisUndoArguments.swift" "$SRC/Aris/private/Aris/ArisTodos.swift" \
  "$SRC/Aris/private/Aris/ArisUsage.swift" \
  "$SRC/Aris/private/Aris/Team/ArisTeammate.swift" "$SRC/Aris/private/Aris/Team/ArisTeammateScope.swift" "$SRC/Aris/private/Aris/Team/ArisClaudeLaunch.swift" "$SRC/Aris/private/Aris/Team/ArisTerminal.swift" "$SRC/Aris/private/Aris/Team/ArisQuietLaunch.swift" "$SRC/Aris/private/Aris/Team/ArisJob.swift" \
  "$SRC/Aris/private/Aris/Team/ArisDispatch.swift" "$SRC/Aris/private/Aris/Team/ArisWindowLocator.swift" \
  "$SRC/Aris/private/Aris/See/ArisCaptureRules.swift" "$SRC/Aris/private/Aris/See/ArisImageBudget.swift" "$SRC/Aris/private/Aris/See/ArisImageCodec.swift" \
  "$SRC/Aris/private/Aris/ArisTurnImage.swift" "$SRC/Aris/private/Aris/ArisImageCheck.swift" "$SRC/ArisTools/ArisSealedTools.swift" "$SRC/ArisTools/ArisTurnGate.swift" "$SRC/ArisTools/ArisReadGate.swift" "$SRC/ArisTools/ArisWebFetch.swift" "$SRC/Aris/private/Aris/ArisLogRotation.swift" "$SRC/Aris/private/Aris/ArisDataSafety.swift" \
  "$SRC/Aris/private/Aris/Dictation/ArisWritingStyle.swift" "$SRC/Aris/private/Aris/Dictation/ArisLearnedDictionary.swift" "$SRC/Aris/private/Aris/Dictation/ArisPolishPrompt.swift" \
  "$SRC/Aris/private/Aris/ArisRoutineProgress.swift" "$SRC/Aris/private/Aris/ArisActivityWords.swift" "$SRC/Aris/private/Aris/ArisPointsBack.swift" \
  "$SRC/ArisTools/ArisLocalStore.swift" "$SRC/ArisTools/ArisMailRead.swift" "$SRC/ArisTools/ArisMailMIME.swift" "$SRC/ArisTools/ArisMailText.swift" "$SRC/ArisTools/ArisMailFind.swift" "$SRC/ArisTools/ArisMailStore.swift" "$SRC/ArisTools/ArisMailReply.swift" \
  "${BUILD_INFO[@]}"
swiftc -O "${TARGET[@]}" -o "$OUT/aris-tools" "$SRC"/ArisTools/*.swift "$SRC/Aris/private/Aris/Team/ArisTeammateScope.swift" "$SRC/ArisAgent/ArisLocalReadPolicy.swift" "$SRC/ArisAgent/ArisCommandPolicy.swift" "$SRC/ArisAgent/ArisSchedule.swift" "$SRC/ArisAgent/ArisScheduleStore.swift" "$SRC/Aris/private/Aris/ArisTodos.swift" "$SRC/ArisAgent/ArisMemoryText.swift" "$SRC/ArisAgent/ArisMemoryWhen.swift" "$SRC/ArisAgent/ArisMemoryRecall.swift" "$SRC/ArisAgent/ArisMemoryStore.swift" "$SRC/ArisAgent/ArisMemoryStore+Review.swift" "$SRC/ArisAgent/ArisMemoryGate.swift" "$SRC/ArisAgent/ArisMemoryEntities.swift" "$SRC"/ArisAgent/ArisWorkMemory*.swift "$SRC/ArisAgent/ArisNoFollow.swift" "$SRC"/ArisAgent/ArisOrigin*.swift "$SRC/Shared/ArisXPCTrust.swift" "$SRC/Aris/private/Aris/ArisNumbers.swift" "$SRC/Aris/private/Aris/ArisFix.swift" "$SRC/Aris/private/Claude/ClaudeHookToken.swift" "$SRC/ArisAgent/ArisFrontNow.swift" "$SRC/ArisAgent/ArisFrontLive.swift" "$SRC/ArisAgent/ArisHelperListing.swift" \
  "$SRC/Aris/private/Aris/See/ArisCaptureRules.swift" "$SRC/Aris/private/Aris/See/ArisImageBudget.swift" "$SRC/Aris/private/Aris/ArisLogRotation.swift" \
  "$SRC/Aris/private/Aris/Currency/ArisCurrencyNames.swift" "$SRC/Aris/private/Aris/Currency/ArisCurrencyMath.swift" \
  "${BUILD_INFO[@]}"
# Each binary must say it runs on MIN_OS (vtool's minos), and every framework newer than that must be weak.
bash "$DIR/min-os-check.sh" "$MIN_OS" "$OUT/aris-agent" "$OUT/aris-tools" || { echo "MIN OS CHECK FAILED"; exit 1; }
echo "AGENT BUILD OK ($OUT)"
