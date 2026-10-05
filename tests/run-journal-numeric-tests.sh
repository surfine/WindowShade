#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/journal-numeric-tests
swiftc -O -parse-as-library \
  prototype/Recovery/JournalNumeric.swift \
  tests/JournalNumericTests.swift \
  -o .build/journal-numeric-tests/journal-numeric
.build/journal-numeric-tests/journal-numeric
