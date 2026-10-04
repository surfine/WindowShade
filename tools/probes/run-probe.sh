set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
NAME=${1:?supply probe name}; shift
case "$NAME" in
BLEReadProbe) FRAMEWORKS="-framework CoreBluetooth";;
RemoteHIDProbe) FRAMEWORKS="-framework IOKit";;
WheelAssociationProbe) FRAMEWORKS="-framework IOKit";;
MultitouchSymbolProbe) FRAMEWORKS="";;
IdentityBoundaryProbe) FRAMEWORKS="-framework LocalAuthentication -framework CryptoKit";;
LockStateProbe) FRAMEWORKS="-framework CoreGraphics";;
*) printf '%s\n' 'Unknown probe'; exit 64;;
esac
if [ "$(uname -s)" != Darwin ]; then printf '%s\n' 'Requires macOS SDK and a real Mac'; exit 3; fi
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
swiftc -parse-as-library -swift-version 5 "$ROOT/$NAME.swift" -framework Foundation $FRAMEWORKS -o "$BUILD/probe"
"$BUILD/probe" "$@"
