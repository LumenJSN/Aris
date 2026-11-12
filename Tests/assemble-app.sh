#!/bin/bash
# Makes a built Aris.app whole and signs it: aris-agent and aris-tools go into Contents/MacOS (a program launchd
# starts from there is charged to the app, so macOS shows one row, "Aris", for every permission), the skills' files
# go into Contents/Resources/skills, and everything is signed inside-out. Nothing is installed.
#
#   assemble-app.sh <Aris.app> <folder holding aris-agent and aris-tools> [sign id]
#
# <Aris.app> is changed in place: hand it a copy of the build product. sign id: "Apple Development" (default), a
# 40-character hash, or "-" for ad-hoc.
# Order: aris-agent and aris-tools (their own identifiers, which macOS knows them by; the hardened runtime and their
# entitlements), every other program and framework inside the app (hardened runtime), the XPC services (hardened
# runtime, their entitlements), then the app with Aris.entitlements. The hardened runtime is what keeps another
# program from loading its own code into these (DYLD_INSERT_LIBRARIES) and using what the user granted Aris.
# The app itself (sandboxed) gets the hardened runtime too when it is signed with a certificate: the default since
# 2026-11-11, when a brand-new install of such a build was walked in a VM (macOS 26.6.2, SIP on: microphone, speech,
# Accessibility, Screen Recording, the capture question, the helper installed by the app, turns, the talk key, a
# dropped file, Settings; no crash, and an injected library was not loaded). HARDEN_APP=0 signs the app as before.
# An ad-hoc signature ("-") never hardens the app: library validation then refuses the app's own
# MediaRemoteAdapter.framework ("different Team IDs") and the app dies in dyld at launch (seen in the same VM), so
# HARDEN_APP=1 together with "-" is refused here.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${SRC:-$DIR/..}"
APP="${1:?usage: assemble-app.sh <Aris.app> <folder with aris-agent and aris-tools> [sign id]}"
FROM="${2:?the folder holding aris-agent and aris-tools}"
SIGN_ID="${3:-Apple Development}"
fail() { echo "assemble-app FAILED: $*" >&2; exit 1; }

[ -x "$APP/Contents/MacOS/Aris" ] || fail "$APP is not a built Aris.app"
for name in aris-agent aris-tools; do [ -f "$FROM/$name" ] || fail "no $name in $FROM (Tests/build-agent.sh makes them)"; done
[ -f "$SRC/ArisAgent/ArisAgent.entitlements" ] || fail "no $SRC/ArisAgent/ArisAgent.entitlements"
# Whether the app itself is hardened (decided before anything is signed).
HARDEN="${HARDEN_APP:-}"
case "$HARDEN" in ""|0|1) ;; *) fail "HARDEN_APP is \"$HARDEN\": use 1 (hardened runtime on the app) or 0 (as before)" ;; esac
if [ "$SIGN_ID" = "-" ]; then
  [ "$HARDEN" = "1" ] && fail "HARDEN_APP=1 cannot be used with an ad-hoc signature: a hardened app loads only libraries of its own team, an ad-hoc signature has no team, and Aris then dies in dyld at launch (MediaRemoteAdapter.framework, \"different Team IDs\"). Sign with a certificate, or leave HARDEN_APP unset."
  HARDEN=0
elif [ -z "$HARDEN" ]; then
  HARDEN=1
fi

# codesign's own complaint is shown; its note that it replaced a signature is not.
sign() {
  local said
  said="$(codesign --force --sign "$SIGN_ID" "$@" 2>&1)" || { [ -n "$said" ] && printf '%s\n' "$said" >&2; fail "codesign could not sign ${*: -1} with \"$SIGN_ID\" (is the keychain unlocked?)"; }
}

# 1. The two programs, into the app.
for name in aris-agent aris-tools; do
  install -m 755 "$FROM/$name" "$APP/Contents/MacOS/$name" || fail "could not copy $name into the app"
  sign --options runtime --identifier "com.lumenjsn.aris.$name" --entitlements "$SRC/ArisAgent/ArisAgent.entitlements" "$APP/Contents/MacOS/$name"
done
# 2. The skills' files the helper reads from the app (the built-in skill, the pinned requirements).
rm -rf "$APP/Contents/Resources/skills"
mkdir -p "$APP/Contents/Resources/skills/builtin"
install -m 644 "$SRC/ArisSkills/runtime-requirements.txt" "$APP/Contents/Resources/skills/runtime-requirements.txt" || fail "could not read $SRC/ArisSkills/runtime-requirements.txt"
cp -R "$SRC/ArisSkills/skill-creator" "$APP/Contents/Resources/skills/builtin/skill-creator" || fail "could not read $SRC/ArisSkills/skill-creator"
# 3. Every other program inside the app (anything that could be started from there), then frameworks, deepest first.
while IFS= read -r -d '' piece; do
  case "$piece" in "$APP/Contents/MacOS/"*|*.xpc/*) continue ;; esac
  file -b "$piece" | grep -q "Mach-O.*executable" && sign --options runtime "$piece"
done < <(find "$APP/Contents" -type f -perm +111 -print0)
if [ -d "$APP/Contents/Frameworks" ]; then
  while IFS= read -r -d '' piece; do sign --options runtime "$piece"; done \
    < <(find "$APP/Contents/Frameworks" \( -name "*.framework" -o -name "*.xpc" -o -name "*.app" -o -name "*.dylib" \) -print0 | sort -rz)
fi
# 4. The XPC services.
for piece in "$APP"/Contents/XPCServices/*.xpc; do
  [ -e "$piece" ] || continue
  entitlements="$SRC/$(basename "$piece" .xpc)/$(basename "$piece" .xpc).entitlements"
  if [ -f "$entitlements" ]; then sign --options runtime --entitlements "$entitlements" "$piece"; else sign --options runtime "$piece"; fi
done
# 5. The app.
if [ "$HARDEN" = "1" ]; then
  sign --options runtime --entitlements "$SRC/Aris/Aris.entitlements" "$APP"
else
  sign --entitlements "$SRC/Aris/Aris.entitlements" "$APP"
fi
codesign --verify --deep --strict "$APP" || fail "the signed app does not verify"
if [ "$HARDEN" = "1" ]; then
  described="$(codesign -dv "$APP" 2>&1 || true)"
  grep -q "flags=.*runtime" <<<"$described" || fail "the app is not signed with the hardened runtime"
fi
for name in aris-agent aris-tools; do
  # Read whole first: with pipefail, a grep that stops at its first match would fail the pipe.
  described="$(codesign -dv "$APP/Contents/MacOS/$name" 2>&1 || true)"
  grep -q "^Identifier=com.lumenjsn.aris.$name$" <<<"$described" || fail "$name lost its signing identifier"
  grep -q "flags=.*runtime" <<<"$described" || fail "$name is not signed with the hardened runtime"
done
echo "ASSEMBLED $APP (signed $([ "$SIGN_ID" = "-" ] && echo "ad-hoc" || echo "with \"$SIGN_ID\""), app $([ "$HARDEN" = "1" ] && echo "hardened" || echo "not hardened"))"
