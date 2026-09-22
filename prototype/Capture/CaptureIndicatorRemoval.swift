// 抹掉画面里的系统录屏指示器。
//
// macOS 26 在“正被流式捕获的窗口”的红绿灯处画一个蓝紫色胶囊（带录屏图标）。单张截图
// 本身不会触发它，但只要这扇窗上还开着一条捕获流（收起动画、置顶预览、窗口浏览实时预览），
// 流里的每一帧、以及同时截的单张图里都有它；在帧里它取代了红绿灯，灯根本不在画面上。
//
// 两种修法：
// - 抹平：用胶囊两侧的标题栏像素逐行填回去。原貌卷帘条上面叠着真实的 AppKit 按钮，
//   抹平就够了；收起动画那几百毫秒、窗口浏览的小预览也只抹平。
// - 底片：置顶预览开流之前先截一张（此时还没有胶囊），之后每帧把底片上同一位置那一块
//   贴回去，红绿灯原样回来。
//
// 只在确实检测到胶囊时才动：位置在左上角红绿灯区域、颜色是指示器的蓝紫色、形状像
// 一颗胶囊（尺寸与红绿灯组相称、没有铺满整个检测区域）。其余画面一个像素都不改。
// 纯 CPU 计算，不碰 AppKit，可在任意线程调用。

import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

enum CaptureIndicatorRemoval {
    /// 检测区域：内容左上角 170 × 64 pt，覆盖各种标题栏高度下的红绿灯组。
    static let searchSize = CGSize(width: 170, height: 64)

    struct Detection: Equatable {
        /// 需要修补的矩形（像素，左上原点，相对整块缓冲），已向外扩出光晕。
        let bounds: CGRect
        let purplePixels: Int
    }

    // MARK: 单张图（卷帘条、悬停预览）

    /// 返回清理后的新图；没有检测到胶囊时返回 nil（调用方继续用原图）。
    static func removingIndicator(from image: CGImage, scale: CGFloat) -> CGImage? {
        guard var pixels = RGBAPixels(image) else { return nil }
        let changed = pixels.withView { view in
            guard let found = detect(in: view, origin: .zero, scale: scale) else { return false }
            fill(view, rect: found.bounds)
            return true
        }
        return changed ? pixels.makeImage() : nil
    }

    static func detect(in image: CGImage, scale: CGFloat) -> Detection? {
        guard var pixels = RGBAPixels(image) else { return nil }
        return pixels.withView { detect(in: $0, origin: .zero, scale: scale) }
    }

    // MARK: 捕获流的一帧（原地修改）

    /// 在一帧 32BGRA 缓冲上原地修补。`content` 是窗口内容在缓冲里的像素矩形（SCK 可能
    /// 在四周留白），`scale` 是每 pt 的像素数。有底片时贴底片，否则抹平。返回是否改动。
    @discardableResult
    static func clean(_ buffer: CVPixelBuffer, content: CGRect, scale: CGFloat,
                      plate: CleanPlate? = nil) -> Bool {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return false }
        let view = PixelView(base: base.assumingMemoryBound(to: UInt8.self),
                             width: CVPixelBufferGetWidth(buffer),
                             height: CVPixelBufferGetHeight(buffer),
                             bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), order: .bgra)
        let origin = CGPoint(x: max(0, content.minX.rounded()), y: max(0, content.minY.rounded()))
        guard let found = detect(in: view, origin: origin, scale: scale) else { return false }
        if let plate, plate.paste(into: view, rect: found.bounds, contentOrigin: origin, scale: scale) {
            return true
        }
        fill(view, rect: found.bounds)
        return true
    }

    /// 直接处理 ScreenCaptureKit 的一帧：从帧信息里取内容区域与缩放比例。
    @discardableResult
    static func clean(_ sample: CMSampleBuffer, plate: CleanPlate? = nil) -> Bool {
        guard let buffer = sample.imageBuffer,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first else { return false }
        let scale = (info[.scaleFactor] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 1
        var content = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer),
                             height: CVPixelBufferGetHeight(buffer))
        if let dict = info[.contentRect] as? [String: Any],
           let rect = CGRect(dictionaryRepresentation: dict as CFDictionary), !rect.isEmpty {
            content = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                             width: rect.width * scale, height: rect.height * scale)
        }
        return clean(buffer, content: content, scale: scale, plate: plate)
    }

    // MARK: 检测与抹平

    static func detect(in view: PixelView, origin: CGPoint, scale: CGFloat) -> Detection? {
        // 缩略图每 pt 可能不到 1 个像素；按实际比例换算尺寸，只挡住离谱的值。
        let scale = max(0.25, scale)
        let x0 = Int(origin.x), y0 = Int(origin.y)
        let width = min(view.width - x0, Int(searchSize.width * scale))
        let height = min(view.height - y0, Int(searchSize.height * scale))
        guard width > 8, height > 8 else { return nil }

        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1, count = 0
        for y in 0..<height {
            for x in 0..<width where view.isIndicatorPurple(x: x0 + x, y: y0 + y) {
                count += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard count > 0 else { return nil }
        let box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        let points = CGSize(width: box.width / scale, height: box.height / scale)
        // 形状：胶囊宽约 60–120 pt、高约 16–34 pt；左缘贴近窗口左边；
        // 不能碰到检测区域的右/下边（那说明是整片紫色的工具栏）。
        guard (36...140).contains(points.width),
              (12...36).contains(points.height),
              box.minX / scale <= 24,
              maxX < width - 1, maxY < height - 1 else { return nil }
        // 胶囊里有图标（卷帘条样本里还有灯），紫色不会铺满外接矩形，但也不会只是零星几点。
        let fill = Double(count) / Double(box.width * box.height)
        guard fill >= 0.25 else { return nil }
        // 胶囊外圈有一层淡淡的光晕（饱和度低，不算“紫色”），多扩 3 pt 一并盖住。
        let pad = ceil(3 * scale)
        let padded = box.offsetBy(dx: CGFloat(x0), dy: CGFloat(y0)).insetBy(dx: -pad, dy: -pad)
            .intersection(CGRect(x: 0, y: 0, width: view.width, height: view.height))
        return Detection(bounds: padded.integral, purplePixels: count)
    }

    /// 逐行用胶囊两侧的标题栏像素填回去：标题栏只有纵向渐变，逐行取样能保住它。
    /// 每侧取几个像素求平均、再在纵向上轻微平滑，避免单个像素的噪点变成横纹。
    static func fill(_ view: PixelView, rect: CGRect) {
        let minX = max(0, Int(rect.minX)), maxX = min(view.width - 1, Int(rect.maxX) - 1)
        let minY = max(0, Int(rect.minY)), maxY = min(view.height - 1, Int(rect.maxY) - 1)
        guard minX <= maxX, minY <= maxY else { return }
        let reach = 2, band = 4
        var rows: [Pixel?] = []
        for y in minY...maxY {
            let left = view.averageSample(xs: (minX - reach - band + 1)...(minX - reach), y: y)
            let right = view.averageSample(xs: (maxX + reach)...(maxX + reach + band - 1), y: y)
            // 左侧是窗口边缘与胶囊之间的空白，最可能是纯标题栏；右侧可能紧挨工具栏按钮。
            // 两侧接近时取平均，否则优先左侧。
            rows.append(Pixel.blend(left, right))
        }
        for (offset, y) in (minY...maxY).enumerated() {
            let window = rows[max(0, offset - 2)...min(rows.count - 1, offset + 2)].compactMap { $0 }
            guard let fill = Pixel.average(window) else { continue }
            for x in minX...maxX { view.set(x: x, y: y, fill) }
        }
    }
}

/// 置顶预览开流前截的一张干净画面（还没有胶囊）。只保留左上角红绿灯那一块。
final class CleanPlate: @unchecked Sendable {
    private var pixels: RGBAPixels
    /// 底片每 pt 的像素数。
    let scale: CGFloat

    init?(image: CGImage, scale: CGFloat) {
        let size = CaptureIndicatorRemoval.searchSize
        let rect = CGRect(x: 0, y: 0, width: min(CGFloat(image.width), size.width * scale),
                          height: min(CGFloat(image.height), size.height * scale))
        guard let crop = image.cropping(to: rect.integral), var pixels = RGBAPixels(crop),
              pixels.withView({ CaptureIndicatorRemoval.detect(in: $0, origin: .zero, scale: scale) }) == nil
        else { return nil }
        self.pixels = pixels
        self.scale = scale
    }

    /// 把底片上与 `rect`（帧像素）对应的那一块贴进帧里。比例不同时按最近邻换算。
    /// 底片覆盖不到这块时返回 false，调用方退回抹平。
    func paste(into view: PixelView, rect: CGRect, contentOrigin: CGPoint, scale: CGFloat) -> Bool {
        let ratio = self.scale / max(1, scale)
        let minX = max(0, Int(rect.minX)), maxX = min(view.width - 1, Int(rect.maxX) - 1)
        let minY = max(0, Int(rect.minY)), maxY = min(view.height - 1, Int(rect.maxY) - 1)
        guard minX <= maxX, minY <= maxY else { return false }
        let plateMaxX = Int((CGFloat(maxX) - contentOrigin.x) * ratio)
        let plateMaxY = Int((CGFloat(maxY) - contentOrigin.y) * ratio)
        guard plateMaxX < pixels.width, plateMaxY < pixels.height else { return false }
        return pixels.withView { plate in
            for y in minY...maxY {
                let py = Int((CGFloat(y) - contentOrigin.y) * ratio)
                guard py >= 0 else { continue }
                for x in minX...maxX {
                    let px = Int((CGFloat(x) - contentOrigin.x) * ratio)
                    guard px >= 0 else { continue }
                    let p = plate.pixel(x: px, y: py)
                    // 底片圆角处透明：保留帧里原来的像素。
                    if p.a == 255 { view.set(x: x, y: y, p) }
                }
            }
            return true
        }
    }
}

struct Pixel: Equatable {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8

    static func average(_ samples: [Pixel]) -> Pixel? {
        guard !samples.isEmpty else { return nil }
        let n = samples.count
        return Pixel(r: UInt8(samples.reduce(0) { $0 + Int($1.r) } / n),
                     g: UInt8(samples.reduce(0) { $0 + Int($1.g) } / n),
                     b: UInt8(samples.reduce(0) { $0 + Int($1.b) } / n), a: 255)
    }

    static func blend(_ left: Pixel?, _ right: Pixel?) -> Pixel? {
        switch (left, right) {
        case let (l?, r?):
            let distance = abs(Int(l.r) - Int(r.r)) + abs(Int(l.g) - Int(r.g)) + abs(Int(l.b) - Int(r.b))
            guard distance <= 24 else { return l }
            return average([l, r])
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }
}

/// 一块 8 位四通道像素内存的视图（不持有内存），行从顶部开始。
struct PixelView {
    enum Order { case rgba, bgra }
    let base: UnsafeMutablePointer<UInt8>
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let order: Order

    func pixel(x: Int, y: Int) -> Pixel {
        let p = base + y * bytesPerRow + x * 4
        switch order {
        case .rgba: return Pixel(r: p[0], g: p[1], b: p[2], a: p[3])
        case .bgra: return Pixel(r: p[2], g: p[1], b: p[0], a: p[3])
        }
    }

    func set(x: Int, y: Int, _ v: Pixel) {
        let p = base + y * bytesPerRow + x * 4
        switch order {
        case .rgba: p[0] = v.r; p[1] = v.g; p[2] = v.b; p[3] = v.a
        case .bgra: p[0] = v.b; p[1] = v.g; p[2] = v.r; p[3] = v.a
        }
    }

    /// 录屏指示器的蓝紫色：色相约 225°–270°、饱和度与亮度都不低。
    /// 普通标题栏（灰、白、深色、半透明材质）和三颗灯（红黄绿）都不落在这个范围。
    func isIndicatorPurple(x: Int, y: Int) -> Bool {
        let p = pixel(x: x, y: y)
        guard p.a > 200, p.b >= p.r, p.b >= p.g, p.b >= 115 else { return false }
        let r = Double(p.r), g = Double(p.g), b = Double(p.b)
        let delta = b - min(r, g)
        guard delta / b >= 0.35 else { return false }
        var hue = 60 * ((r - g) / delta) + 240
        if hue < 0 { hue += 360 }
        return (225...270).contains(hue)
    }

    /// 不透明且不是指示器颜色的像素（越界、圆角透明处、仍是紫色时返回 nil）。
    func opaqueSample(x: Int, y: Int) -> Pixel? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let p = pixel(x: x, y: y)
        guard p.a == 255, !isIndicatorPurple(x: x, y: y) else { return nil }
        return p
    }

    func averageSample(xs: ClosedRange<Int>, y: Int) -> Pixel? {
        Pixel.average(xs.compactMap { opaqueSample(x: $0, y: y) })
    }
}

/// 自己持有内存的 8 位 RGBA（预乘）像素，用于单张 CGImage。
struct RGBAPixels {
    let width: Int
    let height: Int
    private var bytes: [UInt8]
    private let space: CGColorSpace

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let (w, h, s) = (width, height, space)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: s,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
    }

    mutating func withView<T>(_ body: (PixelView) -> T) -> T {
        let (w, h) = (width, height)
        return bytes.withUnsafeMutableBytes { buffer in
            body(PixelView(base: buffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                           width: w, height: h, bytesPerRow: w * 4, order: .rgba))
        }
    }

    func pixel(x: Int, y: Int) -> Pixel {
        let i = (y * width + x) * 4
        return Pixel(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3])
    }

    func makeImage() -> CGImage? {
        var copy = bytes
        let (w, h, s) = (width, height, space)
        return copy.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: s,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return context.makeImage()
        }
    }
}
