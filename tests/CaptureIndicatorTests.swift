// 录屏胶囊清理：真实截图样本必须被清干净；没有胶囊、或者紫色是应用自己的界面时绝不改图。

import AppKit

@main
enum CaptureIndicatorTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        if !condition { failures += 1; print("FAIL: \(message)") }
    }

    static func load(_ name: String) -> CGImage {
        let url = URL(fileURLWithPath: "tests/fixtures/\(name)")
        return NSImage(contentsOf: url)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

    static func purpleCount(_ image: CGImage, scale: CGFloat) -> Int {
        let w = min(image.width, Int(CaptureIndicatorRemoval.searchSize.width * scale))
        let h = min(image.height, Int(CaptureIndicatorRemoval.searchSize.height * scale))
        var pixels = RGBAPixels(image.cropping(to: CGRect(x: 0, y: 0, width: w, height: h))!)!
        return pixels.withView { view in
            var count = 0
            for y in 0..<h { for x in 0..<w where view.isIndicatorPurple(x: x, y: y) { count += 1 } }
            return count
        }
    }

    /// 合成一条 2x 标题栏：纵向渐变底色、三颗灯，可选胶囊或整片紫色工具栏。
    static func synthetic(dark: Bool, capsule: Bool, purpleToolbar: Bool = false) -> CGImage {
        let scale: CGFloat = 2, size = CGSize(width: 600, height: 52)
        let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        let top: CGFloat = dark ? 0.20 : 0.93, bottom: CGFloat = dark ? 0.17 : 0.89
        for row in 0..<Int(size.height) {
            let t = CGFloat(row) / size.height
            let v = bottom + (top - bottom) * t
            ctx.setFillColor(CGColor(srgbRed: v, green: v, blue: v, alpha: 1))
            ctx.fill(CGRect(x: 0, y: CGFloat(row), width: size.width, height: 1))
        }
        if purpleToolbar {
            ctx.setFillColor(CGColor(srgbRed: 0.40, green: 0.30, blue: 0.85, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
        let centerY = size.height / 2
        if capsule {
            ctx.setFillColor(CGColor(srgbRed: 0.40, green: 0.38, blue: 0.90, alpha: 1))
            ctx.addPath(CGPath(roundedRect: CGRect(x: 8, y: centerY - 11, width: 72, height: 22),
                               cornerWidth: 11, cornerHeight: 11, transform: nil))
            ctx.fillPath()
        }
        for (i, color) in [(1.0, 0.37, 0.34), (1.0, 0.74, 0.18), (0.16, 0.78, 0.25)].enumerated() {
            ctx.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 14 + CGFloat(i) * 20, y: centerY - 7, width: 14, height: 14))
        }
        return ctx.makeImage()!
    }

    static func pixelBuffer(_ image: CGImage) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA, nil, &buffer)
        let b = buffer!
        CVPixelBufferLockBaseAddress(b, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(b), width: image.width, height: image.height,
                            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(b),
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        CVPixelBufferUnlockBaseAddress(b, [])
        return b
    }

    static func bufferRect(_ b: CVPixelBuffer) -> CGRect {
        CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(b), height: CVPixelBufferGetHeight(b))
    }

    static func image(_ b: CVPixelBuffer) -> CGImage {
        CVPixelBufferLockBaseAddress(b, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(b, .readOnly) }
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(b), width: CVPixelBufferGetWidth(b),
                            height: CVPixelBufferGetHeight(b), bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(b),
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)!
        return ctx.makeImage()!
    }

    static func main() {
        for name in ["capture-indicator-active@2x.png", "capture-indicator-inactive@2x.png"] {
            let image = load(name)
            expect(purpleCount(image, scale: 2) > 1000, "\(name): fixture really contains the capsule")
            guard let cleaned = CaptureIndicatorRemoval.removingIndicator(from: image, scale: 2) else {
                expect(false, "\(name): real capture indicator is detected"); continue
            }
            expect(purpleCount(cleaned, scale: 2) == 0, "\(name): no indicator purple remains")
            expect(cleaned.width == image.width && cleaned.height == image.height,
                   "\(name): image size is unchanged")
        }

        for dark in [false, true] {
            let label = dark ? "dark" : "light"
            let plain = synthetic(dark: dark, capsule: false)
            expect(CaptureIndicatorRemoval.removingIndicator(from: plain, scale: 2) == nil,
                   "\(label): a title bar with ordinary traffic lights is left untouched")
            let withCapsule = synthetic(dark: dark, capsule: true)
            guard let cleaned = CaptureIndicatorRemoval.removingIndicator(from: withCapsule, scale: 2) else {
                expect(false, "\(label): synthetic capsule is detected"); continue
            }
            expect(purpleCount(cleaned, scale: 2) == 0, "\(label): synthetic capsule is removed")
            // 胶囊中部（两灯之间）应还原成同一行的标题栏底色。
            let before = RGBAPixels(plain)!, after = RGBAPixels(cleaned)!
            let x = 2 * 72, y = 2 * 26
            let a = after.pixel(x: x, y: y), b = before.pixel(x: 2 * 120, y: y)
            let distance = abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b))
            expect(distance <= 6, "\(label): repaint matches the title bar row (distance \(distance))")
            // 胶囊外面（标题文字区域）一个像素都不动。
            let far = RGBAPixels(withCapsule)!.pixel(x: 2 * 300, y: y), farAfter = after.pixel(x: 2 * 300, y: y)
            expect(far == farAfter, "\(label): pixels outside the capsule are unchanged")
        }

        // 实时帧：胶囊取代了红绿灯。原地修补 BGRA 缓冲；有底片时灯要原样回来。
        let frame = load("capture-indicator-stream-frame@2x.png")
        let before = load("capture-indicator-before-stream@2x.png")
        expect(purpleCount(frame, scale: 2) > 1000, "stream frame fixture contains the capsule")
        expect(purpleCount(before, scale: 2) == 0, "pre-stream shot has no capsule")
        let filled = pixelBuffer(frame)
        expect(CaptureIndicatorRemoval.clean(filled, content: bufferRect(filled), scale: 2),
               "a live frame with the capsule is cleaned in place")
        expect(purpleCount(image(filled), scale: 2) == 0, "no capsule left in the cleaned live frame")
        let unchanged = pixelBuffer(before)
        expect(!CaptureIndicatorRemoval.clean(unchanged, content: bufferRect(unchanged), scale: 2),
               "a live frame without the capsule is not touched")
        if let plate = CleanPlate(image: before, scale: 2) {
            let restored = pixelBuffer(frame)
            CaptureIndicatorRemoval.clean(restored, content: bufferRect(restored), scale: 2, plate: plate)
            let out = RGBAPixels(image(restored))!, ref = RGBAPixels(before)!
            // 第一颗灯中心（约 16,16 pt）应与流开始前一样。
            let a = out.pixel(x: 32, y: 32), b = ref.pixel(x: 32, y: 32)
            let distance = abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b))
            expect(distance <= 12, "clean plate brings the traffic lights back (distance \(distance))")
            expect(purpleCount(image(restored), scale: 2) == 0, "no capsule left after pasting the plate")
        } else {
            expect(false, "a pre-stream shot is accepted as a clean plate")
        }
        expect(CleanPlate(image: frame, scale: 2) == nil, "a frame that still shows the capsule is refused as a plate")

        let toolbar = synthetic(dark: false, capsule: false, purpleToolbar: true)
        expect(CaptureIndicatorRemoval.removingIndicator(from: toolbar, scale: 2) == nil,
               "an app whose own title bar is purple is left untouched")

        if failures == 0 {
            print("PASS: capture indicator removed from real strip samples and live frames, clean plate restores the lights; plain, dark and purple-toolbar title bars untouched")
        } else {
            print("FAILED: \(failures) capture indicator checks")
            exit(1)
        }
    }
}
