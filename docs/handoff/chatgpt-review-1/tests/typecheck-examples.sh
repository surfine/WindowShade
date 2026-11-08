#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDS=(T1 L1 A1 D1 D2 I1 I9 T4 D4 A2 L4 I7 D5 D6)
if [[ "${1:-}" == '--macos' ]]; then
  [[ "$(uname -s)" == Darwin ]] || { echo '--macos requires a Mac with an SDK' >&2; exit 2; }
  IDS+=(M1 S1 T2 A3 D3 L2 I2 I3 I5 I8)
elif [[ -n "${1:-}" ]]; then
  echo 'usage: typecheck-examples.sh [--macos]' >&2; exit 2
fi
for ID in "${IDS[@]}"; do
  if [[ "$(uname -s)" == Darwin ]]; then
    swiftc -swift-version 6 -parse-as-library -typecheck \
      -target "$(uname -m)-apple-macosx14.0" "$ROOT/examples/$ID.swift"
  else
    swiftc -swift-version 6 -parse-as-library -typecheck "$ROOT/examples/$ID.swift"
  fi
  echo "PASS typecheck $ID"
done
