#!/bin/bash
# Builds Aris from this repository into build/Aris.app: the app (Xcode, Release), aris-agent and aris-tools
# (Tests/build-agent.sh), put together and signed (Tests/assemble-app.sh). Nothing is installed or started.
#
#   Scripts/build.sh                 the whole app, signed ad-hoc
#   Scripts/build.sh --agent-only    only aris-agent and aris-tools, into build/agent
#   SIGN_ID="Apple Development" Scripts/build.sh    signed with your (free) Apple Development certificate, so macOS
#                                                   keeps the permissions you grant across rebuilds
#
# Then move build/Aris.app to /Applications and open it; it sets its helper up itself. For rebuilding an installed
# copy in place (keep, swap, restart the helper, roll back), use Scripts/deploy.sh instead.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/build}"
SIGN_ID="${SIGN_ID:--}"
AGENT_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --agent-only) AGENT_ONLY=1 ;;
    -h|--help) sed -n 2,11p "$0"; exit 0 ;;
    *) echo "build.sh: unknown argument $arg (see --help)" >&2; exit 2 ;;
  esac
done
for tool in swiftc git; do command -v "$tool" >/dev/null 2>&1 || { echo "build.sh: $tool is missing (install Xcode)" >&2; exit 1; }; done
[ "$(uname -m)" = "arm64" ] || echo "build.sh: note: aris-agent and aris-tools are built for Apple silicon (arm64) only" >&2

COMMIT="$(git -C "$ROOT" rev-parse --short=8 HEAD 2>/dev/null || echo dev)"
[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ] || COMMIT="$COMMIT-dirty"

echo "== aris-agent and aris-tools ($COMMIT)"
rm -rf "$OUT/agent"; mkdir -p "$OUT/agent"
OUT="$OUT/agent" ARIS_COMMIT="$COMMIT" bash "$ROOT/Tests/build-agent.sh"
[ "$AGENT_ONLY" = "1" ] && { echo "BUILD OK: $OUT/agent"; exit 0; }

command -v xcodebuild >/dev/null 2>&1 || { echo "build.sh: xcodebuild is missing (install Xcode, then: sudo xcode-select -s /Applications/Xcode.app)" >&2; exit 1; }
echo "== the app (Release; Swift packages are fetched on the first build)"
DERIVED="$ROOT/build-release"
if ! (cd "$ROOT" && xcodebuild -project Aris.xcodeproj -scheme Aris -configuration Release -derivedDataPath "$DERIVED" \
      CODE_SIGNING_ALLOWED=NO ARIS_COMMIT="$COMMIT" ARIS_BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)" build > "$OUT/xcodebuild.log" 2>&1); then
  grep -E "error:" "$OUT/xcodebuild.log" | head -20 >&2 || true
  echo "build.sh: the app did not build (full log: $OUT/xcodebuild.log)" >&2; exit 1
fi

echo "== put together and sign ($([ "$SIGN_ID" = "-" ] && echo "ad-hoc" || echo "$SIGN_ID"))"
rm -rf "$OUT/Aris.app"
ditto "$DERIVED/Build/Products/Release/Aris.app" "$OUT/Aris.app"
SRC="$ROOT" bash "$ROOT/Tests/assemble-app.sh" "$OUT/Aris.app" "$OUT/agent" "$SIGN_ID"
echo "BUILD OK: $OUT/Aris.app"
[ "$SIGN_ID" = "-" ] && echo "Signed ad-hoc: macOS asks for the permissions again after every rebuild (see docs/BUILD.md, Signing)."
exit 0
