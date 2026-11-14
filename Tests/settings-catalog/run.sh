#!/bin/bash
# The settings window's pure tests alone: the index and search, the words, the pages' rows, the preview's plan.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
S="$DIR/../../Aris/components/Settings"
OUT="$(mktemp -d)/settings-catalog-tests"
swiftc -o "$OUT" "$DIR/main.swift" "$DIR/../settings-catalog-tests.swift" "$S/ArisSettingsCatalog.swift" "$S/ArisSettingsWords.swift" \
  "$S/ArisSettingsModel.swift" "$S/ArisSettingsSnapshot.swift" "$S/ArisSettingsBuilder.swift" "$S/ArisMoreSettings.swift" "$S/ArisFaceStage.swift" \
  "$S/../../private/Aris/Dictation/ArisWritingStyle.swift" "$S/../../private/Aris/ArisMemorySettings.swift" \
  "$S/../../private/Aris/ArisPrerequisites.swift" "$S/../../private/Aris/ArisUIWords.swift" "$S/../../private/Aris/ArisUILanguage.swift" \
  "$S/../../private/Aris/ArisBrain.swift" "$S/../../private/Aris/Side/ArisSideTab.swift" "$S/../../private/Aris/Team/ArisTeamCopy.swift" \
  "$S/../../private/Aris/Team/ArisTeammateScope.swift" "$S/../../private/Claude/ClaudeHookToken.swift" "$S/ArisSettingsCopy.swift"
"$OUT"
