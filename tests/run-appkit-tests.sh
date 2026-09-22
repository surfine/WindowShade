#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_NAME="${1:-SettingsNavigationTests}"
case "$TEST_NAME" in
  SettingsNavigationTests|ClassicStripTests|WindowFoldEffectsTests) ;;
  *) echo "Unknown AppKit test: $TEST_NAME" >&2; exit 2 ;;
esac
mkdir -p .build/appkit-tests
# Compile the production AppKit views with a separate test entry point.
WORK="$(mktemp -d "$(pwd)/.build/appkit-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
SOURCES=()
while IFS= read -r source; do
  mkdir -p "$WORK/$(dirname "$source")"
  cp "$source" "$WORK/$source"
  SOURCES+=("$WORK/$source")
done < <(rg --files prototype -g '*.swift' -g '!main.swift' -g '!*.app/**' | sort)
cp "tests/$TEST_NAME.swift" "$WORK/$TEST_NAME.swift"
TEST_SOURCE=("$WORK/$TEST_NAME.swift")
if [ "$TEST_NAME" = WindowFoldEffectsTests ]; then
  # Swift grants same-file extensions private access. Test the real lifecycle
  # with inert jobs without exposing mutation hooks in the shipping interface.
  cat "$WORK/$TEST_NAME.swift" >> "$WORK/prototype/Effects/WindowFoldEffects.swift"
  TEST_SOURCE=()
fi
GLASS_DEFINE=()
if [ -f "$(xcrun --show-sdk-path --sdk macosx)/System/Library/Frameworks/AppKit.framework/Headers/NSGlassEffectView.h" ]; then
  GLASS_DEFINE=(-DWINDOWSHADE_SDK_HAS_GLASS)
fi
swiftc -target "$(uname -m)-apple-macosx14.0" ${GLASS_DEFINE[@]+"${GLASS_DEFINE[@]}"} \
  "${SOURCES[@]}" ${TEST_SOURCE[@]+"${TEST_SOURCE[@]}"} \
  -framework Cocoa -framework Carbon -framework ApplicationServices \
  -framework ScreenCaptureKit -framework QuartzCore -framework CoreText \
  -framework AVFoundation -framework ServiceManagement -framework Metal \
  -framework MetalKit -framework IOKit -framework CoreImage -framework VideoToolbox \
  -o ".build/appkit-tests/$TEST_NAME"
".build/appkit-tests/$TEST_NAME"
