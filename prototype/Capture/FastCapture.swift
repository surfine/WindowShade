// 快速截图：CGWindowListCreateImage。
//
// ScreenCaptureKit 的单张截图（SCScreenshotManager）每次要临时起一条流，实测 200–584ms，
// 是双击收起时最慢的一段。CGWindowListCreateImage 被 Apple 标为废弃，但仍可用（按符号
// 动态取，SDK 里不直接引用），同样只在有屏幕录制权限时工作，实测几十毫秒。
// 拿不到、或者窗口还没合成出画面（整张全透明）时返回 nil，调用方退回 ScreenCaptureKit。
// 只碰 CoreGraphics，可在任意线程调用。

import CoreGraphics
import Foundation

enum FastCapture {
    private typealias CreateImage = @convention(c) (CGRect, CGWindowListOption, CGWindowID,
                                                    CGWindowImageOption) -> Unmanaged<CGImage>?

    private static let createImage: CreateImage? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else {
            LegacyQuickCapture.reportUnavailableOnce()
            return nil
        }
        return unsafeBitCast(symbol, to: CreateImage.self)
    }()

    /// 对照测量用：设了 WINDOWSHADE_DISABLE_FAST_CAPTURE 就一律退回 ScreenCaptureKit。
    private static let disabled = ProcessInfo.processInfo.environment["WINDOWSHADE_DISABLE_FAST_CAPTURE"] != nil

    static var isAvailable: Bool { createImage != nil && !disabled }

    /// 整扇窗口，满分辨率，不含阴影；窗口被别的窗口挡住也照样截得到它自己。
    static func window(_ id: CGWindowID) -> CGImage? {
        guard !disabled, let createImage,
              let image = createImage(.null, .optionIncludingWindow, id,
                                      [.boundsIgnoreFraming, .bestResolution])?.takeRetainedValue(),
              image.width > 1, image.height > 1, hasContent(image) else { return nil }
        return image
    }

    private typealias CreateImageFromArray = @convention(c) (CGRect, CFArray, CGWindowImageOption)
        -> Unmanaged<CGImage>?

    private static let createImageFromArray: CreateImageFromArray? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let symbol = dlsym(handle, "CGWindowListCreateImageFromArray") else { return nil }
        return unsafeBitCast(symbol, to: CreateImageFromArray.self)
    }()

    /// 屏幕上这块区域（全局坐标，左上原点）现在的样子，但去掉 `excluding` 里的窗口：
    /// 其余在屏窗口（含桌面）按原来的前后顺序合成。收起动画的背景就是它。
    static func composite(excluding: Set<CGWindowID>, rect: CGRect) -> CGImage? {
        guard !disabled, let createImageFromArray, rect.width >= 1, rect.height >= 1,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let ids: [CGWindowID] = list.compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? NSNumber else { return nil }
            let id = CGWindowID(number.uint32Value)
            return excluding.contains(id) ? nil : id
        }
        guard !ids.isEmpty else { return nil }
        // 这个 CFArray 直接装窗口号（不是 CFNumber）：CGWindowListCreateImageFromArray 的约定。
        let pointers: [UnsafeRawPointer?] = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        let array = pointers.withUnsafeBufferPointer { buffer in
            CFArrayCreate(kCFAllocatorDefault,
                          UnsafeMutablePointer(mutating: buffer.baseAddress),
                          buffer.count, nil)
        }
        guard let array,
              let image = createImageFromArray(rect, array, [.bestResolution])?.takeRetainedValue(),
              image.width > 1, image.height > 1 else { return nil }
        return image
    }

    /// 窗口还没被合成时会得到一张全透明图：缩成 16×16 看有没有不透明的像素。
    static func hasContent(_ image: CGImage) -> Bool {
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
