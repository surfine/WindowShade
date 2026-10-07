#!/bin/bash
# No receiver startup, Bluetooth, mDNS, phone connection, or identity acquisition.
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD"
checkout="$root/.build/research/playport"
revision=9a0882dd0ffe48e467b59d58b12d81391df55ade
mode="${1:---check}"
case "$mode" in --prepare|--check|--resolve-jvm) ;; *) echo 'Usage: bash tools/carplay/check-playport.sh [--prepare|--check|--resolve-jvm]' >&2; exit 64;; esac
if [[ -z "${JAVA_HOME:-}" ]]; then
  for candidate in "$root"/.build/tools/jdk21/*/Contents/Home; do
    if [[ -x "$candidate/bin/java" ]]; then export JAVA_HOME="$candidate"; break; fi
  done
fi
if [[ -n "${JAVA_HOME:-}" ]]; then export PATH="$JAVA_HOME/bin:$PATH"; fi
export GRADLE_USER_HOME="$root/.build/tools/gradle-home"
if [[ "$mode" == --prepare && ! -d "$checkout" ]]; then
  mkdir -p "$(dirname "$checkout")"
  git clone --no-checkout https://github.com/youcci/playport.git "$checkout"
  git -C "$checkout" checkout --detach "$revision"
fi
[[ -d "$checkout/.git" ]] || { echo 'BLOCKED: checkout missing; run --prepare (network required)'; exit 2; }
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$revision" ]] || { echo 'REFUSED: unexpected upstream revision'; exit 2; }
[[ -z "$(git -C "$checkout" status --porcelain --untracked-files=no)" ]] || { echo 'REFUSED: modified upstream tracked files'; exit 2; }
[[ ! -e "$checkout/identity/offline-mfi" ]] || { echo 'REFUSED: credential-free checkout required'; exit 2; }
mkdir -p "$root/.build/carplay-tests"
# Redirect this command to a log when retaining evidence; avoid process substitution.
echo "PlayPort revision: $revision"
date -u '+UTC %Y-%m-%dT%H:%M:%SZ'
node --version
if [[ "$mode" == --prepare ]]; then
  (cd "$checkout/web" && npm ci --ignore-scripts --no-audit --no-fund)
fi
result=0
(cd "$checkout/web" && npm test && npm run build) || result=1
if java -version; then
  # Synthetic/local tests only; never :server:run or the real identity test.
  # Only the explicit --resolve-jvm mode allows Gradle dependency downloads.
  offline=--offline
  if [[ "$mode" == --resolve-jvm ]]; then offline=; fi
  (cd "$checkout" && ./gradlew ${offline:+$offline} --no-daemon :protocol:test \
    --tests '*Iap2ProtocolTest' --tests '*CarPlaySizeTest' \
    --tests '*LocalMfiAuthenticationClientTest') || result=1
else
  echo 'BLOCKED: JDK 21 unavailable; JVM synthetic protocol tests NOT RUN.'
  [[ "$result" == 0 ]] && result=2
fi
echo "Check exit: $result (0 pass; 1 failure; 2 prerequisite blocked)"
exit "$result"
