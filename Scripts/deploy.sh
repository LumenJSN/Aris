#!/bin/bash
# One command to put a new Aris on this Mac: build everything, check it, and only then swap it in.
#
#   ./deploy.sh              build, check, sign, wait for the agent to be idle, swap, relaunch
#   ./deploy.sh --now        the same, without waiting for the agent to finish what it is doing
#   ./deploy.sh --rollback   put back the app that the last deploy replaced, and relaunch
#   ./deploy.sh --bundle <Aris.app>   install a bundle that is already built, assembled and signed (nothing is built
#                            here: no Xcode, no source, no signing identity needed), then exactly the same swap
#   ./deploy.sh --clean      remove every signed copy of Aris, its helper and its tools that this script keeps beside
#                            itself (the staging folder, the build product, the build kept for a rollback): after it
#                            there is nothing to roll back to. The installed Aris is not touched.
#
# Aris is ONE bundle: aris-agent and aris-tools are inside Aris.app (Contents/MacOS), so macOS shows one row, "Aris",
# for every permission and keeps it across deploys signed with the same certificate. A deploy is one swap of the app
# and one restart of the helper; a rollback puts one bundle back.
#
# --bundle <Aris.app> (or --bundle=<Aris.app>; --now may be added): for a Mac that has no Xcode (a test VM), and for
# rehearsing the swap. The bundle is what Tests/assemble-app.sh leaves (stage-onerow.sh packs one). Steps 1 to 5 become:
# say what the bundle is, check that it is one build (app and helper carry the same stamp), that it is signed by the
# team of the Aris installed now (another team, or ad-hoc over a certificate, makes macOS forget every permission:
# refused unless ALLOW_OTHER_SIGNER=1), that both programs carry their identifiers and the hardened runtime, and that
# its signature verifies; then it is copied into the staging folder. The launch check is left out (it runs the
# unsigned build product, which a bundle no longer is). Step 6 is the same code: keep the installed app, wait for the
# agent, quit, swap, one restart, health check, and the previous build back by itself on a failure.
#
# Order (the running Aris is not touched before step 6):
#   1 what is being built (commit, signing identity)       4 launch check of the new app (Tests/launch-smoke.sh)
#   2 build the app (Release)                               5 put both programs into the app, sign it all, verify it
#   3 build and check aris-agent and aris-tools             6 keep the installed app, quit Aris, swap, restart the helper once, verify
# A failure in steps 1 to 5 leaves the installed Aris exactly as it was, still running. A failure in step 6 puts the
# previous build back by itself and says so. Every failure names the step and the reason, and exits non-zero.
# The first deploy over an install made the old way (the helper's own copy in ~/.config/aris): the app switches the
# helper over itself when it opens (it removes those copies); they are kept in the rollback folder first, so
# --rollback can still go back to that build.
#
# Signs with "Apple Development" by default, so macOS keeps Aris's permissions across rebuilds; switching
# the signer once makes macOS ask (on screen) whether the app may keep its data. SIGN_ID=- ./deploy.sh signs ad-hoc
# (permissions then have to be given again); with no identity in the keychain the script says so, loudly, and never
# drops a certificate-signed install to ad-hoc by itself (install-aris-agent.sh --resolve-identity is the one rule).
# The app itself is signed with the hardened runtime when a certificate signs it (Tests/assemble-app.sh);
# HARDEN_APP=0 ./deploy.sh signs it as before.
# SKIP_SMOKE=1 leaves out the launch check. IDLE_WAIT=<seconds> is how long step 6 waits for the agent (default 120).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT"
TESTS="${TESTS:-$ROOT/Tests}"
# APP, ARIS_DIR, STAGE and PREV exist so the script can be tried against throwaway folders.
APP="${APP:-/Applications/Aris.app}"
ARIS_DIR="${ARIS_DIR:-$HOME/.config/aris}"
# Where the new build is put together and checked before anything installed changes.
STAGE="${STAGE:-$ROOT/deploy-stage}"
# The build the last deploy replaced (one bundle), for --rollback.
PREV="${PREV:-$ROOT/deploy-previous}"
BUILD="$ROOT/build-release"
PRODUCT="$BUILD/Build/Products/Release/Aris.app"
ENT="$SRC/Aris/Aris.entitlements"
INSTALLER="$ROOT/Scripts/install-aris-agent.sh"
HOOK_PORT=23350
AGENT_PORT=23351
AGENT_LABEL="com.lumenjsn.aris.agent"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
export TESTS ARIS_DIR PREV STAGE APP

STEP="starting"
# 1 from the moment the installed build is being replaced: a failure then puts the previous build back.
SWAPPING=0
ROLLBACK=0
FAIL_REASON=""

step() { STEP="$1"; echo; echo "== $1"; }

# Stops with a reason. The report (and putting the previous build back) is done once, in on_exit.
die() { FAIL_REASON="$*"; exit 1; }

# Runs whenever the script ends. Any failure, expected or not, names the step and the reason, and a failure during the
# swap puts the previous build back, so the script never stops half-way without a word.
on_exit() {
  local status=$? last="$BASH_COMMAND"
  trap - EXIT
  [ "$status" -ne 0 ] || exit 0
  set +e
  { echo; echo "DEPLOY FAILED at step: $STEP"; echo "  ${FAIL_REASON:-an unexpected error in: $last}"; } >&2
  if [ "$SWAPPING" = "1" ]; then
    SWAPPING=0
    echo "  The swap had begun, so the previous build is being put back…" >&2
    if (put_back); then
      echo "  The previous build is back and running. Nothing else needs undoing." >&2
    else
      { echo "  COULD NOT put the previous build back. By hand:"
        echo "    $0 --rollback"
        echo "  (the previous app is kept in $PREV/Aris.previous)"; } >&2
    fi
  elif [ "$ROLLBACK" = "1" ]; then
    echo "  The rollback did not finish: check that Aris is running; $0 --rollback can be run again." >&2
  else
    echo "  Nothing installed was changed: the Aris that was installed and running before is untouched." >&2
  fi
  exit 1
}

listening() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

app_stamp() { /usr/libexec/PlistBuddy -c "Print :ArisCommit" "$1/Contents/Info.plist" 2>/dev/null || true; }

# The app's own processes: those whose program is $APP/Contents/MacOS/Aris. Never aris-agent or aris-tools, which run
# from the same folder: macOS could list the helper under the app's own bundle id, and a quit sent to that id reached
# the helper (-600) while the app ran on until the forced kill (VM fourth re-check, #4).
app_pids() { pgrep -f "^$APP/Contents/MacOS/Aris( |\$)" 2>/dev/null || true; }

quit_app() {
  local pid
  # A clean quit first, addressed to that process by its pid (the quit Apple event, through NSRunningApplication).
  for pid in $(app_pids); do
    case "$pid" in ""|*[!0-9]*) continue ;; esac
    osascript -l JavaScript -e "ObjC.import('AppKit'); var app = \$.NSRunningApplication.runningApplicationWithProcessIdentifier($pid); app.isNil() ? 'gone' : (app.terminate ? 'asked' : 'refused')" >/dev/null 2>&1 || true
  done
  # The app's own program only: aris-agent and aris-tools run from the same folder now, and the helper is restarted
  # once, further down, never killed here (a kill and a kickstart within ten seconds would leave it down).
  for _ in 1 2 3 4 5 6; do pgrep -f "$APP/Contents/MacOS/Aris( |\$)" >/dev/null || break; sleep 1; done
  pkill -9 -f "$APP/Contents/MacOS/Aris( |\$)" 2>/dev/null || true
}

# The bundle at $1 copied next to the installed app and verified there, while the installed one keeps running.
stage_beside() {
  local beside
  beside="$(dirname "$APP")"
  rm -rf "$beside/.Aris.incoming" "$beside/.Aris.outgoing"
  ditto "$1" "$beside/.Aris.incoming" || { echo "could not copy the app next to $APP" >&2; return 1; }
  codesign --verify --deep --strict "$beside/.Aris.incoming" \
    || { rm -rf "$beside/.Aris.incoming"; echo "the copy of the app in $beside does not verify" >&2; return 1; }
}

# The copy stage_beside made takes the installed app's place: two renames, and the old one back if the second fails.
place_incoming() {
  local beside
  beside="$(dirname "$APP")"
  if [ -e "$APP" ]; then mv "$APP" "$beside/.Aris.outgoing" || return 1; fi
  if ! mv "$beside/.Aris.incoming" "$APP"; then
    [ -e "$beside/.Aris.outgoing" ] && mv "$beside/.Aris.outgoing" "$APP"
    return 1
  fi
  rm -rf "$beside/.Aris.outgoing"
}

open_and_wait() {
  open "$APP" || { echo "macOS would not open $APP" >&2; return 1; }
  for _ in $(seq 1 60); do listening "$HOOK_PORT" && break; sleep 1; done
  listening "$HOOK_PORT" || { echo "Aris was opened but its hook server (port $HOOK_PORT) did not come up within 60 s" >&2; return 1; }
  # The app makes its own helper the one that runs (it writes and loads the job when that is needed): up to a minute.
  for _ in $(seq 1 60); do listening "$AGENT_PORT" && break; sleep 1; done
  listening "$AGENT_PORT" || { echo "the agent is not answering on port $AGENT_PORT" >&2; return 1; }
}

# The build the running helper wrote down when it started; empty when there is none.
agent_stamp() { tr -d '[:space:]' < "$ARIS_DIR/aris/agent-build" 2>/dev/null || true; }

# The helper's own copy from an install made the old way, kept once before the app's first launch removes it, with its
# LaunchAgent: what --rollback needs to go back across the switch to one bundle. Kept as an archive, never as a
# program that could be started where it lies (security review 4, M4: the old build is not hardened, and the old
# "aris-agent" rows in System Settings still answer to a helper at the old path).
keep_old_layout() {
  [ -f "$ARIS_DIR/aris-agent" ] && [ ! -L "$ARIS_DIR/aris-agent" ] || return 0
  local work="$PREV/old-layout.tmp"
  rm -rf "$work" "$PREV/old-layout" "$PREV/old-layout.tgz" && mkdir -p "$work" || return 1
  cp -p "$ARIS_DIR/aris-agent" "$work/aris-agent" || return 1
  [ -f "$ARIS_DIR/aris-tools" ] && [ ! -L "$ARIS_DIR/aris-tools" ] && cp -p "$ARIS_DIR/aris-tools" "$work/aris-tools"
  [ -d "$ARIS_DIR/skills" ] && cp -Rp "$ARIS_DIR/skills" "$work/skills"
  cp -p "$AGENT_PLIST" "$work/agent.plist" 2>/dev/null || true
  ( cd "$work" && tar czf "$PREV/old-layout.tgz" . ) && chmod 600 "$PREV/old-layout.tgz" || { rm -rf "$work"; return 1; }
  rm -rf "$work"
  echo "kept the helper of the old layout in $PREV/old-layout.tgz (for a rollback across the switch to one bundle)"
}

# Puts that old layout back: only when the app being restored has no helper inside it.
restore_old_layout() {
  local domain work="$PREV/old-layout.tmp"
  [ -f "$PREV/old-layout.tgz" ] || { echo "  (the previous app has no helper inside and none was kept beside it)" >&2; return 1; }
  rm -rf "$work" && mkdir -p "$work" && tar xzf "$PREV/old-layout.tgz" -C "$work" || return 1
  [ -f "$work/aris-agent" ] && [ -f "$work/agent.plist" ] || { rm -rf "$work"; echo "  (the kept old layout is incomplete)" >&2; return 1; }
  domain="gui/$(id -u)"
  launchctl bootout "$domain/$AGENT_LABEL" 2>/dev/null || true
  for _ in $(seq 1 40); do listening "$AGENT_PORT" || break; sleep 0.5; done
  rm -f "$ARIS_DIR/aris-tools"
  cp -p "$work/aris-agent" "$ARIS_DIR/aris-agent" && chmod 700 "$ARIS_DIR/aris-agent" || { rm -rf "$work"; return 1; }
  [ -f "$work/aris-tools" ] && cp -p "$work/aris-tools" "$ARIS_DIR/aris-tools" && chmod 700 "$ARIS_DIR/aris-tools"
  [ -d "$work/skills" ] && { rm -rf "$ARIS_DIR/skills"; cp -Rp "$work/skills" "$ARIS_DIR/skills"; }
  cp -p "$work/agent.plist" "$AGENT_PLIST" || { rm -rf "$work"; return 1; }
  rm -rf "$work"
  launchctl bootstrap "$domain" "$AGENT_PLIST" || return 1
  for _ in $(seq 1 60); do listening "$AGENT_PORT" && return 0; sleep 0.5; done
  return 1
}

# The kept previous build back in place and running. Used by --rollback and by a failure during the swap.
put_back() {
  set +e
  local ok=0
  if [ -d "$PREV/Aris.previous" ]; then
    stage_beside "$PREV/Aris.previous" && { quit_app; place_incoming; } || ok=1
  else
    quit_app
    echo "  (no previous app was kept: the app was left as it is)" >&2
  fi
  if [ -d "$APP" ]; then
    if [ -x "$APP/Contents/MacOS/aris-agent" ]; then
      # One bundle: the helper is restarted once from the app that is back (or set up by the app when it opens).
      "$INSTALLER" --restart || ok=1
    else
      restore_old_layout || ok=1
    fi
    open_and_wait || ok=1
  fi
  return $ok
}

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }

# The team a signature belongs to; empty for ad-hoc, unsigned or missing.
team_of() { codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p' | grep -v '^not set$' | head -1 || true; }

# The commit compiled into a program, read from its bytes (the program is never run here); empty when it has none.
program_stamp() { grep -a -o -E 'aris-build-commit:[0-9a-zA-Z._-]+' "$1" 2>/dev/null | head -1 | sed 's/^aris-build-commit://' || true; }

NOW=0; CLEAN=0; BUNDLE=""; BUNDLE_GIVEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --now) NOW=1 ;;
    --rollback) ROLLBACK=1 ;;
    --clean) CLEAN=1 ;;
    --bundle)
      [ $# -ge 2 ] || { echo "--bundle needs the path of a built, signed Aris.app" >&2; usage >&2; exit 2; }
      BUNDLE="$2"; BUNDLE_GIVEN=1; shift ;;
    --bundle=*) BUNDLE="${1#--bundle=}"; BUNDLE_GIVEN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
if [ "$BUNDLE_GIVEN" = "1" ]; then
  [ -n "$BUNDLE" ] || { echo "--bundle needs the path of a built, signed Aris.app" >&2; usage >&2; exit 2; }
  if [ "$ROLLBACK" = "1" ] || [ "$CLEAN" = "1" ]; then echo "--bundle cannot be combined with --rollback or --clean" >&2; exit 2; fi
fi

trap on_exit EXIT

# A signed helper or tools of any build, put inside any copy of Aris.app, is charged to Aris by macOS with everything
# the user granted it (measured: follow-up U1). So no signed copy is left lying where it is not needed.
if [ "$CLEAN" = "1" ]; then
  step "clean: removing the signed copies this script keeps"
  for copy in "$STAGE/Aris.app" "$STAGE/agent" "$PRODUCT" "$PREV/Aris.previous" "$PREV/Aris.previous.new" "$PREV/old-layout" "$PREV/old-layout.tgz" "$PREV/old-layout.tmp" "$PREV/agent" "$PREV/app-commit"; do
    if [ -e "$copy" ]; then rm -rf "$copy" && echo "removed $copy"; fi
  done
  echo
  echo "CLEANED: no signed copy of Aris is kept beside this script. There is nothing to roll back to until the next deploy."
  exit 0
fi

if [ "$ROLLBACK" = "1" ]; then
  step "rollback: putting back the build the last deploy replaced"
  [ -d "$PREV/Aris.previous" ] || die "nothing is kept in $PREV: no deploy has replaced a build yet"
  echo "kept app: $(cat "$PREV/app-commit" 2>/dev/null | grep . || echo "commit not recorded")"
  (put_back) || die "the previous build could not be put back completely (see the lines above)"
  echo
  # (Seen in the first real run, 2026-11-11: this line said the newer build "is still in $STAGE"; it is not: a deploy
  # removes its signed staging copy when it is done.)
  echo "ROLLED BACK: the previous Aris is installed and running. The newer build is not kept anywhere by this script: deploy again to install it."
  exit 0
fi

# ---------------------------------------------------------------------------------------------------------------------
if [ "$BUNDLE_GIVEN" = "1" ]; then
  step "1/6 what is being installed (a bundle that is already built and signed; nothing is built here)"
  for tool in codesign ditto lsof; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
  done
  [ -x "$INSTALLER" ] || die "no $INSTALLER beside deploy.sh"
  [ -d "$BUNDLE" ] || die "there is no bundle at $BUNDLE"
  BUNDLE="$(cd "$BUNDLE" && pwd -P)"
  for program in Aris aris-agent aris-tools; do
    [ -x "$BUNDLE/Contents/MacOS/$program" ] || die "$BUNDLE is not an assembled Aris.app: it has no Contents/MacOS/$program (Tests/assemble-app.sh puts the helper and its tools in)"
  done
  APP_REAL="$(cd "$APP" 2>/dev/null && pwd -P || true)"
  if [ -n "$APP_REAL" ] && [ "$BUNDLE" = "$APP_REAL" ]; then die "the bundle is the installed app itself ($APP): give a copy of the new build from outside /Applications"; fi
  COMMIT="$(app_stamp "$BUNDLE")"
  EXPECTED="$(program_stamp "$BUNDLE/Contents/MacOS/aris-agent")"
  TOOLS_STAMP="$(program_stamp "$BUNDLE/Contents/MacOS/aris-tools")"
  echo "bundle:  $BUNDLE"
  echo "stamped: app ${COMMIT:-without a commit stamp}, helper ${EXPECTED:-without a commit stamp}, tools ${TOOLS_STAMP:-without a commit stamp}"
  if [ -n "$COMMIT" ] && [ -n "$EXPECTED" ] && [ "$COMMIT" != "$EXPECTED" ]; then
    die "the bundle is not one build: its app is stamped $COMMIT, the helper inside it $EXPECTED"
  fi
  if [ -n "$EXPECTED" ] && [ -n "$TOOLS_STAMP" ] && [ "$TOOLS_STAMP" != "$EXPECTED" ]; then
    die "the bundle is not one build: its helper is stamped $EXPECTED, its tools $TOOLS_STAMP"
  fi
  [ -n "$COMMIT" ] || COMMIT="${EXPECTED:-unstamped}"
  echo "installed now: app $(app_stamp "$APP" | grep . || echo "without a commit stamp, or none")"
  BUNDLE_TEAM="$(team_of "$BUNDLE")"; INSTALLED_TEAM="$(team_of "$APP")"
  echo "signed:  the bundle by ${BUNDLE_TEAM:-no team (ad-hoc or unsigned)}; the installed app by ${INSTALLED_TEAM:-no team (ad-hoc, unsigned or not installed)}"
  if [ -n "$INSTALLED_TEAM" ] && [ "$BUNDLE_TEAM" != "$INSTALLED_TEAM" ]; then
    if [ "${ALLOW_OTHER_SIGNER:-}" = "1" ]; then
      echo "WARNING: the bundle is not signed by the team of the installed Aris ($INSTALLED_TEAM): macOS will treat it as another program, and its permissions and saved keys have to be given again (ALLOW_OTHER_SIGNER=1 was given)." >&2
    else
      die "the bundle is not signed by the team of the installed Aris (bundle: ${BUNDLE_TEAM:-no team}, installed: $INSTALLED_TEAM): macOS would treat it as another program and forget every permission. ALLOW_OTHER_SIGNER=1 $0 --bundle … accepts that."
    fi
  fi
  echo "agent:   $("$INSTALLER" --agent-status 2>/dev/null || echo "not checked") (looked at again before the swap)"
  mkdir -p "$STAGE"

  step "2/6 to 4/6 building and the launch check: left out (--bundle: the bundle is already built)"

  step "5/6 verifying the bundle and copying it into $STAGE"
  codesign --verify --deep --strict "$BUNDLE" || die "the bundle's signature does not verify: $BUNDLE"
  for program in aris-agent aris-tools; do
    described="$(codesign -dv "$BUNDLE/Contents/MacOS/$program" 2>&1 || true)"
    grep -q "^Identifier=com.lumenjsn.aris.$program$" <<<"$described" || die "$program inside the bundle does not carry its signing identifier (com.lumenjsn.aris.$program): macOS would not know it as Aris's"
    grep -q "flags=.*runtime" <<<"$described" || die "$program inside the bundle is not signed with the hardened runtime"
  done
  rm -rf "$STAGE/Aris.app"
  ditto "$BUNDLE" "$STAGE/Aris.app" || die "could not copy the bundle into $STAGE"
  codesign --verify --deep --strict "$STAGE/Aris.app" || die "the copy of the bundle in $STAGE does not verify"
  echo "verified"
else
# The usual path: build, check and sign here (the lines of steps 1 to 5 are not indented under this "else").
step "1/6 what is being built"
for tool in git xcodebuild swiftc codesign security ditto lsof; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed (Xcode and its command line tools are needed; see docs/BUILD.md)"
done
[ -d "$SRC/Aris.xcodeproj" ] || die "no source at $SRC (deploy.sh expects to sit in the repository's Scripts folder)"
[ -x "$INSTALLER" ] || die "no $INSTALLER beside deploy.sh"
COMMIT="$(git -C "$SRC" rev-parse --short=8 HEAD 2>/dev/null || echo unknown)"
CHANGED="$(git -C "$SRC" --no-optional-locks status --porcelain --untracked-files=no 2>/dev/null || true)"
echo "source:  $SRC"
echo "branch:  $(git -C "$SRC" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "not a git checkout")"
echo "commit:  $(git -C "$SRC" log -1 --abbrev=8 --format='%h %s' 2>/dev/null || echo unknown)"
if [ -n "$CHANGED" ]; then
  COMMIT="$COMMIT-dirty"
  echo "WARNING: $(printf '%s\n' "$CHANGED" | grep -c .) tracked file(s) have uncommitted changes; they are built in, and the build is stamped $COMMIT." >&2
fi
echo "installed now: app $(app_stamp "$APP" | grep . || echo "without a commit stamp, or none")"
SIGN_ID="$("$INSTALLER" --resolve-identity "$APP")" || die "no usable signing identity (the reason is above)"
export SIGN_ID ARIS_SIGN_RESOLVED=1 ARIS_COMMIT="$COMMIT"
echo "signing: $([ "$SIGN_ID" = "-" ] && echo "ad-hoc" || echo "\"$SIGN_ID\"")"
echo "agent:   $("$INSTALLER" --agent-status 2>/dev/null || echo "not checked") (looked at again before the swap)"
mkdir -p "$STAGE"

# ---------------------------------------------------------------------------------------------------------------------
step "2/6 building the app (Release)"
# Products left by earlier builds (e.g. the XPC helper under its old name) must not end up inside the new app.
rm -rf "$PRODUCT"
if ! (cd "$SRC" && xcodebuild -project Aris.xcodeproj -scheme Aris -configuration Release \
        -derivedDataPath "$BUILD" CODE_SIGNING_ALLOWED=NO ARIS_COMMIT="$COMMIT" build) > "$STAGE/xcodebuild.log" 2>&1; then
  grep -E "error:|BUILD FAILED" "$STAGE/xcodebuild.log" | head -30 >&2 || true
  die "the app did not build (full log: $STAGE/xcodebuild.log)"
fi
[ -x "$PRODUCT/Contents/MacOS/Aris" ] || die "xcodebuild reported success but there is no app at $PRODUCT (log: $STAGE/xcodebuild.log)"
echo "BUILD SUCCEEDED"
STAMPED="$(app_stamp "$PRODUCT")"
if [ -z "$STAMPED" ]; then
  echo "WARNING: the app carries no commit stamp (Aris/Info.plist has no ArisCommit key in this source)." >&2
elif [ "$STAMPED" != "$COMMIT" ]; then
  die "the app is stamped $STAMPED but the source is at $COMMIT (a stale build product?)"
fi

# ---------------------------------------------------------------------------------------------------------------------
step "3/6 building and checking aris-agent and aris-tools"
"$INSTALLER" --stage "$STAGE/agent" || die "aris-agent and aris-tools are not ready (the reason is above)"

# ---------------------------------------------------------------------------------------------------------------------
step "4/6 launch check of the new app"
if [ "${SKIP_SMOKE:-}" = "1" ]; then
  echo "skipped (SKIP_SMOKE=1)"
else
  # The unsigned product: a signed copy carries the App Sandbox, which cannot start inside the check's own sandbox.
  bash "$TESTS/launch-smoke.sh" "$PRODUCT/Contents/MacOS/Aris" \
    || die "the new app failed its launch check (lines above). If the check itself is at fault, SKIP_SMOKE=1 $0 leaves it out."
fi

# ---------------------------------------------------------------------------------------------------------------------
step "5/6 putting aris-agent and aris-tools into the app, signing it all in $STAGE and verifying it"
[ -f "$TESTS/assemble-app.sh" ] || die "no $TESTS/assemble-app.sh (it puts the two programs into the app and signs everything inside-out)"
rm -rf "$STAGE/Aris.app"
ditto "$PRODUCT" "$STAGE/Aris.app" || die "could not copy the built app into $STAGE"
SRC="$SRC" bash "$TESTS/assemble-app.sh" "$STAGE/Aris.app" "$STAGE/agent" "$SIGN_ID" || die "the app could not be assembled and signed (the reason is above)"
[ -x "$STAGE/Aris.app/Contents/MacOS/aris-agent" ] && [ -x "$STAGE/Aris.app/Contents/MacOS/aris-tools" ] || die "the assembled app has no aris-agent or aris-tools inside it"
echo "signed ok"
# The build the helper must report after the swap.
EXPECTED="$(cat "$STAGE/agent/commit" 2>/dev/null || true)"
fi

# ---------------------------------------------------------------------------------------------------------------------
step "6/6 swapping in the new build"
mkdir -p "$PREV" && chmod 700 "$PREV"
if [ -d "$APP" ]; then
  rm -rf "$PREV/Aris.previous.new"
  ditto "$APP" "$PREV/Aris.previous.new" || die "could not keep the installed app in $PREV"
  rm -rf "$PREV/Aris.previous" && mv "$PREV/Aris.previous.new" "$PREV/Aris.previous"
  app_stamp "$APP" > "$PREV/app-commit"
  echo "kept the installed app in $PREV/Aris.previous"
else
  rm -rf "$PREV/Aris.previous" "$PREV/app-commit"
  echo "no app installed yet at $APP: nothing to keep for a rollback"
fi
# The one-bundle layout has already run here (the installed app carries its helper): the old layout's archive is not
# needed for any rollback from now on, and nothing of the old helper is kept longer than that.
if [ -x "$APP/Contents/MacOS/aris-agent" ]; then rm -rf "$PREV/old-layout" "$PREV/old-layout.tgz"; fi
keep_old_layout || die "could not keep the helper of the old layout in $PREV"
stage_beside "$STAGE/Aris.app" || die "the new app could not be copied next to $APP"
# Last thing before Aris is quit (quitting the app ends what it was waiting for, too): let the agent finish its work.
if [ "$NOW" = "1" ]; then "$INSTALLER" --wait-idle --now; else "$INSTALLER" --wait-idle; fi
SWAPPING=1
quit_app
# Aris's folder was ~/.config/boring-notch. Move it once, with the app and agent stopped, and leave a link so
# hooks and scripts installed under the old name keep working.
OLD_DIR="$HOME/.config/boring-notch"; NEW_DIR="$ARIS_DIR"
if [ -d "$OLD_DIR" ] && [ ! -L "$OLD_DIR" ] && [ ! -e "$NEW_DIR" ]; then
  launchctl bootout "gui/$(id -u)/com.lumenjsn.aris.aris-agent" 2>/dev/null || true
  mv "$OLD_DIR" "$NEW_DIR" && ln -s "$NEW_DIR" "$OLD_DIR" && echo "moved $OLD_DIR -> $NEW_DIR (link left)"
fi
place_incoming || die "the new app could not be put at $APP"
echo "new app in place at $APP"
# One restart, promptly: the helper that kept running is the old build, while the tools it starts are already the new one.
"$INSTALLER" --restart || die "the helper did not come back after the swap (the reason is above)"
open_and_wait || die "the new Aris did not come up (the reason is above)"
# The helper that answers must be the one inside the new app: it writes down its build when it starts.
RUNNING="$(agent_stamp)"
if grep -a -q "aris-build-commit:$EXPECTED" "$APP/Contents/MacOS/aris-agent" 2>/dev/null && [ -n "$EXPECTED" ]; then
  for _ in $(seq 1 30); do [ "$RUNNING" = "$EXPECTED" ] && break; sleep 1; RUNNING="$(agent_stamp)"; done
  [ "$RUNNING" = "$EXPECTED" ] || die "the helper that answers is build ${RUNNING:-unknown}, not $EXPECTED: the app did not start its own helper"
else
  echo "WARNING: aris-agent carries no commit stamp, so it cannot be checked that the helper answering is the new one." >&2
fi
SWAPPING=0
echo "hook server up"
# The staged copy is a complete, signed Aris.app: opened by mistake it would take the helper's job over from the
# installed one (security review 4, L2). It has done its work.
rm -rf "$STAGE/Aris.app"

echo
echo "DEPLOYED $COMMIT: app $(app_stamp "$APP" | grep . || echo unstamped), helper $RUNNING (inside the app)."
echo "To go back to the build that was replaced: $0 --rollback"
