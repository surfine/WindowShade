#!/usr/bin/env bash
# Explicit opt-in only. This opens a random IPv4 loopback port with ephemeral synthetic keys.
set -euo pipefail
if [[ "${1:-}" != "--loopback-self-test" || "$#" != 1 ]]; then
  echo 'Usage: bash tools/probes/companion-channel/run.sh --loopback-self-test' >&2
  exit 2
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
exec bash "$ROOT/tests/run-companion-channel-tests.sh" --loopback-self-test
