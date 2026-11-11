#!/usr/bin/env bash
# Standalone QA fixture: builds a native production-view preview from the full
# production Swift sources plus one caller-supplied @main render entry, then runs
# ONLY that entry. It never launches a product main. Visual sign-off is done by
# the controller independently.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SELF="${BASH_SOURCE[0]}"
SELF="$(cd "$(dirname "$SELF")" && pwd)/$(basename "$SELF")"
cd "$ROOT"

OUTPUT="${1:-}"
ENTRY="${2:-}"
if [ -z "$OUTPUT" ]; then
  echo "usage: render-native-surfaces.sh ABS_OUTPUT_DIR ABS_SWIFT_ENTRY [--swift6]" >&2
  exit 2
fi
if [ -z "$ENTRY" ]; then
  echo "usage: render-native-surfaces.sh ABS_OUTPUT_DIR ABS_SWIFT_ENTRY [--swift6]" >&2
  exit 2
fi
case "$OUTPUT" in
  /*) ;;
  *) echo "output dir must be absolute: $OUTPUT" >&2; exit 2 ;;
esac

LANGUAGE_VERSION=5
LANGUAGE_FLAGS=(-swift-version 5)
case "${3:-}" in
  "") ;;
  --swift6)
    LANGUAGE_VERSION=6
    LANGUAGE_FLAGS=(-swift-version 6 -strict-concurrency=complete -warnings-as-errors)
    ;;
  *) echo "unknown render mode: $3" >&2; exit 2 ;;
esac
case "$ENTRY" in
  /*) ;;
  *) echo "swift entry must be absolute: $ENTRY" >&2; exit 2 ;;
esac
if [ ! -f "$ENTRY" ]; then
  echo "swift entry is missing or not a file: $ENTRY" >&2
  exit 2
fi
case "${ENTRY##*/}" in
  main.swift) echo "refusing main.swift as render entry: $ENTRY" >&2; exit 2 ;;
esac

mkdir -p "$ROOT/.build"
WORK="$(mktemp -d "$ROOT/.build/native-surfaces.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Native process-supervision port: compile the C source into a WORK-local object.
NATIVE_DIR="$WORK/native"
mkdir -p "$NATIVE_DIR"
cp "$ROOT/prototype/Native/WS2Child.c" "$ROOT/prototype/Native/WS2Child.h" "$ROOT/prototype/Native/module.modulemap" "$NATIVE_DIR/"
cc -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.0 -c "$NATIVE_DIR/WS2Child.c" -o "$NATIVE_DIR/WS2Child.o"

# Snapshot every production Swift source except product mains and app bundles.
SOURCES=()
while IFS= read -r source; do
  mkdir -p "$WORK/$(dirname "$source")"
  cp "$source" "$WORK/$source"
  SOURCES+=("$WORK/$source")
done < <(rg --files prototype -g '*.swift' -g '!main.swift' -g '!*.app/**' | sort)

# Copy the caller's standalone @main render entry into WORK.
ENTRY_COPY="$WORK/$(basename "$ENTRY")"
cp "$ENTRY" "$ENTRY_COPY"

# Immutable compiler inputs recorded by SHA256 before any build step.
python3 - "$ROOT" "$OUTPUT" "$WORK" "$ENTRY" "$SELF" "$ENTRY_COPY" "$NATIVE_DIR/WS2Child.c" "$NATIVE_DIR/WS2Child.h" "$NATIVE_DIR/module.modulemap" "${SOURCES[@]}" <<'PY'
from pathlib import Path
import sys, hashlib, json
root, output, work, entry = map(Path, sys.argv[1:5])
tracked = [Path(p) for p in sys.argv[5:]]
def key(p: Path) -> str:
    if p == work / entry.name:
        p = entry
    elif p.is_relative_to(work / 'native'):
        p = root / 'prototype/Native' / p.name
    elif p.is_relative_to(work):
        p = root / p.relative_to(work)
    return str(p.relative_to(root)) if p.is_absolute() and p.is_relative_to(root) else str(p)
def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()
output.mkdir(parents=True, exist_ok=True)
(output / 'sources.json').write_text(json.dumps({key(p): sha(p) for p in tracked}, indent=2) + '\n')
PY

# GLASS_DEFINE detection is intentional and identical to tests/run-appkit-tests.sh.
GLASS_DEFINE=()
if [ -f "$(xcrun --show-sdk-path --sdk macosx)/System/Library/Frameworks/AppKit.framework/Headers/NSGlassEffectView.h" ]; then
  GLASS_DEFINE=(-DWINDOWSHADE_SDK_HAS_GLASS)
fi

# Unoptimized production library. Default Swift 5; opt into the production Swift 6 strictness for runtime probes.
swiftc "${LANGUAGE_FLAGS[@]}" -module-cache-path "$ROOT/.build/module-cache" -whole-module-optimization -target "$(uname -m)-apple-macosx14.0" ${GLASS_DEFINE[@]+"${GLASS_DEFINE[@]}"} \
  -I "$NATIVE_DIR" "$NATIVE_DIR/WS2Child.o" \
  "${SOURCES[@]}" "$ENTRY_COPY" \
  -framework Cocoa -framework Carbon -framework ApplicationServices -framework LocalAuthentication -framework LocalAuthenticationEmbeddedUI \
  -framework ScreenCaptureKit -framework QuartzCore -framework CoreText \
  -framework AVFoundation -framework Vision -framework ServiceManagement -framework Metal \
  -framework CoreAudio -framework MapKit -framework MetalKit -framework IOKit -framework CoreImage -framework VideoToolbox \
  -o "$WORK/render"

python3 - "$OUTPUT" "$WORK/render" "$LANGUAGE_VERSION" <<'PY'
from pathlib import Path
import sys, hashlib, json
output = Path(sys.argv[1]); binary = Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
(output / 'renderer.json').write_text(json.dumps(
    {"renderer": str(binary), "sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
     "swiftLanguageVersion": int(sys.argv[3]), "strictConcurrency": int(sys.argv[3]) == 6,
     "warningsAsErrors": int(sys.argv[3]) == 6, "optimized": False}, indent=2) + '\n')
PY

# Execute ONLY the caller entry; it owns its self-contained data and window capture.
"$WORK/render" "$OUTPUT"
