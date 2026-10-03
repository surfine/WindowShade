#!/bin/bash
# Isolated optimized compile/link only: no app launch, install, signing or publish.
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
 echo "NOT RUN: requires macOS SDK and Metal tools"; exit 78
fi
BASE="${1:?Supply v6 candidate repo}"
BASE="$(cd "$BASE" && pwd)"
command -v xcrun >/dev/null
xcrun --find swiftc >/dev/null
xcrun --find metal >/dev/null
BUILD="$(mktemp -d)"; trap 'rm -rf "$BUILD"' EXIT
mkdir "$BUILD/repo"
# Do not source the user's signing environment or copy build outputs into this check.
rsync -a --exclude=.git --exclude=.build --exclude='*.app' --exclude=local-codesign.env "$BASE/" "$BUILD/repo/"
cd "$BUILD/repo/prototype"
echo "Isolated SDK check of $BASE; local-codesign.env excluded"
bash ./build.sh --check
