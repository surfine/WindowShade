import Cocoa

// 规格 R47：像素函数的越界体检。所有手算下标的函数都喂一遍极端图像（1×1、单行、单列、很宽很扁、
// 全透明、全不透明、刚过门槛），不许崩；返回 nil 或一个值都行。只拿 PreviewRenderer 本身编，其余给桩。
func wlog(_ message: String) {}
let quickLookOriginalTitleBarHeight: CGFloat = 38
let hoverPreviewMaxPixelSize = CGSize(width: 720, height: 480)
func fixedNonstandardChromeHeight(pid: pid_t) -> CGFloat? { nil }
func fallbackControlPaddedChromeHeight(pid: pid_t, minimum _: CGFloat) -> CGFloat? { nil }
enum TrafficAction { case close, minimize, zoom, fullScreen }
struct WindowChromeProfile {
    var standardCropHeight: CGFloat = 28
    var preciseChrome = false
    var axBarHeight: CGFloat = 28
    var isQuickLook = false
    var standardTitleBarOnly = false
    var boundaryName = "test"
}
enum SystemCornerPath {
    static func cgPath(in rect: CGRect, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: min(radius, rect.width / 2), cornerHeight: min(radius, rect.height / 2), transform: nil)
    }
}

func image(_ w: Int, _ h: Int, alpha: (Int, Int) -> UInt8) -> CGImage {
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h { for x in 0..<w {
        let a = alpha(x, y), i = (y * w + x) * 4
        buf[i] = a; buf[i + 1] = a; buf[i + 2] = a; buf[i + 3] = a
    } }
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

@main
struct PreviewRendererBoundsTests {
    static func main() {
        let sizes = [(1, 1), (1, 40), (40, 1), (2, 2), (20, 20), (21, 21), (22, 300), (3000, 2), (2, 3000), (1201, 131), (64, 64)]
        let alphas: [(String, (Int, Int) -> UInt8)] = [
            ("clear", { _, _ in 0 }), ("opaque", { _, _ in 255 }),
            ("half", { x, y in (x + y) % 2 == 0 ? 255 : 0 }), ("topCorners", { x, y in (y < 3 && (x < 3)) ? 0 : 255 })]
        var runs = 0
        for (w, h) in sizes {
            for (_, alpha) in alphas {
                let img = image(w, h, alpha: alpha)
                for scale in [0.5, 1.0, 2.0, 3.0] as [CGFloat] {
                    _ = preciseVisualChromeHeight(of: img, scale: scale, minimum: 0)
                    _ = preciseVisualChromeHeight(of: img, scale: scale, minimum: 1000)
                }
                _ = mirrorRoundCorners(img)
                for logical in [0, 1, 28, 10_000] as [CGFloat] { _ = nativeTitleStripLooksBroken(img, logicalHeight: logical) }
                _ = estimatedCornerRadiusPixels(from: img)
                for radius in [0, 1, 12, 10_000] as [CGFloat] {
                    _ = roundedClippedImage(img, cornerRadius: radius)
                }
                for max in [CGSize(width: 1, height: 1), CGSize(width: 720, height: 480), CGSize(width: 0, height: 0)] {
                    _ = downsampleCGImage(img, maxPixelSize: max)
                }
                let profiles = [WindowChromeProfile(), WindowChromeProfile(preciseChrome: true, axBarHeight: 500),
                                WindowChromeProfile(isQuickLook: true), WindowChromeProfile(standardTitleBarOnly: true)]
                for profile in profiles {
                    for logical in [CGSize(width: 0, height: 0), CGSize(width: 1, height: 1),
                                    CGSize(width: CGFloat(w), height: CGFloat(h)), CGSize(width: 5000, height: 5000)] {
                        _ = prepareNativeStrip(full: img, logicalSize: logical, profile: profile, pid: 1)
                    }
                }
                runs += 1
            }
        }
        print("PASS preview-renderer-bounds: \(runs) images × every pixel function, no out-of-bounds")
    }
}
