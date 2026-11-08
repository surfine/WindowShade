#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/ws2-part3-tests.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT
sources=()
while IFS= read -r p; do sources+=("$p"); done < <(find "$ROOT/packages" -path '*/prototype/Core/*.swift' -o -path '*/prototype/Support/*.swift' | sort)
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors "$ROOT/contracts/Contracts.swift" "${sources[@]}" "$ROOT/tests/Part3Tests.swift" -o "$OUT/tests"
"$OUT/tests" "$ROOT" "$(command -v python3)"
