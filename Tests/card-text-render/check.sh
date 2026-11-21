#!/bin/bash
# Draws confirm cards offscreen through the real ArisConfirmCard (and ArisEditableRows) and checks that every line of
# text a card was built with is drawn (seventh VM run, item 1: the values card's "It goes on a new line (↵)" was in the
# card's text but never drawn). The text is read back from the drawn view's accessibility tree, never from the screen:
# the window is never ordered on screen. Exit status 0 when every card draws all of its text.
# usage: check.sh [BUILD_DIR]
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
A="$DIR/../../Aris/private/Aris"
C="$DIR/../../Shared/Core"
BUILD="${1:-$(mktemp -d)}"
mkdir -p "$BUILD"
swiftc -Onone -parse-as-library -o "$BUILD/card-text" "$DIR/main.swift" \
  "$A/Home/ArisConfirmCard.swift" "$A/Home/ArisConfirmCard+Countdown.swift" "$A/ArisCountdown.swift" "$A/ArisSession.swift" \
  "$A/Home/ArisEditableRows.swift" "$A/Home/ArisFadingScroll.swift" "$A/Home/ArisAnswerLayout.swift" "$A/Home/ArisConfirmWords.swift" \
  "$A/Home/ArisCardEnglish.swift" "$A/Home/ArisCardEnglish+Desktop.swift" "$A/Home/ArisCardStill.swift" "$A/Home/ArisCardReadLive.swift" "$A/Home/ArisStoppedCard.swift" \
  "$A/ArisCardHold.swift" "$A/ArisCardRead.swift" "$A/ArisStoppedCopy.swift" "$A/ArisCardHearing.swift" "$A/ArisCardKeys.swift" "$A/Home/ArisCardHearingNote.swift" \
  "$A/ArisAgentReply.swift" "$A/ArisCardRevise.swift" "$A/ArisConfirmReply.swift" \
  "$A/ArisUILanguage.swift" "$A/ArisUIWords.swift" \
  "$A/ArisCardWait.swift" "$A/ArisBrain.swift" "$A/ArisUIDates.swift" "$DIR/../../Shared/Core/ArisCountdownStep.swift" "$DIR/../../Shared/Core/ArisEvent.swift" "$A/ArisRoutineProgress.swift" "$C"/Apps/*.swift "$C"/Permissions/*.swift "$C"/Mind/*.swift "$DIR/../../Shared/Core/Tasks"/*.swift "$C/ArisTurnID.swift" "$C"/World/*.swift "$C/Fleet/ArisFleetGrant.swift" "$C"/Teach/*.swift "$C"/Trust/*.swift
"$BUILD/card-text"
