#!/bin/bash
# 设置窗口外观自适应性检查：
# 用隔离构建的 --settings-shots 渲染每一页的浅色/深色版本，然后逐页比较内容区平均
# 亮度。曾经出现过“深色模式下分组卡片仍是浅色、文字几乎不可读”的缺陷（静态颜色被
# 冻结），这个脚本用来防止同类回归。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/design-review/settings-appearance-check.txt"
SHOTS="$ROOT/.build/settings-shots"
BIN="$ROOT/.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade"
mkdir -p "$(dirname "$OUT")"

if [ ! -x "$BIN" ]; then
  echo "缺少隔离构建：先运行 cd prototype && ./build.sh --stage" >&2
  exit 1
fi

"$BIN" --settings-shots "$SHOTS" >/dev/null

cat > /tmp/settings-appearance-check.swift <<'SWIFT'
import Cocoa

func meanBrightness(_ path: String, xRange: Range<Int>, yRange: Range<Int>) -> Double? {
    guard let image = NSImage(contentsOfFile: path), let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    var sum = 0.0
    var count = 0
    for y in stride(from: yRange.lowerBound, to: min(yRange.upperBound, rep.pixelsHigh), by: 8) {
        for x in stride(from: xRange.lowerBound, to: min(xRange.upperBound, rep.pixelsWide), by: 8) {
            if let color = rep.colorAt(x: x, y: y) {
                sum += color.brightnessComponent
                count += 1
            }
        }
    }
    return count > 0 ? sum / Double(count) : nil
}

@main
enum SettingsAppearanceCheck {
    static func main() {
        let directory = CommandLine.arguments[1]
        let pages = ["效果", "卷帘", "窗口浏览", "权限与启动", "高级"]
        var failures = 0
        print("page           light   dark    delta   result")
        for page in pages {
            guard let light = meanBrightness("\(directory)/settings-light-\(page).png",
                                             xRange: 500..<1780, yRange: 120..<1300),
                  let dark = meanBrightness("\(directory)/settings-dark-\(page).png",
                                            xRange: 500..<1780, yRange: 120..<1300) else {
                print("\(page): missing screenshot"); failures += 1; continue
            }
            let delta = light - dark
            let ok = light > 0.6 && dark < 0.5 && delta >= 0.4
            if !ok { failures += 1 }
            print(String(format: "%-14@ %.3f   %.3f   %.3f   %@",
                         page as NSString, light, dark, delta, ok ? "PASS" : "FAIL"))
        }
        print(failures == 0 ? "PASS: settings pages follow the appearance"
                            : "FAILED: \(failures) page(s) do not adapt")
        exit(failures == 0 ? 0 : 1)
    }
}
SWIFT

swiftc -target "$(uname -m)-apple-macosx14.0" -parse-as-library \
  /tmp/settings-appearance-check.swift -framework Cocoa -o /tmp/settings-appearance-check
/tmp/settings-appearance-check "$SHOTS" | tee "$OUT"
echo "==> 结果写入 $OUT"
