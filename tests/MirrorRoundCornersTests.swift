import Cocoa

// 规格 H1：mirrorRoundCorners 的提速版与旧的逐像素全扫版逐字节相同，并给出前后耗时。
// 下面这个 referenceMirrorRoundCorners 是 2026-10-15 改动前的原文（只改了函数名）。
func referenceMirrorRoundCorners(_ image: CGImage) -> CGImage? {
    let w = image.width, h = image.height
    guard w > 0, h > 0 else { return nil }
    let bpr = w * 4
    var buf = [UInt8](repeating: 0, count: bpr * h)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    var origAlpha = [UInt8](repeating: 0, count: w * h)        // 先快照原始 alpha，避免边改边读
    for y in 0..<h { for x in 0..<w { origAlpha[y * w + x] = buf[y * bpr + x * 4 + 3] } }

    for y in 0..<h {
        let my = h - 1 - y
        for x in 0..<w {
            let aSelf = origAlpha[y * w + x]
            let aMirror = origAlpha[my * w + x]
            if aMirror < aSelf {                               // 镜像处更透明 → 把本像素也裁掉相应程度
                let i = y * bpr + x * 4
                let f = Float(aMirror) / Float(aSelf)          // 预乘 RGBA 同比缩放
                buf[i]     = UInt8(Float(buf[i])     * f)
                buf[i + 1] = UInt8(Float(buf[i + 1]) * f)
                buf[i + 2] = UInt8(Float(buf[i + 2]) * f)
                buf[i + 3] = aMirror
            }
        }
    }
    return ctx.makeImage()
}

func bytes(_ image: CGImage?) -> [UInt8]? {
    guard let image, let data = image.dataProvider?.data else { return nil }
    return Array(Data(referencing: data as NSData))
}

func image(_ w: Int, _ h: Int, _ px: (Int, Int) -> (UInt8, UInt8)) -> CGImage {
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h { for x in 0..<w {
        let (c, a) = px(x, y), i = (y * w + x) * 4
        let v = UInt8(Int(c) * Int(a) / 255)
        buf[i] = v; buf[i + 1] = v / 2; buf[i + 2] = v / 3; buf[i + 3] = a
    } }
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

/// 真实形状：顶部两角圆角缺口（半径 r），其余不透明。
func windowShot(_ w: Int, _ h: Int, r: Int) -> CGImage {
    image(w, h) { x, y in
        let c = UInt8((x * 7 + y * 13) % 256)
        guard y < r, x < r || x >= w - r else { return (c, 255) }
        let cx = x < r ? r : w - r - 1, dx = Double(x - cx), dy = Double(y - r)
        let d = (dx * dx + dy * dy).squareRoot() - Double(r)
        return (c, UInt8(max(0, min(255, (0.5 - d) * 255))))
    }
}

@main
struct MirrorRoundCornersTests {
    static func main() {
        var failures = 0
        var rng = SystemRandomNumberGenerator()
        var cases: [(String, CGImage)] = [("1x1", image(1, 1) { _, _ in (9, 128) }),
                                          ("opaque", image(50, 40) { x, _ in (UInt8(x), 255) }),
                                          ("clear", image(50, 40) { _, _ in (0, 0) }),
                                          ("window 800x600", windowShot(800, 600, r: 20))]
        for n in 0..<40 {
            let w = Int.random(in: 1...60, using: &rng), h = Int.random(in: 1...60, using: &rng)
            let opaqueBias = n % 2 == 0
            cases.append(("random \(w)x\(h)", image(w, h) { _, _ in
                (UInt8.random(in: 0...255, using: &rng),
                 opaqueBias && Bool.random(using: &rng) ? 255 : UInt8.random(in: 0...255, using: &rng))
            }))
        }
        for (name, img) in cases where bytes(mirrorRoundCorners(img)) != bytes(referenceMirrorRoundCorners(img)) {
            failures += 1; print("FAIL mirror-round-corners: \(name) 与旧实现不同")
        }
        let big = windowShot(3840, 2400, r: 24)
        func time(_ f: (CGImage) -> CGImage?) -> Double {
            var best = Double.infinity
            for _ in 0..<5 { let t = Date(); _ = f(big); best = min(best, Date().timeIntervalSince(t)) }
            return best * 1000
        }
        let old = time(referenceMirrorRoundCorners), new = time(mirrorRoundCorners)
        if bytes(mirrorRoundCorners(big)) != bytes(referenceMirrorRoundCorners(big)) { failures += 1; print("FAIL 4K 与旧实现不同") }
        print(String(format: "mirror-round-corners 3840x2400: old %.1f ms → new %.1f ms (best of 5)", old, new))
        if failures > 0 { exit(1) }
        print("PASS mirror-round-corners: \(cases.count + 1) images byte-identical to the old implementation")
    }
}
