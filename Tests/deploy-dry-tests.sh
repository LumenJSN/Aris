#!/bin/bash
# deploy-dry-tests.sh: runs deploy.sh, install-aris-agent.sh, the hooks installers, the status line and
# `promote.sh --dry-run` against a sandbox of fakes, and checks every failure case: the exit code, the message, and
# that the "installed" app and agent were not replaced. Nothing real is touched:
#   - each case gets a fresh temp folder with its own HOME, "Applications", config folder and copies of the scripts;
#   - xcodebuild, swiftc, codesign, security, launchctl, osascript, open, lsof, pgrep, pkill, curl and sleep are small
#     scripts first on PATH that only write down how they were called and can be told to fail (files in $STATE);
#   - the agent build (Tests/build-agent.sh) and the launch check are stand-ins too; Tests/assemble-app.sh is the real one;
#   - Aris is one bundle (aris-agent and aris-tools inside Aris.app): `open` stands in for the app, which sets its own
#     helper up when its LaunchAgent does not point into it yet, and `launchctl kickstart` for the helper starting.
# Usage: bash Tests/deploy-dry-tests.sh     (ends in ALL PASSED, or the number that failed; about a minute)
# SHIP=<folder> tests another copy of the scripts (default: the folder above this one).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SHIP="${SHIP:-$(cd "$DIR/../Scripts" && pwd)}"
SCRIPTS=(deploy.sh install-aris-agent.sh install-claude-hooks.py install-agent-hooks.py agent-hook.sh claude-statusline.sh)
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aris-deploy-dry.XXXXXX")" && pwd -P)"
# KEEP_WORK=1 keeps the sandboxes (each case's out.log, err.log and calls.log) for a look afterwards.
trap '[ "${KEEP_WORK:-}" = "1" ] && echo "kept: $WORK" || rm -rf "$WORK"' EXIT
REAL_HOME="$HOME"
REAL_APP_BEFORE="$(stat -f %m /Applications/Aris.app 2>/dev/null || echo none)"
failures=0
N=0

check() { if [ "$1" = "0" ]; then echo "ok   $2"; else failures=$((failures + 1)); echo "FAIL $2"; fi; }
# has <file> <words>: the file contains the words.
has() { grep -q -F -- "$2" "$1"; }
lacks() { ! grep -q -F -- "$2" "$1"; }
# yes <command…>: 0 when the command succeeds, for check.
yes() { "$@" >/dev/null 2>&1 && echo 0 || echo 1; }
no() { "$@" >/dev/null 2>&1 && echo 1 || echo 0; }

# ---------------------------------------------------------------------------------------------------------------------
# The fakes.

make_fakes() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/xcodebuild" <<'EOF'
#!/bin/bash
echo "xcodebuild $*" >> "$CALLS"
derived=""; commit=""
while [ $# -gt 0 ]; do
  case "$1" in -derivedDataPath) derived="$2"; shift ;; ARIS_COMMIT=*) commit="${1#ARIS_COMMIT=}" ;; esac
  shift
done
if [ -e "$STATE/fail-xcodebuild" ]; then echo "/src/Thing.swift:3:1: error: cannot find 'nope' in scope"; echo "** BUILD FAILED **"; exit 65; fi
app="$derived/Build/Products/Release/Aris.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/XPCServices/ArisXPCHelper.xpc"
printf '#!/bin/sh\nsleep 30\n' > "$app/Contents/MacOS/Aris"; chmod +x "$app/Contents/MacOS/Aris"
echo "new-build" > "$app/Contents/Resources/marker"
[ -e "$STATE/unstamped-app" ] && commit=""
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>Aris</string><key>ArisCommit</key><string>$commit</string></dict></plist>
PLIST
echo "** BUILD SUCCEEDED **"
EOF
  cat > "$bin/swiftc" <<'EOF'
#!/bin/bash
echo "swiftc $*" >> "$CALLS"; echo "swiftc must not be reached in these tests" >&2; exit 1
EOF
  cat > "$bin/codesign" <<'EOF'
#!/bin/bash
echo "codesign $*" >> "$CALLS"
target="${!#}"
case " $* " in
  *" --sign "*)
    if [ -e "$STATE/fail-sign" ] && grep -q -F "$(cat "$STATE/fail-sign")" <<<"$target"; then
      echo "$target: errSecInternalComponent" >&2; exit 1
    fi
    exit 0 ;;
  *" --verify "*)
    if [ -e "$STATE/fail-verify" ] && grep -q -F "$(cat "$STATE/fail-verify")" <<<"$target"; then
      echo "$target: invalid signature (code or signature have been modified)" >&2; exit 1
    fi
    exit 0 ;;
  *" -dv "*)
    # bundle-team / installed-team: the team of a bundle handed to --bundle (under /prebuilt/) and of the installed
    # app ("not set" is what codesign prints for ad-hoc); bundle-no-runtime / bundle-other-id spoil its programs.
    team="TEAM123456"; flags="0x10000(runtime)"; identifier="com.lumenjsn.aris.$(basename "$target")"
    case "$target" in
      */prebuilt/*)
        [ -e "$STATE/bundle-team" ] && team="$(cat "$STATE/bundle-team")"
        [ -e "$STATE/bundle-no-runtime" ] && flags="0x0(none)"
        [ -e "$STATE/bundle-other-id" ] && identifier="aris-agent-55554944" ;;
      */Applications/*) [ -e "$STATE/installed-team" ] && team="$(cat "$STATE/installed-team")" ;;
    esac
    echo "Identifier=$identifier"; echo "CodeDirectory v=20500 flags=$flags"; echo "TeamIdentifier=$team"
    exit 0 ;;
  *" -dvv "*)
    if [ -e "$STATE/installed-cert-signed" ]; then echo "Authority=Apple Development: Test Person (TEAM123456)"; else echo "Signature=adhoc"; fi
    exit 0 ;;
esac
exit 0
EOF
  cat > "$bin/security" <<'EOF'
#!/bin/bash
echo "security $*" >> "$CALLS"
if [ -e "$STATE/identities" ]; then cat "$STATE/identities"; else
  echo '  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Apple Development: Test Person (TEAM123456)"'
  echo '     1 valid identities found'
fi
EOF
  cat > "$bin/launchctl" <<'EOF'
#!/bin/bash
echo "launchctl $*" >> "$CALLS"
# The helper that starts writes down the build of the aris-agent it was started from.
started() {
  local program="$1" pid stamp
  pid="$(cat "$STATE/next-pid" 2>/dev/null || echo 2000)"; echo $((pid + 1)) > "$STATE/next-pid"
  echo "$pid" > "$STATE/listen-23351"
  stamp="$(grep -a -o 'aris-build-commit:[0-9a-zA-Z._-]*' "$program" 2>/dev/null | head -1 | sed 's/^aris-build-commit://')"
  left="$(cat "$STATE/helper-wrong-build" 2>/dev/null || echo 0)"
  if [ "$left" -gt 0 ]; then echo $((left - 1)) > "$STATE/helper-wrong-build"; stamp="wr0ng000"; fi
  mkdir -p "$HOME/.config/aris/aris"; [ -n "$stamp" ] && echo "$stamp" > "$HOME/.config/aris/aris/agent-build"
}
plist="$HOME/Library/LaunchAgents/com.lumenjsn.aris.agent.plist"
case "$1" in
  bootout) case "$2" in */com.lumenjsn.aris.agent) rm -f "$STATE/listen-23351" ;; esac; exit 0 ;;
  bootstrap)
    if [ -e "$STATE/fail-bootstrap" ]; then echo "Bootstrap failed: 5: Input/output error" >&2; exit 5; fi
    started "$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null)"; exit 0 ;;
  kickstart)
    if [ -e "$STATE/job-not-loaded" ]; then echo "Could not find service" >&2; exit 113; fi
    # agent-never-up holds how many restarts are swallowed (the helper is killed and never opens its port).
    left="$(cat "$STATE/agent-never-up" 2>/dev/null || echo 0)"
    if [ "$left" -gt 0 ]; then echo $((left - 1)) > "$STATE/agent-never-up"; rm -f "$STATE/listen-23351"; exit 0; fi
    started "$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null)"; exit 0 ;;
esac
exit 0
EOF
  cat > "$bin/lsof" <<'EOF'
#!/bin/bash
echo "lsof $*" >> "$CALLS"
port=""; for word in "$@"; do case "$word" in -iTCP:*) port="${word#-iTCP:}" ;; esac; done
case " $* " in
  *" -sTCP:LISTEN "*)
    [ -e "$STATE/listen-$port" ] || exit 1
    case " $* " in *" -t "*) cat "$STATE/listen-$port" ;; *) echo "COMMAND PID USER"; echo "fake $(cat "$STATE/listen-$port") user TCP 127.0.0.1:$port (LISTEN)" ;; esac
    exit 0 ;;
  *" -sTCP:ESTABLISHED "*)
    # busy: "<open requests> <how many more looks they stay open>"; after that the agent is idle.
    [ -f "$STATE/busy" ] || exit 1
    read -r open looks < "$STATE/busy" || exit 1
    [ "${open:-0}" -gt 0 ] && [ "${looks:-0}" -gt 0 ] || exit 1
    echo "$open $((looks - 1))" > "$STATE/busy"
    echo "COMMAND PID USER"; for _ in $(seq 1 "$open"); do echo "fake 1000 user TCP 127.0.0.1:$port->127.0.0.1:50000 (ESTABLISHED)"; done
    exit 0 ;;
esac
exit 1
EOF
  cat > "$bin/osascript" <<'EOF'
#!/bin/bash
echo "osascript $*" >> "$CALLS"
case "$*" in *"to quit"*) rm -f "$STATE/listen-23350" ;; esac
# The app quit by its pid (the running app is the pid in listen-23350): it goes unless app-ignores-quit says it hangs.
case "$*" in *"runningApplicationWithProcessIdentifier("*)
  pid="$(sed -n 's/.*runningApplicationWithProcessIdentifier(\([0-9]*\)).*/\1/p' <<<"$*")"
  if [ -n "$pid" ] && [ "$pid" = "$(cat "$STATE/listen-23350" 2>/dev/null)" ] && [ ! -e "$STATE/app-ignores-quit" ]; then rm -f "$STATE/listen-23350"; fi ;;
esac
exit 0
EOF
  cat > "$bin/open" <<'EOF'
#!/bin/bash
echo "open $*" >> "$CALLS"
[ -e "$STATE/fail-open" ] && { echo "The application cannot be opened" >&2; exit 1; }
# app-never-up holds how many launches are swallowed (the app opens but its hook server never comes up).
left="$(cat "$STATE/app-never-up" 2>/dev/null || echo 0)"
if [ "$left" -gt 0 ]; then echo $((left - 1)) > "$STATE/app-never-up"; exit 0; fi
echo 3000 > "$STATE/listen-23350"
# The app makes the helper inside it the one that runs (the XPC helper's installAgent): when the LaunchAgent does not
# point into this app, or nothing answers, it writes the job, links aris-tools, removes the old copies and loads it.
app="${!#}"; agent="$app/Contents/MacOS/aris-agent"; aris="$HOME/.config/aris"
plist="$HOME/Library/LaunchAgents/com.lumenjsn.aris.agent.plist"
if [ -x "$agent" ] && [ ! -e "$STATE/app-installs-nothing" ]; then
  program="$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null)"
  if [ "$program" != "$agent" ] || [ ! -e "$STATE/listen-23351" ]; then
    echo "app installs its helper from $app" >> "$CALLS"
    mkdir -p "$aris/aris" "$(dirname "$plist")"
    rm -f "$aris/aris-agent" "$aris/aris-agent.new" "$aris/aris-tools.new" "$aris/aris-tools"
    ln -s "$app/Contents/MacOS/aris-tools" "$aris/aris-tools"
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>com.lumenjsn.aris.agent</string><key>ProgramArguments</key><array><string>%s</string></array></dict></plist>\n' "$agent" > "$plist"
    launchctl bootstrap "gui/$(id -u)" "$plist"
  fi
fi
EOF
  cat > "$bin/pgrep" <<'EOF'
#!/bin/bash
echo "pgrep $*" >> "$CALLS"
# The app's own program (…/Aris.app/Contents/MacOS/Aris): running while its hook server is, as the pid written there.
case "$*" in *"/Contents/MacOS/Aris( |"*) [ -f "$STATE/listen-23350" ] && { cat "$STATE/listen-23350"; exit 0; }; exit 1 ;; esac
# tools-running: how many aris-tools commands are still at work.
case "$*" in *aris-tools*) [ -f "$STATE/tools-running" ] && { seq 1 "$(cat "$STATE/tools-running")" | sed 's/^/900/'; exit 0; } ;; esac
exit 1
EOF
  for name in pkill curl sleep; do printf '#!/bin/bash\necho "%s $*" >> "$CALLS"\nexit 0\n' "$name" > "$bin/$name"; done
  chmod +x "$bin"/*
}

# The stand-ins for Tests/build-agent.sh, min-os-check.sh and launch-smoke.sh.
make_fake_tests() {
  local tests="$1"
  mkdir -p "$tests"
  cat > "$tests/build-agent.sh" <<'EOF'
#!/bin/bash
echo "build-agent OUT=$OUT ARIS_COMMIT=${ARIS_COMMIT:-}" >> "$CALLS"
if [ -e "$STATE/fail-agent-build" ]; then echo "/src/ArisAgent/main.swift:9:1: error: cannot find 'ArisNope' in scope"; exit 1; fi
mkdir -p "$OUT"
stamp="aris-build-commit:${ARIS_COMMIT:-dev}"
[ -e "$STATE/unstamped-agent" ] && stamp="no stamp"
[ -e "$STATE/stale-agent" ] && stamp="aris-build-commit:0ld0ld00"
printf 'new agent %s\n' "$stamp" > "$OUT/aris-agent"; printf 'new tools %s\n' "$stamp" > "$OUT/aris-tools"
echo "AGENT BUILD OK ($OUT)"
EOF
  printf '#!/bin/bash\nexit 0\n' > "$tests/min-os-check.sh"
  cat > "$tests/launch-smoke.sh" <<'EOF'
#!/bin/bash
echo "launch-smoke $*" >> "$CALLS"
if [ -e "$STATE/fail-smoke" ]; then echo "LAUNCH SMOKE FAILED (exited with 134 within 10 s)"; exit 1; fi
echo "LAUNCH SMOKE OK (alive after 10 s)"
EOF
  # The real one: it is what puts the two programs into the app and signs everything.
  cp -p "$DIR/assemble-app.sh" "$tests/assemble-app.sh"
  chmod +x "$tests"/*
}

# A fresh sandbox: $T/root (the scripts, a small git repository as the source, stand-in tests), $T/home, an installed
# app from "before" with its helper inside (one bundle), its LaunchAgent pointing into it, aris-tools in Aris's folder a
# link into it, and that helper answering on its port (pid 1000). old_layout turns it into an install made the old way.
fresh() {
  N=$((N + 1)); T="$WORK/case-$N"
  mkdir -p "$T/root/Scripts" "$T/home/.config/aris/aris" "$T/home/Library/LaunchAgents" "$T/state" "$T/Applications"
  : > "$T/calls.log"
  for name in "${SCRIPTS[@]}"; do cp -p "$SHIP/$name" "$T/root/Scripts/$name"; done
  [ -f "$SHIP/promote.sh" ] && cp -p "$SHIP/promote.sh" "$T/root/Scripts/promote.sh"
  make_fakes "$T/bin"; make_fake_tests "$T/root/Tests"
  local src="$T/root"
  mkdir -p "$src/Aris.xcodeproj" "$src/Aris" "$src/ArisAgent" "$src/ArisXPCHelper" "$src/ArisSkills/skill-creator"
  echo "<plist/>" > "$src/ArisAgent/ArisAgent.entitlements"; echo "<plist/>" > "$src/ArisXPCHelper/ArisXPCHelper.entitlements"
  echo "MACOSX_DEPLOYMENT_TARGET = 14.0;" > "$src/Aris.xcodeproj/project.pbxproj"
  echo "<plist/>" > "$src/Aris/Aris.entitlements"
  echo "skillspector==1.0" > "$src/ArisSkills/runtime-requirements.txt"; echo "# skill" > "$src/ArisSkills/skill-creator/SKILL.md"
  (cd "$src" && git init -q -b fork . && git add -A && git -c user.name=test -c user.email=test@example.invalid commit -q -m "first") >/dev/null 2>&1
  COMMIT="$(git -C "$src" rev-parse --short=8 HEAD)"
  APP="$T/Applications/Aris.app"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  printf '#!/bin/sh\n' > "$APP/Contents/MacOS/Aris"; chmod +x "$APP/Contents/MacOS/Aris"
  echo "installed-before" > "$APP/Contents/Resources/marker"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>ArisCommit</key><string>before00</string></dict></plist>\n' > "$APP/Contents/Info.plist"
  ARIS="$T/home/.config/aris"
  PLIST="$T/home/Library/LaunchAgents/com.lumenjsn.aris.agent.plist"
  printf 'old agent aris-build-commit:before00\n' > "$APP/Contents/MacOS/aris-agent"; printf 'old tools aris-build-commit:before00\n' > "$APP/Contents/MacOS/aris-tools"
  chmod 755 "$APP/Contents/MacOS/aris-agent" "$APP/Contents/MacOS/aris-tools"
  ln -s "$APP/Contents/MacOS/aris-tools" "$ARIS/aris-tools"
  job_file "$APP/Contents/MacOS/aris-agent"
  echo before00 > "$ARIS/aris/agent-build"
  echo 1000 > "$T/state/listen-23351"; echo 3000 > "$T/state/listen-23350"
  OUT="$T/out.log"; ERR="$T/err.log"
}

# job_file <program>: the LaunchAgent file starting that program.
job_file() {
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>com.lumenjsn.aris.agent</string><key>ProgramArguments</key><array><string>%s</string></array></dict></plist>\n' "$1" > "$PLIST"
}
job_program() { /usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$PLIST" 2>/dev/null; }
# old_layout: the sandbox as install-aris-agent.sh used to leave it: an app with no helper inside, the helper's own
# copy and its tools in Aris's folder, and the LaunchAgent pointing there.
old_layout() {
  rm -f "$APP/Contents/MacOS/aris-agent" "$APP/Contents/MacOS/aris-tools" "$ARIS/aris-tools"
  printf 'old agent aris-build-commit:before00\n' > "$ARIS/aris-agent"; printf 'old tools aris-build-commit:before00\n' > "$ARIS/aris-tools"
  chmod 700 "$ARIS/aris-agent" "$ARIS/aris-tools"
  job_file "$ARIS/aris-agent"
}

# run_in <script> [arguments…]: the script from the sandbox, with nothing of the real environment but a PATH that has
# the fakes first. Extra variables come from $EXTRA_ENV (an array). Sets RC.
EXTRA_ENV=()
run_in() {
  local script="$1"; shift
  env -i HOME="$T/home" PATH="$T/bin:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$T" STATE="$T/state" CALLS="$T/calls.log" \
    APP="$T/Applications/Aris.app" OLD_APP="$T/Applications/Boring Notch.app" AGY_BINARIES="$T/home/.local/bin/agy" \
    ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} "$T/root/Scripts/$script" "$@" > "$OUT" 2> "$ERR"
  RC=$?
  EXTRA_ENV=()
}
run_py() {
  local script="$1"; shift
  env -i HOME="$T/home" PATH="$T/bin:/usr/bin:/bin" /usr/bin/python3 -I "$T/root/Scripts/$script" "$@" > "$OUT" 2> "$ERR"
  RC=$?
}
marker() { cat "$APP/Contents/Resources/marker" 2>/dev/null; }
untouched() { [ "$(marker)" = "installed-before" ] && has "$APP/Contents/MacOS/aris-agent" "old agent" && has "$APP/Contents/MacOS/aris-tools" "old tools" && [ "$(job_program)" = "$APP/Contents/MacOS/aris-agent" ] && [ -L "$ARIS/aris-tools" ]; }
calls_of() { grep -c -F -- "$1" "$T/calls.log" || true; }
never_quit() { lacks "$T/calls.log" "osascript" && lacks "$T/calls.log" "pkill" && lacks "$T/calls.log" "launchctl" && lacks "$T/calls.log" "open "; }
line_of() { grep -n -F -- "$1" "$T/calls.log" | head -1 | cut -d: -f1; }

# ---------------------------------------------------------------------------------------------------------------------
echo "# static checks"
for name in deploy.sh install-aris-agent.sh agent-hook.sh claude-statusline.sh promote.sh; do
  [ -f "$SHIP/$name" ] || continue
  check "$(yes bash -n "$SHIP/$name")" "static: $name passes bash -n"
done
for name in install-claude-hooks.py install-agent-hooks.py; do
  check "$(yes /usr/bin/python3 -I -X pycache_prefix="$WORK/pyc" -m py_compile "$SHIP/$name")" "static: $name compiles (python3 -I -m py_compile)"
done
if command -v shellcheck >/dev/null 2>&1; then
  for name in deploy.sh install-aris-agent.sh promote.sh; do
    [ -f "$SHIP/$name" ] && check "$(yes shellcheck -S error "$SHIP/$name")" "static: shellcheck finds no error in $name"
  done
else
  echo "skip static: shellcheck is not installed on this Mac"
fi
# The fakes only catch programs called by name: a path like /bin/launchctl would reach the real one.
check "$(no grep -nE '(^|[^[:alnum:]_.-])/(usr/)?s?bin/(launchctl|codesign|osascript|open|pkill|pgrep|security|lsof|xcodebuild|swiftc|sleep)([^[:alnum:]_-]|$)' "$SHIP/deploy.sh" "$SHIP/install-aris-agent.sh")" \
  "static: deploy.sh and install-aris-agent.sh call launchctl, codesign, osascript, open, pkill… by name only"

# ---------------------------------------------------------------------------------------------------------------------
echo "# deploy.sh: the whole path (one bundle)"
fresh; run_in deploy.sh
STAGED="$T/root/deploy-stage/Aris.app"; UID_NOW="$(id -u)"
check "$([ "$RC" = 0 ] && echo 0 || echo 1)" "deploy: everything works -> exit 0"
check "$(yes has "$OUT" "DEPLOYED $COMMIT")" "deploy: the last lines say which commit was deployed"
check "$([ "$(marker)" = "new-build" ] && echo 0 || echo 1)" "deploy: the installed app is the new build"
check "$(yes has "$APP/Contents/MacOS/aris-agent" "new agent aris-build-commit:$COMMIT")" "deploy: the helper inside the installed app is the new one, stamped with the commit"
check "$(yes has "$APP/Contents/MacOS/aris-tools" "new tools aris-build-commit:$COMMIT")" "deploy: the tools inside the installed app are the new ones"
check "$([ -f "$APP/Contents/Resources/skills/runtime-requirements.txt" ] && [ -f "$APP/Contents/Resources/skills/builtin/skill-creator/SKILL.md" ] && echo 0 || echo 1)" "deploy: the skills' files are inside the app"
check "$([ ! -e "$ARIS/aris-agent" ] && [ -L "$ARIS/aris-tools" ] && [ ! -e "$ARIS/skills" ] && echo 0 || echo 1)" "deploy: nothing is copied into Aris's folder (no helper of its own, aris-tools stays a link)"
check "$(has "$T/root/deploy-previous/Aris.previous/Contents/Resources/marker" "installed-before" && has "$T/root/deploy-previous/Aris.previous/Contents/MacOS/aris-agent" "old agent" && [ ! -e "$T/root/deploy-previous/agent" ] && echo 0 || echo 1)" \
  "deploy: the app that was installed is kept for a rollback, helper and all, as one bundle"
check "$(yes has "$T/calls.log" "xcodebuild -project Aris.xcodeproj -scheme Aris -configuration Release -derivedDataPath $T/root/build-release CODE_SIGNING_ALLOWED=NO ARIS_COMMIT=$COMMIT build")" \
  "deploy: xcodebuild is given the commit to stamp into the app"
check "$([ "$(line_of "codesign --verify --deep --strict $STAGED")" -lt "$(line_of "osascript")" ] && echo 0 || echo 1)" \
  "deploy: the running app is quit only after the new one is signed and verified in staging"
check "$([ "$(line_of "build-agent OUT=")" -lt "$(line_of "osascript")" ] && [ "$(line_of "launch-smoke")" -lt "$(line_of "osascript")" ] && echo 0 || echo 1)" \
  "deploy: the agent build and the launch check also come before the quit"
check "$(yes has "$T/calls.log" "codesign --force --sign Apple Development --options runtime --identifier com.lumenjsn.aris.aris-agent --entitlements $T/root/ArisAgent/ArisAgent.entitlements $STAGED/Contents/MacOS/aris-agent")" \
  "deploy: aris-agent is signed inside the app with its own identifier, the hardened runtime and its entitlements"
check "$(yes has "$T/calls.log" "codesign --force --sign Apple Development --options runtime --identifier com.lumenjsn.aris.aris-tools --entitlements $T/root/ArisAgent/ArisAgent.entitlements $STAGED/Contents/MacOS/aris-tools")" \
  "deploy: aris-tools likewise"
check "$(yes has "$T/calls.log" "codesign --force --sign Apple Development --options runtime --entitlements $T/root/Aris/Aris.entitlements $STAGED")" \
  "deploy: the app is signed in staging with its entitlements and, signed with a certificate, the hardened runtime (the default)"
check "$([ "$(line_of "Contents/MacOS/aris-agent")" -lt "$(line_of "ArisXPCHelper.xpc")" ] && [ "$(line_of "ArisXPCHelper.xpc")" -lt "$(line_of "Aris/Aris.entitlements")" ] && echo 0 || echo 1)" \
  "deploy: the two programs, then the XPC helper, then the app around them (inside-out)"
check "$([ "$(calls_of "launchctl kickstart -k gui/$UID_NOW/com.lumenjsn.aris.agent")" = 1 ] && [ "$(line_of "launchctl kickstart")" -gt "$(line_of "osascript")" ] && echo 0 || echo 1)" \
  "deploy: the helper is restarted exactly once, after the swap"
check "$(lacks "$T/calls.log" "launchctl bootout" && lacks "$T/calls.log" "launchctl bootstrap" && lacks "$T/calls.log" "app installs its helper" && echo 0 || echo 1)" \
  "deploy: the job is not unloaded, loaded or rewritten: it already points into the app"
check "$(yes has "$T/calls.log" "pkill -9 -f $APP/Contents/MacOS/Aris( |\$)")" "deploy: only the app's own program is quit, never the helper that runs from the same folder"
check "$(has "$T/calls.log" "pgrep -f ^$APP/Contents/MacOS/Aris( |\$)" && has "$T/calls.log" "runningApplicationWithProcessIdentifier(3000)" && lacks "$T/calls.log" "com.lumenjsn.aris\" to quit" && echo 0 || echo 1)" \
  "deploy: the app is quit by its own pid (the process whose program is Aris.app/Contents/MacOS/Aris), never by the bundle id the helper can be listed under (vm4 1)"
check "$([ "$(calls_of "sleep 1")" = 0 ] && echo 0 || echo 1)" "deploy: an app that quits cleanly is not waited for"
check "$([ "$(cat "$ARIS/aris/agent-build")" = "$COMMIT" ] && echo 0 || echo 1)" "deploy: the helper that answers afterwards is the new build"
check "$(yes has "$T/calls.log" "open $APP")" "deploy: the new app is opened"
check "$(yes has "$OUT" "the agent is idle")" "deploy: an idle agent is restarted without waiting"
check "$(yes has "$OUT" "deploy.sh --rollback")" "deploy: the last line says how to go back"
check "$([ ! -e "$T/Applications/.Aris.incoming" ] && [ ! -e "$T/Applications/.Aris.outgoing" ] && echo 0 || echo 1)" "deploy: nothing half-moved is left beside the app"

fresh; touch "$T/state/app-ignores-quit"; run_in deploy.sh
check "$([ "$RC" = 0 ] && [ "$(calls_of "sleep 1")" = 6 ] && [ "$(line_of "pkill -9 -f $APP/Contents/MacOS/Aris( |\$)")" -gt "$(grep -n -F "sleep 1" "$T/calls.log" | tail -1 | cut -d: -f1)" ] && [ "$(line_of "runningApplicationWithProcessIdentifier(3000)")" -lt "$(line_of "sleep 1")" ] && echo 0 || echo 1)" \
  "deploy: an app that does not go after the clean quit by its pid is waited for 6 s, then killed (vm4 1)"
: > "$T/calls.log"; rm -f "$T/state/app-ignores-quit"; run_in deploy.sh
check "$([ "$RC" = 0 ] && has "$T/calls.log" "runningApplicationWithProcessIdentifier(3000)" && echo 0 || echo 1)" "deploy: the app opened by the last deploy is quit by its pid as well"
# The rollback below starts from one deploy over the build from before, as the whole path left it.
fresh; run_in deploy.sh

echo "# deploy.sh --rollback"
: > "$T/calls.log"
run_in deploy.sh --rollback
check "$([ "$RC" = 0 ] && yes has "$OUT" "ROLLED BACK")" "rollback: one command, exit 0, and it says so"
check "$(lacks "$OUT" "is still in" && has "$OUT" "deploy again to install it" && [ ! -e "$T/root/deploy-stage/Aris.app" ] && echo 0 || echo 1)" "rollback: it does not claim the newer build is kept in staging (it is not), and says to deploy again"
check "$([ "$(marker)" = "installed-before" ] && has "$APP/Contents/MacOS/aris-agent" "old agent" && echo 0 || echo 1)" "rollback: the one bundle from before is installed again, its helper inside"
check "$([ "$(calls_of "launchctl kickstart")" = 1 ] && [ "$(cat "$ARIS/aris/agent-build")" = "before00" ] && echo 0 || echo 1)" "rollback: the helper was restarted once and is the build from before"
fresh; run_in deploy.sh --rollback
check "$([ "$RC" != 0 ] && yes has "$ERR" "nothing is kept")" "rollback: with no earlier deploy it refuses and says nothing is kept"
check "$(yes untouched)" "rollback: and leaves the installed build alone"

fresh; run_in deploy.sh; : > "$T/calls.log"; BEFORE_CLEAN="$(marker)"; run_in deploy.sh --clean
check "$([ "$RC" = 0 ] && has "$OUT" "CLEANED" && [ ! -e "$T/root/deploy-previous/Aris.previous" ] && [ ! -e "$T/root/deploy-stage/Aris.app" ] && [ ! -e "$T/root/deploy-stage/agent" ] && [ ! -e "$T/root/build-release/Build/Products/Release/Aris.app" ] && echo 0 || echo 1)" \
  "clean: every signed copy the script keeps (staging, build product, the build kept for a rollback) is removed (sec4, U1)"
check "$([ "$(marker)" = "$BEFORE_CLEAN" ] && [ ! -s "$T/calls.log" ] && has "$APP/Contents/MacOS/aris-agent" "new agent" && echo 0 || echo 1)" "clean: the installed Aris is not touched, and nothing is quit or restarted"
run_in deploy.sh --rollback
check "$([ "$RC" != 0 ] && has "$ERR" "nothing is kept" && echo 0 || echo 1)" "clean: afterwards a rollback says plainly that nothing is kept"

echo "# deploy.sh over an install made the old way (the helper's own copy in Aris's folder)"
fresh; old_layout; run_in deploy.sh
check "$([ "$RC" = 0 ] && has "$OUT" "DEPLOYED $COMMIT" && echo 0 || echo 1)" "switch: the first one-bundle deploy over the old layout works"
check "$(has "$OUT" "Aris sets its helper up itself" && [ "$(calls_of "launchctl kickstart")" = 0 ] && has "$T/calls.log" "app installs its helper from $APP" && echo 0 || echo 1)" \
  "switch: the old job is not kickstarted; the app switches its helper over when it opens"
check "$([ ! -e "$ARIS/aris-agent" ] && [ -L "$ARIS/aris-tools" ] && [ "$(job_program)" = "$APP/Contents/MacOS/aris-agent" ] && echo 0 || echo 1)" "switch: afterwards the job points into the app and the old copies are gone"
check "$([ -f "$T/root/deploy-previous/old-layout.tgz" ] && [ ! -e "$T/root/deploy-previous/old-layout" ] && tar tzf "$T/root/deploy-previous/old-layout.tgz" | grep -q "aris-agent" && tar tzf "$T/root/deploy-previous/old-layout.tgz" | grep -q "agent.plist" && echo 0 || echo 1)" \
  "switch: the helper of the old layout was kept first for a rollback across the switch, as an archive and not as a program that could be started (sec4 M4)"
check "$([ ! -e "$T/root/deploy-stage/Aris.app" ] && echo 0 || echo 1)" "switch: no complete signed Aris.app is left in the staging folder after the swap (sec4 L2)"
run_in deploy.sh --rollback
check "$([ "$RC" = 0 ] && [ "$(marker)" = "installed-before" ] && has "$ARIS/aris-agent" "old agent" && [ -f "$ARIS/aris-tools" ] && [ ! -L "$ARIS/aris-tools" ] && [ "$(job_program)" = "$ARIS/aris-agent" ] && echo 0 || echo 1)" \
  "switch: a rollback across it puts the old app, the old helper, its tools and its job back"
check "$([ "$(cat "$ARIS/aris/agent-build")" = "before00" ] && [ -e "$T/state/listen-23351" ] && echo 0 || echo 1)" "switch: and that helper answers again"

fresh; old_layout; run_in deploy.sh; run_in deploy.sh
check "$([ "$RC" = 0 ] && [ ! -e "$T/root/deploy-previous/old-layout.tgz" ] && [ ! -e "$T/root/deploy-previous/old-layout" ] && echo 0 || echo 1)" \
  "switch: once the one-bundle layout has run, the next deploy removes the old helper's archive (sec4 M4)"

echo "# the hardened runtime on the app itself (Tests/assemble-app.sh)"
fresh; EXTRA_ENV=(HARDEN_APP=0); run_in deploy.sh
check "$([ "$RC" = 0 ] && has "$T/calls.log" "codesign --force --sign Apple Development --entitlements $T/root/Aris/Aris.entitlements $T/root/deploy-stage/Aris.app" && lacks "$T/calls.log" "--options runtime --entitlements $T/root/Aris/Aris.entitlements" && echo 0 || echo 1)" \
  "harden: HARDEN_APP=0 signs the app as before (no hardened runtime on the app; the helper and tools keep theirs)"
fresh; echo "     0 valid identities found" > "$T/state/identities"; run_in deploy.sh
check "$([ "$RC" = 0 ] && lacks "$T/calls.log" "--options runtime --entitlements $T/root/Aris/Aris.entitlements" && has "$OUT" "app not hardened" && echo 0 || echo 1)" \
  "harden: an ad-hoc signature never hardens the app (it could not load its own framework and would not start)"
fresh; echo "     0 valid identities found" > "$T/state/identities"; EXTRA_ENV=(HARDEN_APP=1); run_in deploy.sh
check "$([ "$RC" != 0 ] && has "$ERR" "DEPLOY FAILED at step: 5/6" && has "$ERR" "HARDEN_APP=1 cannot be used with an ad-hoc signature" && untouched && never_quit && lacks "$T/calls.log" "codesign --force" && echo 0 || echo 1)" \
  "harden: HARDEN_APP=1 with an ad-hoc signature is refused with the reason before anything is signed, nothing changed"
fresh; EXTRA_ENV=(HARDEN_APP=yes); run_in deploy.sh
check "$([ "$RC" != 0 ] && has "$ERR" "use 1 (hardened runtime on the app) or 0" && untouched && never_quit && echo 0 || echo 1)" "harden: a value other than 0 or 1 is refused"

echo "# deploy.sh --bundle <Aris.app>: a bundle that is already built and signed (a Mac without Xcode; the rehearsal)"
# make_bundle [stamp]: an assembled, "signed" Aris.app outside the sandbox's script folder, as stage-onerow.sh leaves one.
make_bundle() {
  local stamp="${1:-bund1e00}"
  BUNDLE="$T/prebuilt/Aris.app"
  mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/skills"
  printf '#!/bin/sh\nsleep 30\n' > "$BUNDLE/Contents/MacOS/Aris"
  printf 'bundle agent aris-build-commit:%s\n' "$stamp" > "$BUNDLE/Contents/MacOS/aris-agent"
  printf 'bundle tools aris-build-commit:%s\n' "$stamp" > "$BUNDLE/Contents/MacOS/aris-tools"
  chmod 755 "$BUNDLE/Contents/MacOS/"*
  echo "bundle-build" > "$BUNDLE/Contents/Resources/marker"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleExecutable</key><string>Aris</string><key>ArisCommit</key><string>%s</string></dict></plist>\n' "$stamp" > "$BUNDLE/Contents/Info.plist"
}
fresh; make_bundle; run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" = 0 ] && has "$OUT" "DEPLOYED bund1e00" && [ "$(marker)" = "bundle-build" ] && has "$APP/Contents/MacOS/aris-agent" "bundle agent aris-build-commit:bund1e00" && echo 0 || echo 1)" \
  "bundle: the bundle is installed, and the last lines name its stamp"
check "$(lacks "$T/calls.log" "xcodebuild" && lacks "$T/calls.log" "build-agent" && lacks "$T/calls.log" "launch-smoke" && lacks "$T/calls.log" "codesign --force" && lacks "$T/calls.log" "security " && lacks "$T/calls.log" "swiftc" && echo 0 || echo 1)" \
  "bundle: nothing is built, signed or looked up in the keychain"
check "$([ "$(line_of "codesign --verify --deep --strict $BUNDLE")" -lt "$(line_of "osascript")" ] && [ "$(line_of "codesign --verify --deep --strict $T/Applications/.Aris.incoming")" -lt "$(line_of "osascript")" ] && echo 0 || echo 1)" \
  "bundle: its signature is verified, and the copy beside the app again, before Aris is quit"
check "$(has "$T/root/deploy-previous/Aris.previous/Contents/Resources/marker" "installed-before" && [ "$(cat "$T/root/deploy-previous/app-commit")" = "before00" ] && echo 0 || echo 1)" "bundle: the app that was installed is kept for a rollback"
check "$([ "$(calls_of "launchctl kickstart -k gui/$UID_NOW/com.lumenjsn.aris.agent")" = 1 ] && [ "$(line_of "launchctl kickstart")" -gt "$(line_of "osascript")" ] && lacks "$T/calls.log" "launchctl bootout" && lacks "$T/calls.log" "launchctl bootstrap" && echo 0 || echo 1)" \
  "bundle: the helper is restarted exactly once, after the swap; the job is not unloaded or rewritten"
check "$([ "$(cat "$ARIS/aris/agent-build")" = "bund1e00" ] && has "$T/calls.log" "open $APP" && has "$OUT" "the agent is idle" && echo 0 || echo 1)" "bundle: the health check is the same: the app is opened and the helper that answers is the bundle's build"
check "$([ ! -e "$T/root/deploy-stage/Aris.app" ] && [ -x "$BUNDLE/Contents/MacOS/aris-agent" ] && [ ! -e "$T/Applications/.Aris.incoming" ] && [ ! -e "$T/Applications/.Aris.outgoing" ] && echo 0 || echo 1)" \
  "bundle: no signed copy is left in staging or beside the app, and the bundle handed in is not touched"
: > "$T/calls.log"; run_in deploy.sh --rollback
check "$([ "$RC" = 0 ] && [ "$(marker)" = "installed-before" ] && [ "$(cat "$ARIS/aris/agent-build")" = "before00" ] && [ "$(calls_of "launchctl kickstart")" = 1 ] && echo 0 || echo 1)" "bundle: --rollback afterwards puts the previous build back with one restart"
fresh; make_bundle; rm -rf "$T/root/.git" "$T/root/Aris.xcodeproj" "$T/root/Aris" "$T/root/ArisAgent" "$T/root/ArisXPCHelper" "$T/root/ArisSkills" "$T/root/Tests"; run_in deploy.sh "--bundle=$BUNDLE"
check "$([ "$RC" = 0 ] && [ "$(marker)" = "bundle-build" ] && echo 0 || echo 1)" "bundle: works with neither the source nor the tests folder beside the script (--bundle=<path> form)"
fresh; make_bundle; echo "2 3" > "$T/state/busy"; run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" = 0 ] && has "$OUT" "the agent is busy (2 request(s) being answered): waiting up to 120s" && [ "$(line_of "osascript")" -gt "$(grep -n "ESTABLISHED" "$T/calls.log" | tail -1 | cut -d: -f1)" ] && echo 0 || echo 1)" "bundle: a busy agent is waited for before the app is quit, as in a built deploy"
fresh; make_bundle; echo "1 100000" > "$T/state/busy"; run_in deploy.sh --bundle "$BUNDLE" --now
check "$([ "$RC" = 0 ] && has "$ERR" "--now was given: restarting it anyway" && echo 0 || echo 1)" "bundle: --now applies to it too"
fresh; make_bundle; echo 1 > "$T/state/agent-never-up"; run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" != 0 ] && has "$ERR" "DEPLOY FAILED at step: 6/6" && has "$ERR" "The previous build is back and running" && untouched && echo 0 || echo 1)" "bundle: a helper that does not come back puts the previous build back, as in a built deploy"
fresh; make_bundle; echo 1 > "$T/state/helper-wrong-build"; run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" != 0 ] && has "$ERR" "the helper that answers is build wr0ng000, not bund1e00" && untouched && echo 0 || echo 1)" "bundle: a helper of another build answering after the swap is a failure"
fresh; old_layout; make_bundle; run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" = 0 ] && [ ! -e "$ARIS/aris-agent" ] && [ -L "$ARIS/aris-tools" ] && [ "$(job_program)" = "$APP/Contents/MacOS/aris-agent" ] && [ -f "$T/root/deploy-previous/old-layout.tgz" ] && [ "$(calls_of "launchctl kickstart")" = 0 ] && echo 0 || echo 1)" \
  "bundle: over an install made the old way the app does the switch, and the old helper is kept as an archive first"
fresh; run_in deploy.sh --bundle
check "$([ "$RC" = 2 ] && has "$ERR" "--bundle needs the path" && untouched && never_quit && echo 0 || echo 1)" "bundle: without a path it stops with the usage, exit 2"
fresh; make_bundle; run_in deploy.sh --bundle "$BUNDLE" --rollback
check "$([ "$RC" = 2 ] && has "$ERR" "cannot be combined" && untouched && never_quit && echo 0 || echo 1)" "bundle: together with --rollback it is refused"
fresh; run_in deploy.sh --bundle "$T/nowhere/Aris.app"
check "$([ "$RC" != 0 ] && has "$ERR" "DEPLOY FAILED at step: 1/6" && has "$ERR" "there is no bundle at" && has "$ERR" "Nothing installed was changed" && untouched && never_quit && echo 0 || echo 1)" "bundle: a path with nothing at it is refused at step 1, nothing changed"
fresh; make_bundle; rm "$BUNDLE/Contents/MacOS/aris-agent"; run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" != 0 ] && has "$ERR" "is not an assembled Aris.app" && untouched && never_quit && echo 0 || echo 1)" "bundle: an app without the helper inside (a bare build product) is refused"
fresh; make_bundle; printf 'bundle agent aris-build-commit:0ther000\n' > "$BUNDLE/Contents/MacOS/aris-agent"; run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" != 0 ] && has "$ERR" "is not one build: its app is stamped bund1e00, the helper inside it 0ther000" && untouched && never_quit && echo 0 || echo 1)" "bundle: an app and a helper of different builds are refused"
fresh; make_bundle; run_in deploy.sh --bundle "$APP"
check "$([ "$RC" != 0 ] && has "$ERR" "the bundle is the installed app itself" && untouched && never_quit && echo 0 || echo 1)" "bundle: the installed app itself is refused as the bundle"
fresh; make_bundle; echo "prebuilt/Aris.app" > "$T/state/fail-verify"; run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" != 0 ] && has "$ERR" "DEPLOY FAILED at step: 5/6" && has "$ERR" "the bundle's signature does not verify" && untouched && never_quit && echo 0 || echo 1)" "bundle: a signature that does not verify stops it at step 5, nothing changed"
fresh; make_bundle; touch "$T/state/bundle-no-runtime"; run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" != 0 ] && has "$ERR" "is not signed with the hardened runtime" && untouched && never_quit && echo 0 || echo 1)" "bundle: a helper without the hardened runtime is refused"
fresh; make_bundle; touch "$T/state/bundle-other-id"; run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" != 0 ] && has "$ERR" "does not carry its signing identifier" && untouched && never_quit && echo 0 || echo 1)" "bundle: a helper signed under another identifier is refused"
fresh; make_bundle; echo "OTHERTEAM1" > "$T/state/bundle-team"; run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" != 0 ] && has "$ERR" "is not signed by the team of the installed Aris (bundle: OTHERTEAM1, installed: TEAM123456)" && has "$ERR" "ALLOW_OTHER_SIGNER=1" && untouched && never_quit && echo 0 || echo 1)" \
  "bundle: a bundle signed by another team than the installed Aris is refused (permissions would be forgotten)"
fresh; make_bundle; echo "not set" > "$T/state/bundle-team"; run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" != 0 ] && has "$ERR" "(bundle: no team, installed: TEAM123456)" && untouched && never_quit && echo 0 || echo 1)" "bundle: an ad-hoc bundle over a certificate-signed install is refused likewise"
fresh; make_bundle; echo "OTHERTEAM1" > "$T/state/bundle-team"; EXTRA_ENV=(ALLOW_OTHER_SIGNER=1); run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" = 0 ] && has "$ERR" "its permissions and saved keys have to be given again" && [ "$(marker)" = "bundle-build" ] && echo 0 || echo 1)" "bundle: ALLOW_OTHER_SIGNER=1 accepts the other signer, with the warning"
fresh; make_bundle; echo "not set" > "$T/state/installed-team"; echo "not set" > "$T/state/bundle-team"; run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" = 0 ] && [ "$(marker)" = "bundle-build" ] && echo 0 || echo 1)" "bundle: over an ad-hoc install any bundle goes in (there is nothing to keep)"
fresh; make_bundle; rm -rf "$APP" "$ARIS/aris-tools" "$PLIST" "$ARIS/aris/agent-build" "$T/state/listen-23351" "$T/state/listen-23350"; run_in deploy.sh --bundle "$BUNDLE"
check "$([ "$RC" = 0 ] && [ "$(marker)" = "bundle-build" ] && has "$OUT" "nothing to keep for a rollback" && [ "$(job_program)" = "$APP/Contents/MacOS/aris-agent" ] && echo 0 || echo 1)" "bundle: a first install (no app yet) works; the app sets its own helper up"

echo "# deploy.sh: failures before the swap leave the installed Aris alone"
fresh; touch "$T/state/fail-xcodebuild"; run_in deploy.sh
check "$([ "$RC" != 0 ] && echo 0 || echo 1)" "build fails: exit is not 0"
check "$(has "$ERR" "DEPLOY FAILED at step: 2/6" && has "$ERR" "the app did not build" && echo 0 || echo 1)" "build fails: the message names the step and the reason"
check "$(yes has "$ERR" "error: cannot find 'nope' in scope")" "build fails: the compiler's error line is shown"
check "$(yes has "$ERR" "Nothing installed was changed")" "build fails: it says nothing installed was changed"
check "$(yes untouched)" "build fails: the installed app and the helper inside it are the ones from before"
check "$(yes never_quit)" "build fails: the running app was never quit and launchd never touched"

fresh; touch "$T/state/fail-agent-build"; run_in deploy.sh
check "$([ "$RC" != 0 ] && has "$ERR" "DEPLOY FAILED at step: 3/6" && has "$ERR" "did not build" && echo 0 || echo 1)" "agent build fails: exit is not 0 and the message names the step (deploy-1)"
check "$(yes has "$ERR" "error: cannot find 'ArisNope' in scope")" "agent build fails: the compiler's error line is shown"
check "$(untouched && never_quit && echo 0 || echo 1)" "agent build fails: nothing installed changed, nothing was quit"

fresh; touch "$T/state/stale-agent"; run_in deploy.sh
check "$([ "$RC" != 0 ] && has "$ERR" "is stamped 0ld0ld00 but the source is at $COMMIT" && untouched && echo 0 || echo 1)" "agent stamped with another commit: refused before the swap"
fresh; touch "$T/state/unstamped-agent" "$T/state/unstamped-app"; run_in deploy.sh
check "$([ "$RC" = 0 ] && has "$ERR" "aris-agent carries no commit stamp" && has "$ERR" "the app carries no commit stamp" && has "$ERR" "cannot be checked that the helper answering is the new one" && echo 0 || echo 1)" \
  "a source without the stamp code still deploys, with a warning for app and agent and for the check it cannot make"

fresh; echo "deploy-stage/Aris.app" > "$T/state/fail-sign"; run_in deploy.sh
check "$([ "$RC" != 0 ] && echo 0 || echo 1)" "signing fails: exit is not 0 (deploy-3)"
check "$(has "$ERR" "DEPLOY FAILED at step: 5/6" && has "$ERR" "codesign could not sign" && has "$ERR" "errSecInternalComponent" && echo 0 || echo 1)" "signing fails: the step, the reason and codesign's own error are shown"
check "$(untouched && never_quit && echo 0 || echo 1)" "signing fails: the installed app is not replaced by an unsigned one and Aris keeps running"

fresh; echo "ArisXPCHelper.xpc" > "$T/state/fail-sign"; run_in deploy.sh
check "$([ "$RC" != 0 ] && has "$ERR" "DEPLOY FAILED at step: 5/6" && has "$ERR" "ArisXPCHelper.xpc" && untouched && never_quit && echo 0 || echo 1)" "a piece inside the app that cannot be signed stops the deploy at step 5, nothing changed"

fresh; echo "deploy-stage/Aris.app" > "$T/state/fail-verify"; run_in deploy.sh
check "$([ "$RC" != 0 ] && has "$ERR" "the signed app does not verify" && untouched && never_quit && echo 0 || echo 1)" "a signature that does not verify stops the deploy before the swap"

fresh; touch "$T/state/fail-smoke"; run_in deploy.sh
check "$([ "$RC" != 0 ] && has "$ERR" "DEPLOY FAILED at step: 4/6" && has "$ERR" "SKIP_SMOKE=1" && untouched && never_quit && echo 0 || echo 1)" "launch check fails: step 4, nothing changed, and the way to skip it is named"
fresh; touch "$T/state/fail-smoke"; EXTRA_ENV=(SKIP_SMOKE=1); run_in deploy.sh
check "$([ "$RC" = 0 ] && lacks "$T/calls.log" "launch-smoke" && echo 0 || echo 1)" "SKIP_SMOKE=1 leaves the launch check out"

fresh; echo ".Aris.incoming" > "$T/state/fail-verify"; run_in deploy.sh
check "$([ "$RC" != 0 ] && has "$ERR" "could not be copied next to" && untouched && lacks "$T/calls.log" "osascript" && echo 0 || echo 1)" "a copy next to the app that does not verify stops before the app is quit"

echo "# deploy.sh: failures during the swap put the previous build back"
fresh; echo 1 > "$T/state/agent-never-up"; run_in deploy.sh
check "$([ "$RC" != 0 ] && echo 0 || echo 1)" "helper does not come back: exit is not 0 (deploy-1)"
check "$(has "$ERR" "DEPLOY FAILED at step: 6/6" && has "$ERR" "did not open port 23351" && has "$ERR" "NOT kickstarted a second time" && echo 0 || echo 1)" "helper does not come back: the message names the step and the reason, and no second kickstart was sent for it"
check "$(has "$ERR" "the previous build is being put back" && has "$ERR" "The previous build is back and running" && echo 0 || echo 1)" "helper does not come back: it says the previous build was put back"
check "$(yes untouched)" "helper does not come back: the installed app and its helper are the ones from before again"
check "$([ -e "$T/state/listen-23351" ] && [ -e "$T/state/listen-23350" ] && [ "$(cat "$ARIS/aris/agent-build")" = "before00" ] && echo 0 || echo 1)" "helper does not come back: the previous helper and app are running again"
check "$(yes lacks "$OUT" "DEPLOYED")" "helper does not come back: it never says deployed"

fresh; echo 1 > "$T/state/helper-wrong-build"; run_in deploy.sh
check "$([ "$RC" != 0 ] && has "$ERR" "the helper that answers is build wr0ng000, not $COMMIT" && has "$ERR" "The previous build is back and running" && untouched && echo 0 || echo 1)" \
  "a helper of another build answering after the swap is a failure: the previous build is put back"

fresh; echo 1 > "$T/state/app-never-up"; run_in deploy.sh
check "$([ "$RC" != 0 ] && has "$ERR" "hook server (port 23350) did not come up" && has "$ERR" "The previous build is back and running" && untouched && echo 0 || echo 1)" "the new app's hook server does not come up: the previous build is put back"

fresh; touch "$T/state/fail-open"; run_in deploy.sh
check "$([ "$RC" != 0 ] && has "$ERR" "macOS would not open" && has "$ERR" "COULD NOT put the previous build back" && echo 0 || echo 1)" "the app cannot be opened at all: failure is reported, with the command to run by hand"

fresh; rm -rf "$APP" "$ARIS/aris-tools" "$PLIST" "$ARIS/aris/agent-build" "$T/state/listen-23351" "$T/state/listen-23350"; run_in deploy.sh
check "$([ "$RC" = 0 ] && [ "$(marker)" = "new-build" ] && has "$OUT" "nothing to keep for a rollback" && echo 0 || echo 1)" "a first install (no app, no helper, no job yet) deploys and says there is nothing to keep"
check "$(has "$T/calls.log" "app installs its helper from $APP" && [ "$(job_program)" = "$APP/Contents/MacOS/aris-agent" ] && [ -L "$ARIS/aris-tools" ] && [ "$(calls_of "launchctl kickstart")" = 0 ] && echo 0 || echo 1)" \
  "a first install: no script writes the job; the app sets its own helper up when it opens"

echo "# signing identity (sign-1, deploy-3)"
fresh; echo "     0 valid identities found" > "$T/state/identities"; run_in deploy.sh
check "$([ "$RC" = 0 ] && has "$ERR" "SIGNING AD-HOC" && has "$ERR" "granted again" && echo 0 || echo 1)" "no identity, ad-hoc install: the fallback to ad-hoc is announced loudly"
check "$(has "$T/calls.log" "codesign --force --sign - --options runtime --identifier com.lumenjsn.aris.aris-agent" && has "$T/calls.log" "codesign --force --sign - --entitlements" && echo 0 || echo 1)" "no identity: the app and the helper inside it are both signed ad-hoc (one rule)"
check "$([ "$(grep -c "SIGNING AD-HOC" "$ERR")" = 1 ] && echo 0 || echo 1)" "no identity: the warning is printed once, not once per program"
fresh; echo "     0 valid identities found" > "$T/state/identities"; touch "$T/state/installed-cert-signed"; run_in deploy.sh
check "$([ "$RC" != 0 ] && has "$ERR" "is signed with a certificate" && has "$ERR" "SIGN_ID=-" && echo 0 || echo 1)" "no identity, certificate-signed install: refused, with the reason and how to accept ad-hoc"
check "$(untouched && never_quit && echo 0 || echo 1)" "no identity, certificate-signed install: nothing was changed"
fresh; echo "     0 valid identities found" > "$T/state/identities"; touch "$T/state/installed-cert-signed"; EXTRA_ENV=(SIGN_ID=-); run_in deploy.sh
check "$([ "$RC" = 0 ] && has "$ERR" "SIGNING AD-HOC: SIGN_ID=- was asked for" && echo 0 || echo 1)" "SIGN_ID=- signs ad-hoc when asked, still with the warning"
fresh; printf '  1) %040d "Apple Development: A (T1)"\n  2) %040d "Apple Development: A (T2)"\n     2 valid identities found\n' 1 2 > "$T/state/identities"; run_in deploy.sh
check "$([ "$RC" != 0 ] && has "$ERR" "2 identities match" && untouched && never_quit && echo 0 || echo 1)" "two matching identities: refused before anything is built, both are listed"
fresh; EXTRA_ENV=("SIGN_ID=Developer ID Application: Nobody"); run_in deploy.sh
check "$([ "$RC" != 0 ] && has "$ERR" "no code-signing identity named" && untouched && echo 0 || echo 1)" "an identity that was asked for by name and is missing is never swapped for another"
fresh; run_in install-aris-agent.sh --resolve-identity
check "$([ "$RC" = 0 ] && [ "$(cat "$OUT")" = "Apple Development" ] && echo 0 || echo 1)" "--resolve-identity prints the identity when the keychain has exactly one"

echo "# waiting for the agent to be idle (imp-5)"
fresh; echo "2 3" > "$T/state/busy"; run_in deploy.sh
check "$([ "$RC" = 0 ] && has "$OUT" "the agent is busy (2 request(s) being answered): waiting up to 120s" && has "$OUT" "the agent is idle (after" && echo 0 || echo 1)" "a busy agent is waited for, and the deploy goes on when it is idle"
check "$([ "$(line_of "osascript")" -gt "$(grep -n "ESTABLISHED" "$T/calls.log" | tail -1 | cut -d: -f1)" ] && echo 0 || echo 1)" "the app is quit only after the agent was seen idle"
fresh; echo "1 100000" > "$T/state/busy"; EXTRA_ENV=(IDLE_WAIT=6); run_in deploy.sh
check "$([ "$RC" = 0 ] && has "$ERR" "still busy after 6s (1 request(s) being answered): restarting it anyway; that work is cut off" && echo 0 || echo 1)" "an agent that stays busy is restarted after the bounded wait, and the output says what was cut off"
fresh; echo "1 100000" > "$T/state/busy"; run_in deploy.sh --now
check "$([ "$RC" = 0 ] && has "$ERR" "--now was given: restarting it anyway" && lacks "$OUT" "waiting up to" && echo 0 || echo 1)" "--now restarts a busy agent at once and says the work is cut off"
fresh; printf '[{"id":"A","runningSince":"2026-11-10T01:00:00Z","parked":["q1"]},{"id":"B","parked":[]}]' > "$ARIS/aris/schedules.json"; echo 0 > "$T/state/unused"
EXTRA_ENV=(IDLE_WAIT=2); run_in install-aris-agent.sh --wait-idle
check "$(has "$OUT" "1 scheduled job(s) running, 1 waiting for an answer from you" && echo 0 || echo 1)" "a scheduled job that is running counts as busy, and a question waiting for the user is named"
fresh; echo 2 > "$T/state/tools-running"; run_in install-aris-agent.sh --agent-status
check "$([ "$(cat "$OUT")" = "busy: 2 aris-tools command(s) still running" ] && echo 0 || echo 1)" "aris-tools still at work counts as busy, also one that detached itself from the helper"
check "$(has "$T/calls.log" "pgrep -x aris-tools" && lacks "$T/calls.log" "pgrep -f /aris-tools" && echo 0 || echo 1)" "aris-tools at work is looked for by program name, never in command lines (an AI program's arguments name aris-tools without being one)"
fresh; echo "not json" > "$ARIS/aris/schedules.json"; run_in install-aris-agent.sh --agent-status
check "$([ "$RC" = 0 ] && [ "$(cat "$OUT")" = "idle" ] && echo 0 || echo 1)" "--agent-status: a schedules file that cannot be read does not stop the deploy (idle)"
fresh; rm -f "$T/state/listen-23351"; run_in install-aris-agent.sh --agent-status
check "$([ "$(cat "$OUT")" = "not running" ] && echo 0 || echo 1)" "--agent-status: no agent answering -> not running"

echo "# install-aris-agent.sh on its own (what is left of it)"
fresh; run_in install-aris-agent.sh
check "$([ "$RC" = 0 ] && has "$OUT" "inside Aris.app" && untouched && [ ! -s "$T/calls.log" ] && echo 0 || echo 1)" "with no option it says where the helper lives now and does nothing"
fresh; run_in install-aris-agent.sh --stage "$T/staged"
check "$([ "$RC" = 0 ] && has "$T/staged/aris-agent" "new agent aris-build-commit:$COMMIT" && has "$T/staged/aris-tools" "new tools" && [ "$(cat "$T/staged/commit")" = "$COMMIT" ] && echo 0 || echo 1)" "--stage builds and checks both programs into the folder"
check "$(untouched && lacks "$T/calls.log" "launchctl" && lacks "$T/calls.log" "codesign" && echo 0 || echo 1)" "--stage installs nothing, restarts nothing and signs nothing (they are signed inside the app)"
fresh; touch "$T/state/fail-agent-build"; run_in install-aris-agent.sh --stage "$T/staged"
check "$([ "$RC" != 0 ] && has "$ERR" "aris-agent install FAILED" && untouched && lacks "$T/calls.log" "launchctl" && echo 0 || echo 1)" "--stage: a build failure leaves the running helper alone"
fresh; run_in install-aris-agent.sh --restart
check "$([ "$RC" = 0 ] && has "$OUT" "aris agent up (pid 2000)" && [ "$(calls_of "launchctl kickstart -k")" = 1 ] && lacks "$T/calls.log" "bootout" && lacks "$T/calls.log" "bootstrap" && echo 0 || echo 1)" "--restart: one kickstart of the job, and the new process answers"
fresh; echo 1 > "$T/state/agent-never-up"; run_in install-aris-agent.sh --restart
check "$([ "$RC" != 0 ] && has "$ERR" "did not open port 23351" && has "$ERR" "agent.log" && [ "$(calls_of "launchctl kickstart -k")" = 1 ] && echo 0 || echo 1)" "--restart: a helper that does not come back is a failure that names its log, and it is not kicked a second time"
fresh; printf '#!/bin/bash\necho "launchctl $*" >> "$CALLS"\nexit 0\n' > "$T/bin/launchctl"; run_in install-aris-agent.sh --restart
check "$([ "$RC" != 0 ] && has "$ERR" "did not open port 23351" && echo 0 || echo 1)" "--restart: an old process that survives the restart is never taken for the new one"
fresh; touch "$T/state/job-not-loaded"; run_in install-aris-agent.sh --restart
check "$([ "$RC" = 0 ] && has "$OUT" "Aris loads it itself when it is opened" && echo 0 || echo 1)" "--restart: a job launchd does not have is left to the app"
fresh; old_layout; run_in install-aris-agent.sh --restart
check "$([ "$RC" = 0 ] && has "$OUT" "Aris sets its helper up itself" && lacks "$T/calls.log" "launchctl" && has "$ARIS/aris-agent" "old agent" && echo 0 || echo 1)" "--restart: over an install made the old way nothing is restarted or removed; the app does the switch"
for gone in --install-staged --keep-previous --restore-previous; do
  fresh; run_in install-aris-agent.sh "$gone" "$T/staged"
  check "$([ "$RC" != 0 ] && has "$ERR" "$gone is gone" && has "$ERR" "one swap of the app" && untouched && echo 0 || echo 1)" "$gone is refused with the reason (one bundle)"
done

echo "# Antigravity's rules are the helper's own business now (ArisAgyRules, at each start of agy)"
AGY_REL=".gemini/antigravity-cli/settings.json"
fresh; mkdir -p "$T/home/.gemini/antigravity-cli"; echo '{"theme": broken' > "$T/home/$AGY_REL"; run_in deploy.sh
check "$([ "$RC" = 0 ] && has "$T/home/$AGY_REL" '{"theme": broken' && [ ! -e "$T/home/$AGY_REL.before-aris" ] && echo 0 || echo 1)" "agy: the deploy neither reads nor writes Antigravity's settings"
fresh; mkdir -p "$T/home/.local/bin"; printf '#!/bin/sh\n' > "$T/home/.local/bin/agy"; chmod +x "$T/home/.local/bin/agy"; run_in deploy.sh
check "$([ "$RC" = 0 ] && [ ! -e "$T/home/.gemini" ] && echo 0 || echo 1)" "agy: nothing of its is created by a deploy"

# ---------------------------------------------------------------------------------------------------------------------
echo "# hooks installers on a Mac without Codex, Gemini CLI or Claude Code (hooks-1, hooks-2, hooks-3)"
TOKEN="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
fresh; rm -f "$ARIS/claude-hook-token"; run_py install-agent-hooks.py --apply
check "$([ "$RC" != 0 ] && has "$ERR" "no hook token yet" && lacks "$ERR" "Traceback" && echo 0 || echo 1)" "agent hooks, no token: a plain message, no traceback"
fresh; echo "$TOKEN" > "$ARIS/claude-hook-token"; run_py install-agent-hooks.py --apply
check "$([ "$RC" = 0 ] && has "$OUT" "Codex is not installed" && has "$OUT" "Gemini CLI is not installed" && has "$OUT" "nothing to set up" && echo 0 || echo 1)" "agent hooks, neither installed: exit 0 and both are named as skipped"
check "$([ ! -e "$T/home/.codex" ] && [ ! -e "$T/home/.gemini" ] && echo 0 || echo 1)" "agent hooks, neither installed: no folder of theirs is created"
fresh; echo "$TOKEN" > "$ARIS/claude-hook-token"; mkdir -p "$T/home/.codex"; run_py install-agent-hooks.py --apply
check "$([ "$RC" = 0 ] && lacks "$ERR" "Traceback" && echo 0 || echo 1)" "agent hooks, Codex only: no crash on the missing ~/.gemini"
check "$(has "$T/home/.codex/config.toml" "codex_hooks = true" && has "$T/home/.codex/hooks.json" '"timeout": 5' && has "$T/home/.codex/hooks.json" "agent-hook.sh\\\" codex" && echo 0 || echo 1)" "agent hooks, Codex only: the hooks are written and Codex's hooks are switched on"
check "$([ ! -e "$T/home/.gemini" ] && has "$OUT" "Gemini CLI is not installed" && echo 0 || echo 1)" "agent hooks, Codex only: Gemini is skipped by name and nothing of its is created"
check "$([ "$(stat -f %Lp "$ARIS/agent-hook-headers")" = 600 ] && [ -x "$ARIS/agent-hook.sh" ] && echo 0 || echo 1)" "agent hooks: the token header file is 0600 and the hook script is installed"
run_py install-agent-hooks.py --apply
check "$([ "$RC" = 0 ] && [ "$(grep -c "^same" "$OUT")" = 2 ] && [ "$(ls "$T/home/.codex" | grep -c bak)" = 0 ] && echo 0 || echo 1)" "agent hooks: running it again changes nothing and makes no backups"
fresh; echo "$TOKEN" > "$ARIS/claude-hook-token"; mkdir -p "$T/home/.gemini"; run_py install-agent-hooks.py --apply
check "$([ "$RC" = 0 ] && has "$T/home/.gemini/settings.json" '"timeout": 5000' && lacks "$T/home/.gemini/settings.json" '"timeout": 5,' && [ ! -e "$T/home/.codex" ] && echo 0 || echo 1)" "agent hooks, Gemini only: its hooks get 5000 ms (not 5), and nothing of Codex's is created"
fresh; echo "$TOKEN" > "$ARIS/claude-hook-token"; mkdir -p "$T/home/.gemini"
printf '{"hooks":{"BeforeTool":[{"hooks":[{"type":"command","command":"\\"%s/agent-hook.sh\\" gemini","timeout":5},{"type":"command","command":"other-tool","timeout":7}]}]}}' "$ARIS" > "$T/home/.gemini/settings.json"
run_py install-agent-hooks.py --apply
check "$([ "$RC" = 0 ] && [ "$(grep -c '"timeout": 5000' "$T/home/.gemini/settings.json")" = 7 ] && has "$T/home/.gemini/settings.json" '"timeout": 7' && [ "$(grep -c 'agent-hook.sh' "$T/home/.gemini/settings.json")" = 7 ] && echo 0 || echo 1)" "agent hooks: an installed 5 ms Gemini hook is raised to 5000 in place; someone else's hook keeps its own"
fresh; echo "$TOKEN" > "$ARIS/claude-hook-token"; mkdir -p "$T/home/.codex"; echo "{broken" > "$T/home/.codex/hooks.json"; run_py install-agent-hooks.py --apply
check "$([ "$RC" != 0 ] && has "$ERR" "is not valid JSON" && lacks "$ERR" "Traceback" && has "$T/home/.codex/hooks.json" "{broken" && [ ! -e "$ARIS/agent-hook-headers" ] && echo 0 || echo 1)" "agent hooks: a hooks file that is not JSON stops it with a plain message and nothing written"

if [ -e /opt/homebrew/bin/claude ] || [ -e /usr/local/bin/claude ]; then
  echo "skip claude hooks: this Mac has claude in a system folder, so 'Claude Code not installed' cannot be staged here"
else
  fresh; run_py install-claude-hooks.py --apply
  check "$([ "$RC" = 0 ] && has "$OUT" "Claude Code is not installed" && [ ! -e "$T/home/.claude" ] && [ ! -e "$ARIS/claude-hook-token" ] && echo 0 || echo 1)" "claude hooks, no Claude Code: exit 0, says so, creates nothing"
fi
fresh; mkdir -p "$T/home/.claude"; run_py install-claude-hooks.py
check "$([ "$RC" = 0 ] && lacks "$ERR" "Traceback" && has "$OUT" "Dry run" && [ ! -e "$T/home/.claude/settings.json" ] && echo 0 || echo 1)" "claude hooks, no settings.json yet: the dry run prints the plan and writes nothing (hooks-3)"
run_py install-claude-hooks.py --apply
check "$([ "$RC" = 0 ] && has "$T/home/.claude/settings.json" "http://127.0.0.1:23350/hook" && has "$OUT" "nothing to back up" && echo 0 || echo 1)" "claude hooks, no settings.json yet: --apply makes it with Aris's hooks"
check "$([ "$(stat -f %Lp "$ARIS/claude-hook-token")" = 600 ] && [ -x "$ARIS/statusline.sh" ] && [ "$(ls "$T/home/.claude" | wc -l | tr -d ' ')" = 1 ] && echo 0 || echo 1)" "claude hooks: the token is 0600, the status line is installed, and no backup of a file that never existed"
run_py install-claude-hooks.py --apply
check "$([ "$RC" = 0 ] && has "$OUT" "Already installed" && echo 0 || echo 1)" "claude hooks: running it again changes nothing"
fresh; mkdir -p "$T/home/.claude"; echo '{"model":"opus","statusLine":{"type":"command","command":"my-line"},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"mine"}]}]}}' > "$T/home/.claude/settings.json"; run_py install-claude-hooks.py --apply
check "$([ "$RC" = 0 ] && has "$T/home/.claude/settings.json" '"command": "mine"' && has "$T/home/.claude/settings.json" '"command": "my-line"' && [ "$(ls "$T/home/.claude" | grep -c pre-notch-claude)" = 1 ] && echo 0 || echo 1)" "claude hooks, existing settings: the user's hook and status line stay, and the old file is backed up"
fresh; mkdir -p "$T/home/.claude"; echo "{broken" > "$T/home/.claude/settings.json"; run_py install-claude-hooks.py --apply
check "$([ "$RC" != 0 ] && has "$ERR" "is not valid JSON" && lacks "$ERR" "Traceback" && has "$T/home/.claude/settings.json" "{broken" && echo 0 || echo 1)" "claude hooks: settings that are not JSON stop it with a plain message, unchanged"

echo "# claude hooks: the events Aris uses, short timeouts, and older installs brought up to date (hooks-fast)"
# count_json <file> <python expression over `s` (the settings) and `ours` (Aris's hooks as (event, hook) pairs)>: prints its value.
count_json() {
  /usr/bin/python3 -I -c '
import json, sys
s = json.load(open(sys.argv[1]))
URL = "http://127.0.0.1:23350/hook"
ours = [(e, h) for e, gs in s.get("hooks", {}).items() for g in gs for h in g.get("hooks", []) if h.get("url") == URL]
theirs = [(e, h) for e, gs in s.get("hooks", {}).items() for g in gs for h in g.get("hooks", []) if h.get("url") != URL]
print(eval(sys.argv[2]))' "$1" "$2"
}
S="$T/home/.claude/settings.json"
fresh; S="$T/home/.claude/settings.json"; mkdir -p "$T/home/.claude"; run_py install-claude-hooks.py --apply
check "$([ "$RC" = 0 ] && [ "$(count_json "$S" 'sorted(e for e, h in ours)')" = "['Notification', 'PermissionRequest', 'PostToolUse', 'PostToolUseFailure', 'PreCompact', 'PreToolUse', 'SessionEnd', 'SessionStart', 'Stop', 'StopFailure', 'UserPromptSubmit']" ] && echo 0 || echo 1)" "claude hooks, new install: Aris's hook is on the eleven events it uses, once each, and on no other"
check "$([ "$(count_json "$S" 'sorted(set(h["timeout"] for e, h in ours if e != "PermissionRequest"))')" = "[2]" ] && [ "$(count_json "$S" '[h["timeout"] for e, h in ours if e == "PermissionRequest"]')" = "[130]" ] && echo 0 || echo 1)" "claude hooks, new install: an event's hook waits 2 s, the permission request 130 s"
check "$([ "$(count_json "$S" '"SubagentStart" in s["hooks"] or "SubagentStop" in s["hooks"]')" = "False" ] && echo 0 || echo 1)" "claude hooks, new install: nothing is registered for a subagent's start or stop"

# An install made by the earlier installer (13 events, 5 s and 600 s), recorded beside other tools' hooks: a guard on
# Bash and another app's http hook under PreToolUse, a Stop hook, and under SubagentStop someone's own hook in the
# same group as Aris's.
fresh; S="$T/home/.claude/settings.json"; mkdir -p "$T/home/.claude"; echo "$TOKEN" > "$ARIS/claude-hook-token"
sed "s/@TOKEN@/$TOKEN/g" "$DIR/fixtures/claude-settings-13-events.json" > "$S"
THEIRS_BEFORE="$(count_json "$S" 'sorted((e, json.dumps(h, sort_keys=True)) for e, h in theirs)')"
check "$([ "$(count_json "$S" 'len(ours)')" = 13 ] && [ "$(count_json "$S" 'len(theirs)')" = 4 ] && echo 0 || echo 1)" "claude hooks, the recorded older install: thirteen hooks of Aris's and four of other tools'"
run_py install-claude-hooks.py
check "$([ "$RC" = 0 ] && has "$OUT" "Dry run" && has "$OUT" '-            "timeout": 600,' && has "$OUT" '+            "timeout": 130,' && has "$OUT" '+            "timeout": 2,' && lacks "$OUT" "$TOKEN" && [ "$(count_json "$S" 'len(ours)')" = 13 ] && echo 0 || echo 1)" "claude hooks, older install: the dry run shows the new timeouts, never the token, and writes nothing"
run_py install-claude-hooks.py --apply
check "$([ "$RC" = 0 ] && [ "$(count_json "$S" 'len(ours)')" = 11 ] && [ "$(count_json "$S" 'sorted(set(h["timeout"] for e, h in ours if e != "PermissionRequest"))')" = "[2]" ] && [ "$(count_json "$S" '[h["timeout"] for e, h in ours if e == "PermissionRequest"]')" = "[130]" ] && echo 0 || echo 1)" "claude hooks, older install: Aris's hooks become the eleven, with today's timeouts"
check "$([ "$(count_json "$S" 'sorted((e, json.dumps(h, sort_keys=True)) for e, h in theirs)')" = "$THEIRS_BEFORE" ] && echo 0 || echo 1)" "claude hooks, older install: every hook of another tool is exactly as it was (its own timeout too)"
check "$([ "$(count_json "$S" '"SubagentStart" in s["hooks"]')" = "False" ] && [ "$(count_json "$S" '[[h.get("command") for h in g["hooks"]] for g in s["hooks"]["SubagentStop"]]')" = "[['other-tool subagent-done']]" ] && echo 0 || echo 1)" "claude hooks, older install: Aris's hook leaves SubagentStart (the event goes with it) and SubagentStop, where the other tool's hook stays in its group"
check "$([ "$(count_json "$S" '[len(g["hooks"]) for g in s["hooks"]["PreToolUse"]]')" = "[1, 1, 1]" ] && [ "$(count_json "$S" 's["model"] + " " + s["statusLine"]["command"]')" = "opus my-own-line" ] && [ "$(count_json "$S" 'all(h["headers"]["X-Aris-Token"] == "'"$TOKEN"'" for e, h in ours)')" = "True" ] && echo 0 || echo 1)" "claude hooks, older install: the groups, the model, the user's status line and the token are as they were"
check "$([ "$(ls "$T/home/.claude" | grep -c pre-notch-claude)" = 1 ] && has "$OUT" "Written. Backup:" && echo 0 || echo 1)" "claude hooks, older install: the file as it was is kept beside it"
run_py install-claude-hooks.py --apply
check "$([ "$RC" = 0 ] && has "$OUT" "Already installed" && [ "$(ls "$T/home/.claude" | grep -c pre-notch-claude)" = 1 ] && echo 0 || echo 1)" "claude hooks, older install: running it again changes nothing"
# Before the rename: the old header, and no terminal headers; and a timeout the user set by hand on Aris's hook.
fresh; S="$T/home/.claude/settings.json"; mkdir -p "$T/home/.claude"; echo "$TOKEN" > "$ARIS/claude-hook-token"
printf '{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"http","url":"http://127.0.0.1:23350/hook","timeout":45,"headers":{"X-Boring-Notch-Token":"%s"}}]}],"SubagentStart":[{"matcher":"","hooks":[{"type":"http","url":"http://127.0.0.1:23350/hook","timeout":5}]},{"hooks":[{"type":"http","url":"http://127.0.0.1:9/elsewhere","timeout":3}]}]}}' "$TOKEN" > "$S"
run_py install-claude-hooks.py --apply
check "$([ "$RC" = 0 ] && [ "$(count_json "$S" 'len(ours)')" = 11 ] && [ "$(count_json "$S" '[(h["timeout"], sorted(h["headers"])[0:1], "X-Boring-Notch-Token" in h["headers"]) for e, h in ours if e == "Stop"]')" = "[(2, ['X-Aris-Token'], False)]" ] && [ "$(count_json "$S" '[(e, h["url"], h["timeout"]) for e, h in theirs]')" = "[('SubagentStart', 'http://127.0.0.1:9/elsewhere', 3)]" ] && echo 0 || echo 1)" "claude hooks, an install from before the rename: its one hook is brought up to date in place, the rest added, and another server's hook on a retired event stays"

echo "# status line (hooks-3)"
fresh
STATUS='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":41.6},"rate_limits":{"five_hour":{"used_percentage":12.1}}}'
WITH_JQ="$(printf '%s' "$STATUS" | env -i HOME="$T/home" PATH="$T/bin:/usr/bin:/bin" bash "$T/root/Scripts/claude-statusline.sh")"
NO_JQ="$(printf '%s' "$STATUS" | env -i HOME="$T/home" PATH="$T/bin:/bin" bash "$T/root/Scripts/claude-statusline.sh")"
if command -v jq >/dev/null 2>&1; then
  check "$([ "$WITH_JQ" = "Opus · ctx 42% · 5h 13%" ] && echo 0 || echo 1)" "status line with jq: Opus · ctx 42% · 5h 13%"
else
  echo "skip status line: this Mac has no jq, so only the path without it runs"
fi
check "$([ "$NO_JQ" = "Opus · ctx 42% · 5h 13%" ] && echo 0 || echo 1)" "status line without jq (macOS 14): the same line, not an empty one"
check "$([ -z "$(printf 'not json' | env -i HOME="$T/home" PATH="$T/bin:/bin" bash "$T/root/Scripts/claude-statusline.sh")" ] && echo 0 || echo 1)" "status line without jq: input that is not JSON prints nothing and does not fail"

# ---------------------------------------------------------------------------------------------------------------------
if [ -f "$SHIP/promote.sh" ]; then
  echo "# promote.sh --dry-run (the only mode these tests ever run)"
  # A stand-in for the main folder: a checkout on fork with a release branch two commits ahead, old scripts and tests.
  promote_fresh() {
    fresh
    D="$T/main"; mkdir -p "$D/tests"
    git clone -q "$T/root" "$D/boring.notch" >/dev/null 2>&1
    (cd "$D/boring.notch" && git checkout -q -b release-candidate && echo a > a.txt && git add a.txt \
       && git -c user.name=test -c user.email=test@example.invalid commit -q -m "fix: one" && echo b > b.txt && git add b.txt \
       && git -c user.name=test -c user.email=test@example.invalid commit -q -m "fix: two" && git checkout -q fork) >/dev/null 2>&1
    for name in "${SCRIPTS[@]}"; do echo "old $name" > "$D/$name"; done
    echo "old" > "$D/tests/run.sh"; echo "gone tomorrow" > "$D/tests/only-in-main.swift"
    R="$T/release"; mkdir -p "$R/tests"
    for name in "${SCRIPTS[@]}"; do cp -p "$SHIP/$name" "$R/$name"; done
    for name in run.sh main.swift build-agent.sh assemble-app.sh min-os-check.sh launch-smoke.sh launch-smoke.sb; do echo "new" > "$R/tests/$name"; done
  }
  promote_dry() { EXTRA_ENV=(ARIS_DEST="$D"); run_in promote.sh --dry-run "$@"; }
  snapshot() { (cd "$D" && find . -type f -not -path './boring.notch/.git/*' -exec shasum {} + | sort; git -C boring.notch rev-parse HEAD fork; git -C boring.notch status --porcelain; ls -a "$D") 2>/dev/null; }

  promote_fresh; BEFORE="$(snapshot)"; promote_dry release-candidate "$R"
  check "$([ "$RC" = 0 ] && has "$OUT" "DRY RUN" && echo 0 || echo 1)" "promote --dry-run: a clean main checkout on fork and a fast-forward branch -> exit 0"
  check "$([ "$BEFORE" = "$(snapshot)" ] && echo 0 || echo 1)" "promote --dry-run: nothing changed (same files, same commits, no backup folder)"
  check "$(lacks "$T/calls.log" "xcodebuild" && lacks "$T/calls.log" "launchctl" && lacks "$T/calls.log" "codesign" && echo 0 || echo 1)" "promote --dry-run: deploy.sh was not run"
  check "$(has "$OUT" "2 commit(s)" && has "$OUT" "fix: one" && has "$OUT" "fix: two" && has "$OUT" "a.txt" && echo 0 || echo 1)" "promote --dry-run: it lists the commits and the files that will change"
  check "$(has "$OUT" "changed  deploy.sh" && has "$OUT" "only in the main folder (removed; kept in the backup)" && echo 0 || echo 1)" "promote --dry-run: it lists the scripts and tests outside git that will change"
  check "$(has "$OUT" "would run: git -C $D/boring.notch merge --ff-only release-candidate" && echo 0 || echo 1)" "promote --dry-run: the fast-forward is printed, and it is --ff-only"
  check "$(has "$OUT" "would run: cp -Rp $D/tests $D/backup-out-of-git-" && has "$OUT" "would run: cp -p $R/deploy.sh $D/deploy.sh" && has "$OUT" "would run: rsync -a --checksum --delete" && echo 0 || echo 1)" "promote --dry-run: the backup and the copies are printed"
  check "$(has "$OUT" "would run: $D/deploy.sh" && echo 0 || echo 1)" "promote --dry-run: the deploy is printed last"
  check "$(has "$OUT" "reset --hard $(git -C "$D/boring.notch" rev-parse fork)" && has "$OUT" "deploy.sh --rollback" && echo 0 || echo 1)" "promote --dry-run: it prints exactly how to undo each step"
  check "$(lacks "$OUT" "--force" && lacks "$OUT" "push" && echo 0 || echo 1)" "promote --dry-run: no forced update and no push anywhere"

  promote_fresh; echo x >> "$D/boring.notch/Aris/Aris.entitlements"; promote_dry release-candidate "$R"
  check "$([ "$RC" != 0 ] && has "$ERR" "uncommitted or untracked files" && has "$ERR" "Nothing was changed" && echo 0 || echo 1)" "promote: a main checkout that is not clean is refused"
  promote_fresh; echo x > "$D/boring.notch/stray.txt"; promote_dry release-candidate "$R"
  check "$([ "$RC" != 0 ] && has "$ERR" "uncommitted or untracked files" && echo 0 || echo 1)" "promote: an untracked file in the main checkout is refused too"
  promote_fresh; git -C "$D/boring.notch" checkout -q release-candidate; promote_dry release-candidate "$R"
  check "$([ "$RC" != 0 ] && has "$ERR" "is on release-candidate, not on fork" && echo 0 || echo 1)" "promote: a main checkout on another branch is refused"
  promote_fresh; (cd "$D/boring.notch" && echo c > c.txt && git add c.txt && git -c user.name=test -c user.email=test@example.invalid commit -q -m "on fork only") >/dev/null 2>&1; promote_dry release-candidate "$R"
  check "$([ "$RC" != 0 ] && has "$ERR" "cannot be fast-forwarded" && has "$ERR" "never forces" && echo 0 || echo 1)" "promote: a branch that is not a fast-forward of fork is refused, never forced"
  promote_fresh; promote_dry nothing-here "$R"
  check "$([ "$RC" != 0 ] && has "$ERR" "no local branch named nothing-here" && echo 0 || echo 1)" "promote: a branch that does not exist is refused"
  promote_fresh; rm "$R/install-agent-hooks.py"; promote_dry release-candidate "$R"
  check "$([ "$RC" != 0 ] && has "$ERR" "the release folder has no install-agent-hooks.py" && echo 0 || echo 1)" "promote: a release folder missing one of the six scripts is refused"
  promote_fresh; echo 'echo "old deploy"' > "$R/deploy.sh"; promote_dry release-candidate "$R"
  check "$([ "$RC" != 0 ] && has "$ERR" "is the old deploy.sh" && echo 0 || echo 1)" "promote: a release folder with the old deploy.sh (no rollback) is refused"
  promote_fresh; sed -i '' 's/runningApplicationWithProcessIdentifier/byBundleId/g' "$R/deploy.sh"; promote_dry release-candidate "$R"
  check "$([ "$RC" != 0 ] && has "$ERR" "quits Aris by its bundle id" && echo 0 || echo 1)" "promote: a deploy.sh that quits the app by its bundle id, not its pid, is refused (vm4 1)"
  promote_fresh; git clone -q "$D/boring.notch" "$R/boring.notch" >/dev/null 2>&1; promote_dry release-candidate "$R"
  check "$([ "$RC" != 0 ] && has "$ERR" "were made for another commit" && echo 0 || echo 1)" "promote: a release folder whose own checkout is at another commit than the branch is refused"
fi

# ---------------------------------------------------------------------------------------------------------------------
if [ -f "$DIR/launch-smoke.sb" ]; then
  echo "# launch check's sandbox takes its folders as parameters (smoke-1)"
  check "$(no grep -q "/Users/" "$DIR/launch-smoke.sb" "$DIR/launch-smoke.sh")" "smoke: the launch check names no user's folder (any worktree, any Mac)"
  # Under /private/tmp, not the usual temp folder: the profile lets the app use /private/var/folders (its caches).
  B="$(cd "$(mktemp -d /tmp/aris-dry-smoke.XXXXXX)" && pwd -P)"
  mkdir -p "$B/build-a" "$B/build-b" "$B/work" "$B/home/.config"; echo A > "$B/build-a/f"; echo B > "$B/build-b/f"; echo C > "$B/home/.config/f"
  # A harmless program under the real profile: it may read the build folder it was given and nothing beside it.
  boxed() { /usr/bin/sandbox-exec -D BUILD="$B/build-a" -D WORK="$B/work" -D HOME="$B/home" -f "$DIR/launch-smoke.sb" "$@" 2>/dev/null; }
  check "$([ "$(boxed /usr/bin/head -1 "$B/build-a/f")" = "A" ] && echo 0 || echo 1)" "smoke: the app may read the build folder passed in"
  check "$([ -z "$(boxed /usr/bin/head -1 "$B/build-b/f")" ] && echo 0 || echo 1)" "smoke: another build folder stays closed"
  check "$([ -z "$(boxed /usr/bin/head -1 "$B/home/.config/f")" ] && echo 0 || echo 1)" "smoke: the home's .config stays closed"
  check "$(boxed /bin/sh -c "echo x > '$B/work/w'" && [ -f "$B/work/w" ] && ! boxed /bin/sh -c "echo x > '$B/build-a/w'" && echo 0 || echo 1)" "smoke: only the check's own work folder can be written"
  rm -rf "${B:?}"
fi

# ---------------------------------------------------------------------------------------------------------------------
echo "# nothing real was touched"
check "$([ "$REAL_APP_BEFORE" = "$(stat -f %m /Applications/Aris.app 2>/dev/null || echo none)" ] && echo 0 || echo 1)" "the real /Applications/Aris.app has the same modification time as before the tests"
check "$([ "$HOME" = "$REAL_HOME" ] && ! grep -R -l -F -e "$REAL_HOME/.config" -e "$REAL_HOME/.claude" -e "$REAL_HOME/.codex" -e "$REAL_HOME/.gemini" -e "$REAL_HOME/Library" -e " /Applications/" "$WORK"/case-*/calls.log >/dev/null 2>&1 && echo 0 || echo 1)" \
  "no fake was ever called with a path in the real home or the real /Applications"

echo
if [ "$failures" -eq 0 ]; then echo "ALL PASSED"; else echo "$failures FAILED"; fi
exit "$([ "$failures" -eq 0 ] && echo 0 || echo 1)"
