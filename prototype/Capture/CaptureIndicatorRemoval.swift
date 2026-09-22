// 抹掉截图里的系统录屏指示器。
//
// macOS 26 会在“正被捕获的窗口”的红绿灯处画一个蓝紫色胶囊（包住三颗灯，右侧带一个
// 录屏图标）。收起窗口时我们恰恰要捕获它，于是胶囊常被截进原貌卷帘条和悬停预览里。
// 卷帘条上的红绿灯本来就是叠在截图上的真实 AppKit 按钮，所以只要把截图里胶囊那一块
// 还原成标题栏底色，按钮就落在干净的背景上，悬停符号、激活/非激活状态都由系统绘制。
//
// 只在确实检测到胶囊时才改图：位置在左上角红绿灯区域、颜色是指示器的蓝紫色、形状像
// 一颗胶囊（尺寸与红绿灯组相称、没有铺满整个检测区域）。其余截图原样返回 nil。
// 纯 CPU 计算，不碰 AppKit，可在任意线程调用。

import CoreGraphics
import Foundation

enum CaptureIndicatorRemoval {
    /// 检测区域：窗口左上角 170 × 64 pt，覆盖各种标题栏高度下的红绿灯组。
    static let searchSize = CGSize(width: 170, height: 64)

    struct Detection: Equatable {
        /// 胶囊外接矩形（像素，左上原点），已向外扩出抗锯齿边缘。
        let bounds: CGRect
        let purplePixels: Int
    }

    /// 返回清理后的新图；没有检测到胶囊时返回 nil（调用方继续用原图）。
    static func removingIndicator(from image: CGImage, scale: CGFloat) -> CGImage? {
        guard let detection = detect(in: image, scale: scale) else { return nil }
        return repaint(image, clearing: detection.bounds)
    }

    static func detect(in image: CGImage, scale: CGFloat) -> Detection? {
        let scale = max(1, scale)
        let width = min(image.width, Int(searchSize.width * scale))
        let height = min(image.height, Int(searchSize.height * scale))
        guard width > 8, height > 8,
              let region = image.cropping(to: CGRect(x: 0, y: 0, width: width, height: height)),
              let pixels = RGBAPixels(region) else { return nil }

        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1, count = 0
        for y in 0..<height {
            for x in 0..<width where pixels.isIndicatorPurple(x: x, y: y) {
                count += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard count > 0 else { return nil }
        let box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        let points = CGSize(width: box.width / scale, height: box.height / scale)
        // 形状：胶囊包住三颗 12–14 pt 的灯再加一个图标，宽约 60–120 pt、高约 16–34 pt；
        // 左缘贴近窗口左边；不能碰到检测区域的右/下边（那说明是整片紫色的工具栏）。
        guard (36...140).contains(points.width),
              (12...36).contains(points.height),
              box.minX / scale <= 24,
              maxX < width - 1, maxY < height - 1 else { return nil }
        // 胶囊内部有灯和图标，紫色像素不会铺满外接矩形，但也不会只是零星几点。
        let fill = Double(count) / Double(box.width * box.height)
        guard fill >= 0.25 else { return nil }
        // 胶囊外圈有一层淡淡的光晕（饱和度低，不算“紫色”），多扩 3 pt 一并盖住。
        let pad = ceil(3 * scale)
        let padded = box.insetBy(dx: -pad, dy: -pad)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Detection(bounds: padded.integral, purplePixels: count)
    }

    /// 逐行用胶囊两侧的标题栏像素填回去：标题栏只有纵向渐变，逐行取样能保住它。
    /// 每侧取几个像素求平均、再在纵向上轻微平滑，避免单个像素的噪点变成横纹。
    static func repaint(_ image: CGImage, clearing rect: CGRect) -> CGImage? {
        guard var pixels = RGBAPixels(image) else { return nil }
        let minX = max(0, Int(rect.minX)), maxX = min(pixels.width - 1, Int(rect.maxX) - 1)
        let minY = max(0, Int(rect.minY)), maxY = min(pixels.height - 1, Int(rect.maxY) - 1)
        guard minX <= maxX, minY <= maxY else { return nil }
        let reach = 2, band = 4
        var rows: [RGBAPixels.Pixel?] = []
        for y in minY...maxY {
            let left = pixels.averageSample(xs: (minX - reach - band + 1)...(minX - reach), y: y)
            let right = pixels.averageSample(xs: (maxX + reach)...(maxX + reach + band - 1), y: y)
            // 左侧是窗口边缘与第一颗灯之间的空白，最可能是纯标题栏；右侧可能紧挨工具栏按钮。
            // 两侧接近时取平均，否则优先左侧。
            rows.append(RGBAPixels.blend(left, right))
        }
        for (offset, y) in (minY...maxY).enumerated() {
            let window = rows[max(0, offset - 2)...min(rows.count - 1, offset + 2)].compactMap { $0 }
            guard let fill = RGBAPixels.average(window) else { continue }
            for x in minX...maxX { pixels.set(x: x, y: y, fill) }
        }
        return pixels.makeImage(colorSpace: image.colorSpace)
    }
}

/// 8 位 RGBA（预乘）像素缓冲，行从图像顶部开始。
struct RGBAPixels {
    typealias Pixel = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
    let width: Int
    let height: Int
    private(set) var bytes: [UInt8]
    private let space: CGColorSpace

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
    }

    func pixel(x: Int, y: Int) -> Pixel {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    mutating func set(x: Int, y: Int, _ p: Pixel) {
        let i = (y * width + x) * 4
        bytes[i] = p.r; bytes[i + 1] = p.g; bytes[i + 2] = p.b; bytes[i + 3] = p.a
    }

    /// 录屏指示器的蓝紫色：色相约 225°–270°、饱和度与亮度都不低。
    /// 普通标题栏（灰、白、深色、半透明材质）和三颗灯（红黄绿）都不落在这个范围。
    func isIndicatorPurple(x: Int, y: Int) -> Bool {
        let p = pixel(x: x, y: y)
        guard p.a > 200 else { return false }
        let r = Double(p.r) / 255, g = Double(p.g) / 255, b = Double(p.b) / 255
        let maxC = max(r, g, b), minC = min(r, g, b)
        guard maxC == b, maxC >= 0.45 else { return false }
        let delta = maxC - minC
        let saturation = delta / maxC
        guard saturation >= 0.35 else { return false }
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
        RGBAPixels.average(xs.compactMap { opaqueSample(x: $0, y: y) })
    }

    static func average(_ samples: [Pixel]) -> Pixel? {
        guard !samples.isEmpty else { return nil }
        let n = samples.count
        return (UInt8(samples.reduce(0) { $0 + Int($1.r) } / n),
                UInt8(samples.reduce(0) { $0 + Int($1.g) } / n),
                UInt8(samples.reduce(0) { $0 + Int($1.b) } / n), 255)
    }

    static func blend(_ left: Pixel?, _ right: Pixel?) -> Pixel? {
        switch (left, right) {
        case let (l?, r?):
            let distance = abs(Int(l.r) - Int(r.r)) + abs(Int(l.g) - Int(r.g)) + abs(Int(l.b) - Int(r.b))
            guard distance <= 24 else { return l }
            return (UInt8((Int(l.r) + Int(r.r)) / 2), UInt8((Int(l.g) + Int(r.g)) / 2),
                    UInt8((Int(l.b) + Int(r.b)) / 2), 255)
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }

    func makeImage(colorSpace: CGColorSpace?) -> CGImage? {
        var copy = bytes
        return copy.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return context.makeImage()
        }
    }
}
