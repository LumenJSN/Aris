#!/bin/bash
# Draws the open notch's background recipe off screen, before and after, over a white window, a mid-grey one and a
# dark photo-like gradient, with the notch's text colours on top, and prints each text style's contrast.
# Never touches the screen; reads nothing of Aris's. usage: render.sh [OUT_DIR]
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
A="$DIR/../../Aris/private/Aris"
WORK="$(mktemp -d)"
swiftc -swift-version 5 -O -o "$WORK/render" "$DIR/main.swift" "$DIR/glass-contrast.swift" "$A/Design/ArisGlassRecipe.swift"
"$WORK/render" "${1:-$(mktemp -d)}"
