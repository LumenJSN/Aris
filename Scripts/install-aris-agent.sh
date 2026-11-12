#!/bin/bash
# The developer's helper for aris-agent and aris-tools. They live inside Aris.app now (Contents/MacOS), so that macOS
# shows one row, "Aris", for every permission, and the app installs its own LaunchAgent at launch (the XPC helper's
# installAgent): a person who installs Aris runs no script. What is left here is what deploy.sh needs around a swap:
#
#   install-aris-agent.sh --stage <dir>            build and check aris-agent and aris-tools into <dir> (nothing is installed;
#                                                  Tests/assemble-app.sh puts them into the app and signs them)
#   install-aris-agent.sh --restart                restart the helper once from the app that is installed, and wait for it
#   install-aris-agent.sh --wait-idle [--now]      only wait until the agent is doing nothing
#   install-aris-agent.sh --agent-status           say whether the agent is idle, busy (with what) or not running
#   install-aris-agent.sh --resolve-identity [installed path…]   print the signing identity that will be used
#
# --now: do not wait for the agent's work (that work is cut off by the restart). Without it --wait-idle waits up to
# IDLE_WAIT seconds (default 120) for the agent to finish, then gives up waiting and says what will be cut off.
# Where each duty of the old script went is listed in docs/BUILD.md ("One row").
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT"
# Where the build and check scripts live (build-agent.sh holds the one list of source files; min-os-check.sh).
TESTS="${TESTS:-$ROOT/Tests}"
# Aris's own folder. ARIS_DIR exists so the script can be tried against a throwaway folder.
DIR="${ARIS_DIR:-$HOME/.config/aris}"
# The installed app, whose Contents/MacOS holds the helper. APP exists so the script can be tried against a throwaway folder.
APP="${APP:-/Applications/Aris.app}"
BIN="$APP/Contents/MacOS/aris-agent"
LABEL="com.lumenjsn.aris.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PORT=23351
IDLE_WAIT="${IDLE_WAIT:-120}"
DEFAULT_SIGN_ID="Apple Development"
# The marker build-agent.sh compiles into both programs (Shared/ArisBuildStamp.swift), followed by the commit.
STAMP_MARK="aris-build-commit:"

fail() { echo "aris-agent install FAILED: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------------------------------------------------
# Signing. One rule for the whole app (deploy.sh asks with --resolve-identity; Tests/assemble-app.sh signs).
# Signed with a real identity, macOS keeps the permissions given to Aris (Accessibility, Screen Recording, Full Disk
# Access…) across rebuilds; an ad-hoc signature is a new program every build.
# SIGN_ID="-" asks for ad-hoc (permissions then have to be given again after each install).
# The identifiers below still carry the old name on purpose: changing them would make macOS forget those permissions.

adhoc_warning() {
  cat >&2 <<EOF

======================================================================================
  SIGNING AD-HOC: $1
  macOS treats every ad-hoc build as a new program. After this install the permissions
  of Aris (Microphone, Speech, Accessibility, Screen Recording, Full Disk Access: the
  last is switched off by macOS) and its saved keys have to be granted again, even where System Settings
  still shows them switched on. See docs/BUILD.md ("Signing").
======================================================================================

EOF
}

# True when what is installed at the path is signed with a certificate (so its permissions would survive a rebuild).
signed_with_certificate() {
  local described
  [ -e "$1" ] || return 1
  described="$(codesign -dvv "$1" 2>&1 || true)"
  grep -q '^Authority=' <<<"$described"
}

# Prints the identity to sign with: the wanted one when the keychain has exactly one match, "-" for ad-hoc.
# Never falls back in silence: ad-hoc is announced, and it is refused when it would drop permissions already granted
# to a certificate-signed install (SIGN_ID=- accepts that).
resolve_identity() {
  local wanted="${SIGN_ID:-$DEFAULT_SIGN_ID}" found count path
  if [ "$wanted" = "-" ]; then
    adhoc_warning "SIGN_ID=- was asked for."
    echo "-"; return 0
  fi
  # Each identity is a line with its 40-character hash; the wanted one is matched by name or by that hash.
  found="$(security find-identity -v -p codesigning 2>/dev/null | grep '[0-9A-F]\{40\}' | grep -F "$wanted" || true)"
  count="$(printf '%s' "$found" | grep -c . || true)"
  if [ "$count" -eq 1 ]; then echo "$wanted"; return 0; fi
  if [ "$count" -gt 1 ]; then
    { echo "signing: $count identities match \"$wanted\", so codesign cannot choose:"; printf '%s\n' "$found"
      echo "Run again with SIGN_ID set to the 40-character hash of the one to use."; } >&2
    return 1
  fi
  if [ -n "${SIGN_ID:-}" ]; then
    echo "signing: no code-signing identity named \"$wanted\" in the keychain (security find-identity -v -p codesigning)." >&2
    return 1
  fi
  for path in "$BIN" "$@"; do
    if signed_with_certificate "$path"; then
      { echo "signing: no \"$wanted\" identity in the keychain, but $path is signed with a certificate."
        echo "An ad-hoc build would make macOS forget its permissions and saved keys, so nothing was changed."
        echo "Either restore the certificate, or accept that with: SIGN_ID=- $0"; } >&2
      return 1
    fi
  done
  adhoc_warning "no \"$wanted\" identity in the keychain."
  echo "-"
}

# ---------------------------------------------------------------------------------------------------------------------
# What is being built.

# The commit of the source, with "-dirty" when tracked files have uncommitted changes; "unknown" outside git.
source_commit() {
  local commit
  commit="$(git -C "$SRC" rev-parse --short=8 HEAD 2>/dev/null)" || { echo "unknown"; return 0; }
  [ -z "$(git -C "$SRC" --no-optional-locks status --porcelain --untracked-files=no 2>/dev/null)" ] || commit="$commit-dirty"
  echo "$commit"
}

# The commit compiled into a program, read from its bytes (the program is never run here); empty when it has none.
stamp_of() {
  grep -a -o -E "$STAMP_MARK[0-9a-zA-Z._-]+" "$1" 2>/dev/null | head -1 | sed "s/^$STAMP_MARK//" || true
}

# ---------------------------------------------------------------------------------------------------------------------
# Build, check and sign into a staging folder. Nothing outside the folder changes.

stage_build() {
  local stage="$1" commit name found
  [ -n "$stage" ] || fail "--stage needs a folder"
  [ -f "$TESTS/build-agent.sh" ] || fail "no $TESTS/build-agent.sh (it holds the list of source files the agent is built from)"
  [ -f "$TESTS/min-os-check.sh" ] || fail "no $TESTS/min-os-check.sh (it checks the programs run on the app's lowest macOS)"
  commit="${ARIS_COMMIT:-$(source_commit)}"
  mkdir -p "$stage" && chmod 700 "$stage"
  rm -rf "$stage/aris-agent" "$stage/aris-tools" "$stage/skills"
  echo "building aris-agent and aris-tools ($commit)…"
  # build-agent.sh compiles both for the app's own lowest macOS and checks them (min-os-check.sh).
  if ! OUT="$stage" ARIS_COMMIT="$commit" bash "$TESTS/build-agent.sh" > "$stage/build.log" 2>&1; then
    grep -E "error:|MIN OS CHECK FAILED|min-os:|No such file" "$stage/build.log" | head -30 >&2 || true
    fail "aris-agent and aris-tools did not build or failed the macOS check (full log: $stage/build.log)"
  fi
  for name in aris-agent aris-tools; do
    [ -f "$stage/$name" ] || fail "the build reported success but made no $name (log: $stage/build.log)"
    found="$(stamp_of "$stage/$name")"
    if [ -z "$found" ]; then
      echo "WARNING: $name carries no commit stamp (the source has no Shared/ArisBuildStamp.swift in its build list)." >&2
    elif [ "$found" != "$commit" ]; then
      fail "$name is stamped $found but the source is at $commit (a stale build?)"
    fi
  done
  printf '%s\n' "$commit" > "$stage/commit"
  echo "built aris-agent and aris-tools ($commit) in $stage (they are signed when they are put into the app)"
}

# ---------------------------------------------------------------------------------------------------------------------
# Is the agent doing something? There is no status route yet, so this looks from outside: every answer of the agent
# closes its connection, so a request it has not finished (a turn, a background task, a teammate's job) is an open
# connection to its port; and a scheduled job that is running is marked in schedules.json.

agent_pid() { lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -1 || true; }

# "<running> <waiting for an answer>" scheduled jobs; "0 0" when the file is missing or unreadable.
scheduled_jobs() {
  /usr/bin/python3 -I - "$DIR/aris/schedules.json" <<'PY' 2>/dev/null || echo "0 0"
import json, sys
try:
    with open(sys.argv[1]) as handle:
        jobs = json.load(handle)
except (OSError, ValueError):
    jobs = []
jobs = [job for job in jobs if isinstance(job, dict)] if isinstance(jobs, list) else []
print(sum(1 for job in jobs if job.get("runningSince")), sum(1 for job in jobs if job.get("parked")))
PY
}

# Prints what the agent is doing, in words; prints nothing when it is idle or not running.
agent_busy() {
  local pid open jobs running parked tools said=""
  pid="$(agent_pid)"
  [ -n "$pid" ] || return 0
  # aris-tools still at work, whoever its parent is now: a restart kills the helper's own children but not a command
  # that detached itself (follow-up experiment, 6-chain.txt), and that one would go on under the old build.
  # Counted by the program's own name (pgrep -x), never by command lines: the AI program the helper keeps running
  # between turns (claude -p …) carries "…/aris-tools " dozens of times in its arguments (its instructions), and a
  # search of command lines took it for a tool at work for as long as it lived. Seen in the first real run
  # (2026-11-11, VM): after any turn every deploy waited the whole IDLE_WAIT and then warned about work being cut off.
  tools="$(pgrep -x aris-tools 2>/dev/null | wc -l | tr -d ' ' || true)"
  open="$(lsof -nP -a -p "$pid" -iTCP:"$PORT" -sTCP:ESTABLISHED 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ' || true)"
  jobs="$(scheduled_jobs)"; running="${jobs%% *}"; parked="${jobs##* }"
  [ "${open:-0}" -gt 0 ] && said="$open request(s) being answered"
  [ "${running:-0}" -gt 0 ] && said="${said:+$said, }$running scheduled job(s) running"
  [ "${tools:-0}" -gt 0 ] && said="${said:+$said, }$tools aris-tools command(s) still running"
  [ -n "$said" ] && [ "${parked:-0}" -gt 0 ] && said="$said, $parked waiting for an answer from you"
  printf '%s' "$said"
}

wait_idle() {
  local now="$1" waited=0 what
  what="$(agent_busy)"
  if [ -z "$what" ]; then echo "the agent is idle"; return 0; fi
  if [ "$now" = "1" ]; then
    echo "WARNING: the agent is busy ($what) and --now was given: restarting it anyway; that work is cut off." >&2
    return 0
  fi
  echo "the agent is busy ($what): waiting up to ${IDLE_WAIT}s for it to finish (--now restarts at once)…"
  while [ "$waited" -lt "$IDLE_WAIT" ]; do
    sleep 2; waited=$((waited + 2))
    what="$(agent_busy)"
    if [ -z "$what" ]; then echo "the agent is idle (after ${waited}s)"; return 0; fi
  done
  echo "WARNING: the agent is still busy after ${IDLE_WAIT}s ($what): restarting it anyway; that work is cut off (Aris reports it as interrupted)." >&2
}

# ---------------------------------------------------------------------------------------------------------------------
# Restart. The helper is launchd's job, started from inside the app; after the app was replaced the running helper is
# still the old build, so it is restarted once. Never twice within ten seconds: launchd waits that long between two
# starts of one job, and a second kickstart inside it leaves the helper down until they are over.

listening() { lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; }

# The program the installed LaunchAgent starts; empty when there is no such file.
job_program() { /usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$PLIST" 2>/dev/null || true; }

restart_agent() {
  local old_pid new_pid domain program
  domain="gui/$(id -u)"
  program="$(job_program)"
  if [ "$program" != "$BIN" ]; then
    # A new Mac, an app that was moved, or an install made the old way: the app writes and loads the job itself the
    # next time it is opened (and removes the helper's old copies from $DIR).
    echo "the LaunchAgent does not point at $BIN yet (${program:-no job file}): Aris sets its helper up itself when it is opened"
    return 0
  fi
  [ -x "$BIN" ] || fail "there is no aris-agent inside $APP (was the app assembled with Tests/assemble-app.sh?)"
  old_pid="$(agent_pid)"
  if ! launchctl kickstart -k "$domain/$LABEL" 2>/dev/null; then
    echo "the helper's job is not loaded: Aris loads it itself when it is opened"
    return 0
  fi
  # Back within a second or two; up to 30 s is allowed (launchd's own ten-second wait included).
  for _ in $(seq 1 60); do
    new_pid="$(agent_pid)"
    if [ -n "$new_pid" ] && [ "$new_pid" != "$old_pid" ]; then echo "aris agent up (pid $new_pid)"; return 0; fi
    sleep 0.5
  done
  fail "the helper was restarted but did not open port $PORT within 30 s (see $DIR/aris/agent.log). It was NOT kickstarted a second time: launchd starts it by itself."
}

# ---------------------------------------------------------------------------------------------------------------------

MODE="help"; STAGE_ARG=""; NOW=0; EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --now) NOW=1 ;;
    --stage)
      MODE="${1#--}"; STAGE_ARG="${2:-}"; [ -n "$STAGE_ARG" ] || fail "$1 needs a folder"; shift ;;
    --restart|--wait-idle|--agent-status|--resolve-identity) MODE="${1#--}" ;;
    --install-staged|--keep-previous|--restore-previous)
      fail "$1 is gone: aris-agent and aris-tools are inside Aris.app now, and one swap of the app replaces all three (deploy.sh; deploy.sh --rollback)" ;;
    -h|--help) MODE="help" ;;
    -*) fail "unknown option $1 (see --help)" ;;
    *) EXTRA+=("$1") ;;
  esac
  shift
done

case "$MODE" in
  resolve-identity) resolve_identity ${EXTRA[@]+"${EXTRA[@]}"} ;;
  wait-idle) wait_idle "$NOW" ;;
  agent-status)
    if [ -z "$(agent_pid)" ]; then echo "not running"; else WHAT="$(agent_busy)"; echo "${WHAT:+busy: }${WHAT:-idle}"; fi ;;
  stage) stage_build "$STAGE_ARG" ;;
  restart) restart_agent ;;
  help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
