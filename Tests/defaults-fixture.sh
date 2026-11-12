#!/bin/bash
# The defaults fixture: compiles the preference types and bridges against the Defaults package built by the Release
# xcodebuild (run that first) and checks the stored shapes. Nothing outside a throwaway defaults domain is touched.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Aris/private"
BR="$DIR/../build-release/Build/Products/Release"
OUT="${OUT:-$(mktemp -d)/defaults-fixture}"
swiftc -o "$OUT" -profile-generate -I "$BR" "$BR/Defaults.o" "$DIR/defaults-fixture/main.swift" \
  "$SRC/Notch/ArisPreferenceTypes.swift" "$SRC/Notch/ArisAppLanguage.swift" "$SRC/Notch/ArisPreferenceStorage.swift" \
  "$SRC/Calendar/ArisCalendarSelection.swift"
LLVM_PROFILE_FILE=/dev/null "$OUT" || { echo "FIXTURE FAILED"; exit 1; }
