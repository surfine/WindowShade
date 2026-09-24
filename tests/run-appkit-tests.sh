#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_NAME="${1:-SettingsNavigationTests}"
case "$TEST_NAME" in
  all|SettingsNavigationTests|ClassicStripTests|WindowFoldEffectsTests|GlanceLifecycleTests|CarryControllerTests) ;;
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
TEST_SOURCE=()
if [ "$TEST_NAME" = all ]; then
  TESTS=(SettingsNavigationTests ClassicStripTests WindowFoldEffectsTests GlanceLifecycleTests CarryControllerTests)
else
  TESTS=("$TEST_NAME")
fi
for name in "${TESTS[@]}"; do
  if [ "$TEST_NAME" = all ]; then
    # Share compilation, not process state: the dispatcher below runs one suite
    # per invocation. Keep the test bodies identical to their standalone entry.
    sed 's/@main//' "tests/$name.swift" > "$WORK/$name.swift"
  else
    cp "tests/$name.swift" "$WORK/$name.swift"
  fi
  case "$name" in
    WindowFoldEffectsTests) cat "$WORK/$name.swift" >> "$WORK/prototype/Effects/WindowFoldEffects.swift" ;;
    CarryControllerTests) cat "$WORK/$name.swift" >> "$WORK/prototype/App/Carry.swift" ;;
    GlanceLifecycleTests) cat "$WORK/$name.swift" >> "$WORK/prototype/App/Glance.swift" ;;
    *) TEST_SOURCE+=("$WORK/$name.swift") ;;
  esac
done
if [ "$TEST_NAME" = all ]; then
  cat > "$WORK/AppKitTestRunner.swift" <<'SWIFT'
import Cocoa
@main struct AppKitTestRunner {
  @MainActor static func main() async {
    switch CommandLine.arguments.dropFirst().first {
    case "SettingsNavigationTests": await SettingsNavigationTests.main()
    case "ClassicStripTests": ClassicStripTests.main()
    case "WindowFoldEffectsTests": WindowFoldEffectsTests.main()
    case "GlanceLifecycleTests": GlanceLifecycleTests.main()
    case "CarryControllerTests": CarryControllerTests.main()
    default: preconditionFailure("Choose an AppKit test suite")
    }
  }
}
SWIFT
  TEST_SOURCE+=("$WORK/AppKitTestRunner.swift")
fi
GLASS_DEFINE=()
if [ -f "$(xcrun --show-sdk-path --sdk macosx)/System/Library/Frameworks/AppKit.framework/Headers/NSGlassEffectView.h" ]; then
  GLASS_DEFINE=(-DWINDOWSHADE_SDK_HAS_GLASS)
fi
swiftc -whole-module-optimization -target "$(uname -m)-apple-macosx14.0" ${GLASS_DEFINE[@]+"${GLASS_DEFINE[@]}"} \
  "${SOURCES[@]}" ${TEST_SOURCE[@]+"${TEST_SOURCE[@]}"} \
  -framework Cocoa -framework Carbon -framework ApplicationServices \
  -framework ScreenCaptureKit -framework QuartzCore -framework CoreText \
  -framework AVFoundation -framework ServiceManagement -framework Metal \
  -framework MetalKit -framework IOKit -framework CoreImage -framework VideoToolbox \
  -o ".build/appkit-tests/$TEST_NAME"
if [ "$TEST_NAME" = all ]; then
  for name in "${TESTS[@]}"; do ".build/appkit-tests/$TEST_NAME" "$name"; done
else
  ".build/appkit-tests/$TEST_NAME"
fi
