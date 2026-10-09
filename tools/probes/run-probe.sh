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
HabitSignalProbe) FRAMEWORKS="-framework Cocoa -framework ApplicationServices";;
FaceFeaturePrintProbe) FRAMEWORKS="-framework AVFoundation -framework Vision -framework CoreImage -framework CoreVideo";;
*) printf '%s\n' 'Unknown probe'; exit 64;;
esac
if [ "$(uname -s)" != Darwin ]; then printf '%s\n' 'Requires macOS SDK and a real Mac'; exit 3; fi
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
EXTRA=""
[ "$NAME" = BLEReadProbe ] && EXTRA="$ROOT/BLEBatteryParsing.swift"
# 与 App 同一条特征管线；新增后端时把它的源文件加在这里（见 prototype/App/FaceEmbedderBackends.swift）。
[ "$NAME" = FaceFeaturePrintProbe ] && EXTRA="$ROOT/../../prototype/App/FaceEmbedder.swift $ROOT/../../prototype/App/VisionFaceEmbedder.swift $ROOT/../../prototype/App/FaceEmbedderBackends.swift $ROOT/../../prototype/Core/FaceScanGuard.swift $ROOT/../../prototype/Core/SessionLockState.swift"
swiftc -parse-as-library -swift-version 5 "$ROOT/$NAME.swift" $EXTRA -framework Foundation $FRAMEWORKS -o "$BUILD/probe"
"$BUILD/probe" "$@"
