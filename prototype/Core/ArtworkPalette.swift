// 封面取色（设计稿《正在播放》“封面取色”算法卡）。纯函数，只依赖 Foundation：
// 不碰 AppKit、不读时钟、不落盘；同一份像素永远得到同一份结果。
//
// 输入：64 × 64 的 RGBA（每像素 4 字节，非预乘；预乘的缓冲先过 `unpremultiplied`）。
// 步骤：
// 1. 转 OKLCH，丢掉透明度 < 0.5、明度 L < 0.18 或 > 0.96、彩度 C < 0.035 的像素（太黑、太白、太灰不投票）。
// 2. 剩下的按色相分 16 桶（每桶 22.5°），每个像素投它的彩度 C。
//    留下的像素不到全部的 8% 就当这张封面没有颜色，一律用白 0.92（和刘海上的主文字同色）。
// 3. 票最多的桶是主色，取桶内按彩度加权的平均。副色是和主色色相差 ≥ 45°、票数 ≥ 主色 25% 的最高桶；
//    没有就用主色提亮 0.1。
// 4. 字色（歌手名）：L 夹到 0.74–0.92，C 最多 0.14。填充色（进度、波形、音量条）：L 夹到 0.66–0.90，
//    C 最多 0.17。超出 sRGB 时只降彩度，不改色相和明度。

import Foundation

/// OKLCH：L 明度 0...1，C 彩度（sRGB 内大约 0...0.4），h 色相角 0..<360。
struct OKLCH: Sendable, Equatable {
    var l: Double
    var c: Double
    var h: Double
}

/// sRGB，各分量 0...1（已做 gamma 编码，可直接交给 NSColor / CGColor）。
struct ArtworkRGB: Sendable, Equatable {
    var r: Double
    var g: Double
    var b: Double

    /// WCAG 相对亮度。
    var relativeLuminance: Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// 放在纯黑上的 WCAG 对比度（1...21）。
    var contrastAgainstBlack: Double { (relativeLuminance + 0.05) / 0.05 }
}

struct ArtworkPalette: Sendable, Equatable {
    /// 这张封面有没有可用的颜色；false 时三种颜色都是白 0.92。
    let hasColor: Bool
    /// 主色、副色的原始 OKLCH（没夹之前）。无色时都是 L 0.92、C 0。
    let primary: OKLCH
    let secondary: OKLCH
    /// 歌手名用。
    let text: ArtworkRGB
    /// 进度、波形、音量条用（主色）。
    let fill: ArtworkRGB
    /// 波形等需要交替两种颜色时用的副色填充。
    let secondaryFill: ArtworkRGB

    // MARK: 数字（都来自设计稿）

    static let side = 64
    static let hueBucketCount = 16
    static let minAlpha = 0.5
    static let minLightness = 0.18
    static let maxLightness = 0.96
    static let minChroma = 0.035
    /// 留下的像素占全部像素的比例低于它，就当没有颜色。
    static let minKeptFraction = 0.08
    static let secondaryMinHueGap = 45.0
    static let secondaryMinVoteFraction = 0.25
    static let secondaryLift = 0.1
    static let textLightness: ClosedRange<Double> = 0.74...0.92
    static let textMaxChroma = 0.14
    static let fillLightness: ClosedRange<Double> = 0.66...0.90
    static let fillMaxChroma = 0.17
    static let neutralLightness = 0.92

    /// 没有颜色（灰图、纯黑纯白、透明、尺寸不对）时的结果：白 0.92。
    static let neutral: ArtworkPalette = {
        let gray = OKLCH(l: neutralLightness, c: 0, h: 0)
        let rgb = fitToSRGB(gray)
        return ArtworkPalette(hasColor: false, primary: gray, secondary: gray, text: rgb, fill: rgb, secondaryFill: rgb)
    }()

    // MARK: 取色

    /// `rgba` 是 `width × height` 的非预乘 RGBA；长度对不上就当没有颜色。
    static func make(rgba: [UInt8], width: Int = side, height: Int = side) -> ArtworkPalette {
        let total = width * height
        guard width > 0, height > 0, rgba.count == total * 4 else { return neutral }

        struct Bucket { var votes = 0.0; var l = 0.0; var a = 0.0; var b = 0.0 }
        var buckets = [Bucket](repeating: Bucket(), count: hueBucketCount)
        var kept = 0
        let bucketWidth = 360.0 / Double(hueBucketCount)

        for index in 0..<total {
            let offset = index * 4
            guard Double(rgba[offset + 3]) / 255 >= minAlpha else { continue }
            let lab = oklab(r: srgbToLinear[Int(rgba[offset])], g: srgbToLinear[Int(rgba[offset + 1])],
                            b: srgbToLinear[Int(rgba[offset + 2])])
            guard lab.l >= minLightness, lab.l <= maxLightness else { continue }
            let chroma = hypot(lab.a, lab.b)
            guard chroma >= minChroma else { continue }
            var hue = atan2(lab.b, lab.a) * 180 / .pi
            if hue < 0 { hue += 360 }
            let slot = min(hueBucketCount - 1, Int(hue / bucketWidth))
            buckets[slot].votes += chroma
            buckets[slot].l += lab.l * chroma
            buckets[slot].a += lab.a * chroma
            buckets[slot].b += lab.b * chroma
            kept += 1
        }

        guard Double(kept) >= Double(total) * minKeptFraction else { return neutral }

        func average(_ bucket: Bucket) -> OKLCH {
            let l = bucket.l / bucket.votes
            let a = bucket.a / bucket.votes
            let b = bucket.b / bucket.votes
            var hue = atan2(b, a) * 180 / .pi
            if hue < 0 { hue += 360 }
            return OKLCH(l: l, c: hypot(a, b), h: hue)
        }

        // 票数相同取序号小的，保证结果稳定。
        var best = 0
        for slot in 1..<hueBucketCount where buckets[slot].votes > buckets[best].votes { best = slot }
        guard buckets[best].votes > 0 else { return neutral }
        let primary = average(buckets[best])

        var secondaryIndex: Int?
        for slot in 0..<hueBucketCount where slot != best && buckets[slot].votes > 0 {
            guard buckets[slot].votes >= buckets[best].votes * secondaryMinVoteFraction else { continue }
            guard hueDistance(average(buckets[slot]).h, primary.h) >= secondaryMinHueGap else { continue }
            if secondaryIndex == nil || buckets[slot].votes > buckets[secondaryIndex!].votes { secondaryIndex = slot }
        }
        let secondary = secondaryIndex.map { average(buckets[$0]) }
            ?? OKLCH(l: min(1, primary.l + secondaryLift), c: primary.c, h: primary.h)

        return ArtworkPalette(
            hasColor: true, primary: primary, secondary: secondary,
            text: fitToSRGB(clamped(primary, lightness: textLightness, maxChroma: textMaxChroma)),
            fill: fitToSRGB(clamped(primary, lightness: fillLightness, maxChroma: fillMaxChroma)),
            secondaryFill: fitToSRGB(clamped(secondary, lightness: fillLightness, maxChroma: fillMaxChroma)))
    }

    /// 预乘 RGBA（CGContext 默认给的）还原成非预乘；透明度为 0 的像素颜色清零。
    static func unpremultiplied(_ rgba: [UInt8]) -> [UInt8] {
        var out = rgba
        var offset = 0
        while offset + 3 < out.count {
            let alpha = Int(out[offset + 3])
            if alpha == 0 {
                out[offset] = 0; out[offset + 1] = 0; out[offset + 2] = 0
            } else if alpha < 255 {
                for channel in 0..<3 {
                    out[offset + channel] = UInt8(min(255, (Int(out[offset + channel]) * 255 + alpha / 2) / alpha))
                }
            }
            offset += 4
        }
        return out
    }

    /// 同一份像素的指纹（FNV-1a 64 位）：换曲时同一张封面不重算，按它做缓存键。
    static func fingerprint(of rgba: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in rgba {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    // MARK: 颜色数学

    private static func clamped(_ color: OKLCH, lightness: ClosedRange<Double>, maxChroma: Double) -> OKLCH {
        OKLCH(l: min(lightness.upperBound, max(lightness.lowerBound, color.l)),
              c: min(maxChroma, max(0, color.c)), h: color.h)
    }

    private static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    /// 8 位 sRGB 通道 → 线性值。
    private static let srgbToLinear: [Double] = (0...255).map { value in
        let v = Double(value) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func oklab(r: Double, g: Double, b: Double) -> (l: Double, a: Double, b: Double) {
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// OKLCH → 线性 sRGB（可能超出 0...1）。
    private static func linearRGB(_ color: OKLCH) -> (r: Double, g: Double, b: Double) {
        let radians = color.h * .pi / 180
        let a = color.c * cos(radians)
        let b = color.c * sin(radians)
        let l = pow(color.l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(color.l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(color.l - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    private static func inGamut(_ c: (r: Double, g: Double, b: Double)) -> Bool {
        let slack = 1e-6
        return c.r >= -slack && c.r <= 1 + slack && c.g >= -slack && c.g <= 1 + slack && c.b >= -slack && c.b <= 1 + slack
    }

    /// 超出 sRGB 时只降彩度（二分），不改色相和明度。
    static func fitToSRGB(_ color: OKLCH) -> ArtworkRGB {
        var candidate = color
        if !inGamut(linearRGB(candidate)) {
            var low = 0.0, high = max(0, color.c)
            for _ in 0..<24 {
                let mid = (low + high) / 2
                candidate.c = mid
                if inGamut(linearRGB(candidate)) { low = mid } else { high = mid }
            }
            candidate.c = low
        }
        let linear = linearRGB(candidate)
        func encode(_ v: Double) -> Double {
            let clamped = min(1, max(0, v))
            return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        }
        return ArtworkRGB(r: encode(linear.r), g: encode(linear.g), b: encode(linear.b))
    }
}
