#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v swiftc >/dev/null || { echo 'swiftc is required' >&2; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ws-review-boundaries.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
SOURCES=()
for ID in T1 L1 A1 D1 D2 I1 I9 A2 L4 I7 D5 D6; do
  SOURCES+=("$ROOT/examples/$ID.swift")
done
swiftc -swift-version 6 -parse-as-library "${SOURCES[@]}" \
  "$ROOT/tests/BoundaryTests.swift" -o "$WORK/boundaries"
"$WORK/boundaries"
