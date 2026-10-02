// 窗口快照：CGSHWCaptureWindowList。
//
// CGWindowListCreateImage（FastCapture）对最小化的窗口、被隐藏的 App 的窗口直接返回 nil；这个私有函数
// 由窗口服务器自己给出窗口此刻的画面，最小化、App 被隐藏、窗口在别的桌面上时都拿得到
// （AltTab、DockDoor 用的同一个；本机 macOS 27 实测跨进程 31–135ms，不点亮录屏指示）。
// 拿到的是 App 最后画的那一帧：最小化、隐藏的 App 多半已经不再画，所以调用方一律标“不是实时画面”。
// 按符号动态取，SDK 里不直接引用；设了 WINDOWSHADE_DISABLE_WINDOW_SNAPSHOT 就当不可用（探针测兜底用）。
// 拿不到、没有屏幕录制权限、窗口已经没了、或者画面整张全透明（保护窗口、动画中间帧）时返回 nil。
// 只碰 CoreGraphics，可在任意线程调用。

import CoreGraphics
import Foundation

nonisolated enum WindowSnapshot {
    enum Quality {
        /// 标称（1x）分辨率。
        case thumbnail
        /// 能拿到的最好分辨率。
        case full
    }

    // 私有符号签名：连接号，以及“连窗口列表一起截一张图”。
    private typealias ConnectionFunction = @convention(c) () -> Int32
    // Copy 规则：返回的数组是 +1，按 Unmanaged 接住再 takeRetainedValue，不然每次调用都漏一个。
    private typealias CaptureFunction = @convention(c) (Int32, UnsafeMutablePointer<CGWindowID>, UInt32,
                                                         UInt32) -> Unmanaged<CFArray>?

    // CGSHWCaptureWindowList 的选项位。ignoreGlobalClipShape 让它不管窗口当前被裁剪成什么样，
    // fullSize 让它按窗口原始大小出图（不然最小化的窗口会缩成一张很小的图）。
    private static let ignoreGlobalClipShape: UInt32 = 1 << 11
    private static let nominalResolution: UInt32 = 1 << 9
    private static let bestResolution: UInt32 = 1 << 8
    private static let fullSize: UInt32 = 1 << 19

    private static let symbols: (connection: ConnectionFunction, capture: CaptureFunction)? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let captureSymbol = dlsym(handle, "CGSHWCaptureWindowList"),
              let capture = unsafeBitCast(captureSymbol, to: CaptureFunction?.self) else { return nil }
        // 连接函数先试 CGSMainConnectionID，没有再退回旧的 _CGSDefaultConnection。
        guard let connectionSymbol = dlsym(handle, "CGSMainConnectionID")
                ?? dlsym(handle, "_CGSDefaultConnection"),
              let connection = unsafeBitCast(connectionSymbol, to: ConnectionFunction?.self) else { return nil }
        return (connection, capture)
    }()

    private static let disabled = ProcessInfo.processInfo.environment["WINDOWSHADE_DISABLE_WINDOW_SNAPSHOT"] != nil

    static var isAvailable: Bool { symbols != nil && !disabled }

    /// 一扇窗口现在的样子，最小化、App 被隐藏、在别的桌面上时也拿得到。
    /// 私有函数缺失、没有屏幕录制权限、窗口已经没了、画面全透明（保护窗口、动画中间帧）时返回 nil。
    static func image(_ id: CGWindowID, quality: Quality) -> CGImage? {
        // 先问有没有屏幕录制权限（只问，不弹授权框）：没有就不碰私有函数。
        guard !disabled, let symbols, CGPreflightScreenCaptureAccess() else { return nil }
        let options = ignoreGlobalClipShape | fullSize
            | (quality == .full ? bestResolution : nominalResolution)
        var window = id
        guard let raw = symbols.capture(symbols.connection(), &window, 1, options)?.takeRetainedValue(),
              let image = (raw as? [CGImage])?.first else { return nil }
        // 太小的图不是画面，是全透明占位。
        guard image.width > 1, image.height > 1, hasContent(image) else { return nil }
        return image
    }

    /// 缩到最长边不超过 maxPixel（格子上的小图）；本来就够小的原样返回。任意线程可调。
    static func downscaled(_ image: CGImage, maxPixel: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxPixel, maxPixel > 0 else { return image }
        let scale = CGFloat(maxPixel) / CGFloat(longest)
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// 窗口还没被合成时会得到一张全透明图：缩成 16×16 的网格看有没有不透明的像素。
    private static func hasContent(_ image: CGImage) -> Bool {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 8 }
    }
}
