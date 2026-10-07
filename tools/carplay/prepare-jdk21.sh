#!/bin/bash
# Optional, repository-local macOS ARM64 toolchain. No system install or services.
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo 'Use an external JDK 21 via JAVA_HOME on this platform.'; exit 2; }
directory="$PWD/.build/tools/jdk21"
archive="$directory/archive.tar.gz"
mkdir -p "$directory"
url='https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_aarch64_mac_hotspot_21.0.12.1_1.tar.gz'
expected=3623232f33a9c3baadf304480b2535f9a3cba8a58d42ecbb438ba267315d9998
if [[ ! -f "$archive" ]]; then
  curl -fL --retry 2 "$url" -o "$archive.part"
  mv "$archive.part" "$archive"
fi
actual=$(shasum -a 256 "$archive")
[[ "${actual%% *}" == "$expected" ]] || { echo 'REFUSED: JDK archive checksum mismatch'; exit 1; }
if [[ ! -x "$directory/jdk-21.0.12.1+1/Contents/Home/bin/java" ]]; then
  tar -xzf "$archive" -C "$directory"
fi
"$directory/jdk-21.0.12.1+1/Contents/Home/bin/java" -version
