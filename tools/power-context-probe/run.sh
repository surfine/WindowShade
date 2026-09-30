#!/usr/bin/env bash
set -euo pipefail

# Resolve repository root from this script's location.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build/power-context-probe"
mkdir -p "$BUILD_DIR"

# Target the host architecture on macOS 14.0.
ARCH="$(uname -m)"
BIN="$BUILD_DIR/power-context-probe"

swiftc -O \
  -target "${ARCH}-apple-macosx14.0" \
  -framework Foundation \
  -framework IOKit \
  -o "$BIN" \
  "$SCRIPT_DIR/main.swift"

exec "$BIN" "$@"
