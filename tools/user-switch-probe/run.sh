#!/bin/bash
# Compile and run the read-only probe. Usage: run.sh
set -euo pipefail
cd "$(dirname "$0")"; out="${TMPDIR:-/tmp}/UserSwitchProbe"
clang UserSwitchProbe.c -o "$out" -w -framework CoreFoundation -framework ApplicationServices
"$out"
echo "accounts(uid>=500): $(dscl . -list /Users UniqueID | awk '$2>=500' | wc -l | tr -d ' ')  console_sessions: $(who | grep -c console)  filevault: $(fdesetup status | head -1)"
