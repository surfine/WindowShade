#!/usr/bin/env bash
# Compile and run the LaunchpadBackdrop standalone tests.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$root/.build/launchpad-tests"
binary="$out_dir/backdrop"

mkdir -p "$out_dir"

swiftc \
  -O \
  -o "$binary" \
  "$root/prototype/App/LaunchpadBackdrop.swift" \
  "$root/tests/LaunchpadBackdropTests.swift"

"$binary"
