#!/bin/bash
set -euo pipefail
exec bash "$(dirname "$0")/run-appkit-tests.sh" SettingsNavigationTests
