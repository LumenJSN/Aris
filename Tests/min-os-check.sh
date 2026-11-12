#!/bin/bash
# min-os-check.sh <min macOS> <binary>…: fails when a binary's minimum macOS (vtool -show-build) is above <min>, or when it
# loads, not weakly, a system framework that doesn't exist on <min> (QA: aris-agent built on macOS 27 died in dyld on 26).
set -euo pipefail
MIN="$1"; shift
# Frameworks that are newer than macOS 14 (the app's floor): they must be weak-linked.
NEWER="FoundationModels Translation"
version() { echo "$1" | awk -F. '{ printf "%d%03d%03d", $1, $2, $3 }'; }
status=0
for bin in "$@"; do
  minos="$(vtool -show-build "$bin" 2>/dev/null | awk '/minos/ {print $2; exit}')"
  if [ -z "$minos" ]; then echo "min-os: $bin has no build version"; status=1; continue; fi
  if [ "$(version "$minos")" -gt "$(version "$MIN")" ]; then echo "min-os: $(basename "$bin") needs macOS $minos, above $MIN"; status=1; fi
  for framework in $NEWER; do
    # A strong load of a newer framework (LC_LOAD_DYLIB, not LC_LOAD_WEAK_DYLIB) kills the process on an older macOS.
    if otool -l "$bin" | awk -v f="$framework" '/cmd LC_LOAD_DYLIB$/ {strong=1; next} /cmd / {strong=0} strong && $0 ~ "/" f ".framework/" {found=1} END {exit !found}'; then
      echo "min-os: $(basename "$bin") loads $framework strongly (it must be weak below macOS 26)"; status=1
    fi
  done
  [ $status -eq 0 ] && echo "min-os: $(basename "$bin") runs from macOS $minos"
done
exit $status
