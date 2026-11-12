#!/bin/bash
# ls-listing-proof.sh: shows on this Mac how LaunchServices lists a helper inside an app once it touches AppKit
# (VM fourth re-check #4). It builds a probe (ls-listing-probe.swift with the helper's ArisHelperListing.swift), puts it
# into a throwaway app in a temp folder as Contents/MacOS/aris-agent (the app's own id is com.example.aris-lsproof, never
# Aris's), runs it once without and once with the settling aris-agent does first thing, and asks `lsappinfo` each time.
# Ends in "LS PROOF OK" when the settled probe is listed under its own id and name and nothing answers for the app's id.
# Nothing installed is touched; the real aris-agent is not run (outside launchd it stops before any AppKit use).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/LSProof.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.example.aris-lsproof</string>
<key>CFBundleExecutable</key><string>LSProof</string>
<key>CFBundleName</key><string>LSProof</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
cp "$DIR/ls-listing-probe.swift" "$WORK/main.swift"   # top-level code: compiled as a main.swift
swiftc -O -o "$APP/Contents/MacOS/aris-agent" "$WORK/main.swift" "$SRC/ArisAgent/ArisHelperListing.swift" || { echo "LS PROOF: the probe does not build"; exit 1; }
printf '#!/bin/sh\nexit 0\n' > "$APP/Contents/MacOS/LSProof"; chmod +x "$APP/Contents/MacOS/LSProof"
codesign --force --sign - "$APP/Contents/MacOS/aris-agent" 2>/dev/null

# listing <mode>: runs the probe, prints "<bundle id>|<name>|<what answers for the app's id>" as LaunchServices has it.
listing() {
  local pid asn id name app
  "$APP/Contents/MacOS/aris-agent" "$1" > "$WORK/pid" 2>/dev/null &
  sleep 1.5
  pid="$(head -1 "$WORK/pid")"
  asn="$(lsappinfo find pid="$pid" 2>/dev/null)"
  id="$( [ -n "$asn" ] && lsappinfo info -only bundleid "$asn" | sed -n 's/.*="\(.*\)"/\1/p')"
  name="$( [ -n "$asn" ] && lsappinfo info -only name "$asn" | sed -n '1s/^"\(.*\)" ASN.*/\1/p')"
  app="$(lsappinfo find bundleid=com.example.aris-lsproof 2>/dev/null)"
  wait
  echo "${id:-not listed}|${name:-}|${app:-nothing}"
}
BARE="$(listing bare)"; SETTLED="$(listing settled)"
echo "without settling: bundle id, name, what answers for the app's id = $BARE"
echo "settled:          bundle id, name, what answers for the app's id = $SETTLED"
status=0
[ "${BARE%%|*}" = "com.example.aris-lsproof" ] || { echo "LS PROOF: the bare probe was not listed under the app's id (nothing to prove on this macOS?)"; status=1; }
[ "$SETTLED" = "com.example.aris-lsproof.agent|aris-agent|nothing" ] || { echo "LS PROOF FAILED: the settled probe is not listed apart from the app"; status=1; }
[ "$status" = 0 ] && echo "LS PROOF OK"
exit $status
