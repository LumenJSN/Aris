#!/bin/bash
# Launch smoke check: starts the built Release app inside sandbox-exec (launch-smoke.sb: no ~/.config, no network,
# no audio HAL or microphone, no preference writes) and checks it is still alive after 10 s, then stops it.
# Run after the Release build. Exit 0 = it stayed up. The first-run guide counts as seen (argument domain), so the
# check doesn't put a 10 s window in front of the user at every install.
#   launch-smoke.sh [app binary] [build folder]
# app binary: …/Aris.app/Contents/MacOS/Aris (default: this worktree's build-release).
# build folder: what the sandbox lets the app read (default: the derived-data folder the app was built into, or the
# folder holding Aris.app when it is somewhere else). Nothing is tied to one worktree or one Mac.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$DIR/../build-release/Build/Products/Release/Aris.app/Contents/MacOS/Aris}"
[ -x "$APP" ] || { echo "LAUNCH SMOKE: no built app at $APP"; exit 1; }
# The sandbox matches real paths (/tmp is /private/tmp), so every folder handed to it is resolved first.
APP="$(cd "$(dirname "$APP")" && pwd -P)/$(basename "$APP")"
PRODUCTS="$(cd "$(dirname "$APP")/../../.." && pwd -P)"
case "$PRODUCTS" in
  */Build/Products/*) DEFAULT_BUILD="$(cd "$PRODUCTS/../../.." && pwd -P)" ;;
  *) DEFAULT_BUILD="$PRODUCTS" ;;
esac
BUILD="$(cd "${2:-$DEFAULT_BUILD}" 2>/dev/null && pwd -P)" || { echo "LAUNCH SMOKE: no build folder at ${2:-$DEFAULT_BUILD}"; exit 1; }
# A folder of this run's own, so two checks at once never delete each other's.
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aris-launch-smoke.XXXXXX")" && pwd -P)" || { echo "LAUNCH SMOKE: no temp folder"; exit 1; }
mkdir -p "$WORK/home"
# The app runs from its own deployment target, never only from the build host's macOS (QA's macOS 26 VM).
MIN_OS="$(grep -m1 -o 'MACOSX_DEPLOYMENT_TARGET = [0-9.]*' "$DIR/../Aris.xcodeproj/project.pbxproj" | awk '{print $3}')"
bash "$DIR/min-os-check.sh" "$MIN_OS" "$APP" || { echo "LAUNCH SMOKE: MIN OS CHECK FAILED"; exit 1; }
# The app icon is in the built product: the asset catalog's AppIcon (and the .icns for macOS before 26).
RES="$(dirname "$(dirname "$APP")")/Resources"
# (Read whole first: with pipefail, grep -q closing the pipe early made assetutil's SIGPIPE fail the check at random.)
CATALOG="$( [ -f "$RES/Assets.car" ] && assetutil --info "$RES/Assets.car" 2>/dev/null || true )"
grep -q '"AppIcon"' <<<"$CATALOG" || { echo "LAUNCH SMOKE: NO APP ICON in $RES/Assets.car"; exit 1; }
[ -f "$RES/AppIcon.icns" ] || { echo "LAUNCH SMOKE: NO AppIcon.icns for macOS 14/15"; exit 1; }
CFFIXED_USER_HOME="$WORK/home" sandbox-exec -D BUILD="$BUILD" -D WORK="$WORK" -D HOME="$(cd "$HOME" && pwd -P)" -f "$DIR/launch-smoke.sb" \
  "$APP" -arisOnboardingSeen YES > "$WORK/out.log" 2>&1 &
PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 1
  kill -0 "$PID" 2>/dev/null || break
done
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID" 2>/dev/null; sleep 1; kill -9 "$PID" 2>/dev/null
  wait "$PID" 2>/dev/null
  # The app's Now Playing adapter (perl) outlives a killed app: stop this build's own, nothing else.
  ADAPTER="$(dirname "$(dirname "$APP")")/Resources/mediaremote-adapter.pl"
  # It can outlive the first try (it was still starting): try again until none is left, a few times at most.
  for _ in 1 2 3 4 5; do pkill -f "$ADAPTER" 2>/dev/null; sleep 1; pgrep -f "$ADAPTER" >/dev/null || break; done
  pgrep -f "$ADAPTER" >/dev/null && { echo "LAUNCH SMOKE: this build's Now Playing adapter is still running"; exit 1; }
  echo "LAUNCH SMOKE OK (alive after 10 s)"
  rm -rf "$WORK"; exit 0
fi
wait "$PID"; STATUS=$?
echo "LAUNCH SMOKE FAILED (exited with $STATUS within 10 s)"
grep -E "Fatal error|fatal|Terminating|exception|dispatch_once|EXC_|sandbox" "$WORK/out.log" | head -5
echo "LAUNCH SMOKE: the app's output is kept in $WORK/out.log"
exit 1
