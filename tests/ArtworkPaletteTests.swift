// 封面取色与封面取得（设计稿《正在播放》NP-1）：纯逻辑测试，无权限、无 UI、不启动子进程、不读真实播放。

import Cocoa
import ImageIO
import UniformTypeIdentifiers

@main struct ArtworkPaletteTests {
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, "断言失败: \(message)")
    }

    /// 64 × 64 纯色（非预乘，alpha 255）。
    static func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, alpha: UInt8 = 255, count: Int = 4096) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(count * 4)
        for _ in 0..<count { out += [r, g, b, alpha] }
        return out
    }

    /// 前 `first` 个像素用一种颜色，其余用另一种。
    static func split(_ a: (UInt8, UInt8, UInt8), count first: Int, _ b: (UInt8, UInt8, UInt8)) -> [UInt8] {
        var out: [UInt8] = []
        for index in 0..<4096 {
            let c = index < first ? a : b
            out += [c.0, c.1, c.2, 255]
        }
        return out
    }

    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    static func main() {
        testStable()
        testNeutralCases()
        testThresholdsAndFraction()
        testPrimaryAndSecondary()
        testClampsAndContrast()
        testUnpremultiplyAndFingerprint()
        testPayload()
        testDecoder()
        print("PASS artwork-palette")
    }

    static func testStable() {
        var pixels: [UInt8] = []
        for index in 0..<4096 {
            pixels += [UInt8((index * 7) % 256), UInt8((index * 13 + 40) % 256), UInt8((index * 29) % 256), 255]
        }
        let first = ArtworkPalette.make(rgba: pixels)
        for _ in 0..<5 { expect(ArtworkPalette.make(rgba: pixels) == first, "同一张图结果不变") }
        expect(ArtworkPalette.fingerprint(of: pixels) == ArtworkPalette.fingerprint(of: pixels), "指纹稳定")
    }

    static func testNeutralCases() {
        let neutral = ArtworkPalette.neutral
        expect(!neutral.hasColor, "neutral 无色")
        expect(neutral.primary.l == 0.92 && neutral.primary.c == 0, "neutral 是 L 0.92 的灰")
        expect(neutral.text == neutral.fill && neutral.fill == neutral.secondaryFill, "neutral 三色同一个")
        expect(abs(neutral.text.r - neutral.text.g) < 1e-6 && abs(neutral.text.g - neutral.text.b) < 1e-6, "neutral 是中性灰")

        // 灰图、纯黑、纯白、全透明、尺寸不对：都回白 0.92。
        expect(ArtworkPalette.make(rgba: solid(128, 128, 128)) == neutral, "灰图回白 0.92")
        expect(ArtworkPalette.make(rgba: solid(0, 0, 0)) == neutral, "纯黑回白 0.92")
        expect(ArtworkPalette.make(rgba: solid(255, 255, 255)) == neutral, "纯白回白 0.92")
        expect(ArtworkPalette.make(rgba: solid(220, 30, 30, alpha: 0)) == neutral, "全透明回白 0.92")
        expect(ArtworkPalette.make(rgba: [1, 2, 3]) == neutral, "尺寸不对回白 0.92")
        expect(ArtworkPalette.make(rgba: []) == neutral, "空输入回白 0.92")
    }

    static func testThresholdsAndFraction() {
        // 红色像素占比：8% 以下无色，以上有色。8% × 4096 = 327.68。
        let red: (UInt8, UInt8, UInt8) = (220, 40, 40)
        let gray: (UInt8, UInt8, UInt8) = (128, 128, 128)
        expect(ArtworkPalette.make(rgba: split(red, count: 327, gray)) == ArtworkPalette.neutral, "不到 8% 当无色")
        expect(ArtworkPalette.make(rgba: split(red, count: 328, gray)).hasColor, "到 8% 有色")
        // alpha 0.5 刚好留下，0.49 丢掉。
        expect(ArtworkPalette.make(rgba: solid(220, 40, 40, alpha: 128)).hasColor, "alpha ≥ 0.5 留下")
        expect(!ArtworkPalette.make(rgba: solid(220, 40, 40, alpha: 127)).hasColor, "alpha < 0.5 丢掉")
        // 很暗的红（L < 0.18）丢掉。
        expect(!ArtworkPalette.make(rgba: solid(40, 0, 0)).hasColor, "L < 0.18 不投票")
    }

    static func testPrimaryAndSecondary() {
        let red: (UInt8, UInt8, UInt8) = (230, 40, 40)
        let blue: (UInt8, UInt8, UInt8) = (40, 80, 230)
        let nearRed: (UInt8, UInt8, UInt8) = (230, 70, 30)
        // 红 3000、蓝 1096：蓝票数 ≥ 红的 25% 且色相差大，是副色。
        let both = ArtworkPalette.make(rgba: split(red, count: 3000, blue))
        expect(both.hasColor, "双色有色")
        expect(hueDistance(both.primary.h, 28) < 20, "主色是红（\(both.primary.h)）")
        expect(hueDistance(both.secondary.h, both.primary.h) >= 45, "副色色相差 ≥ 45°（\(both.secondary.h)）")
        expect(hueDistance(both.secondary.h, 265) < 25, "副色是蓝（\(both.secondary.h)）")

        // 单色：没有副色候选，用主色提亮 0.1。
        let single = ArtworkPalette.make(rgba: solid(red.0, red.1, red.2))
        expect(abs(single.secondary.l - (single.primary.l + 0.1)) < 1e-9, "单色副色 = 主色提亮 0.1")
        expect(single.secondary.h == single.primary.h, "单色副色色相不变")

        // 相近色相（< 45°）不当副色。
        let close = ArtworkPalette.make(rgba: split(red, count: 2500, nearRed))
        expect(abs(close.secondary.l - (close.primary.l + 0.1)) < 1e-9, "色相相近不当副色")

        // 蓝只有 3%：不到红的 25%，不当副色。
        let few = ArtworkPalette.make(rgba: split(red, count: 3970, blue))
        expect(abs(few.secondary.l - (few.primary.l + 0.1)) < 1e-9, "票数不足 25% 不当副色")
    }

    static func testClampsAndContrast() {
        let samples: [(UInt8, UInt8, UInt8)] = [
            (230, 40, 40), (40, 80, 230), (250, 230, 30), (30, 200, 90), (150, 20, 200), (255, 140, 0), (10, 60, 20), (0, 255, 255),
        ]
        for color in samples {
            let palette = ArtworkPalette.make(rgba: solid(color.0, color.1, color.2))
            guard palette.hasColor else { continue }
            // 字色对纯黑 ≥ 7:1。
            expect(palette.text.contrastAgainstBlack >= 7, "字色对纯黑 ≥ 7:1：\(color) → \(palette.text.contrastAgainstBlack)")
            expect(palette.fill.contrastAgainstBlack >= 4.5, "填充色对纯黑 ≥ 4.5:1")
            for rgb in [palette.text, palette.fill, palette.secondaryFill] {
                expect([rgb.r, rgb.g, rgb.b].allSatisfy { $0 >= 0 && $0 <= 1 }, "颜色在 sRGB 内")
            }
        }
        // 暗红被抬到下限、鲜艳色被压到彩度上限。
        let dark = ArtworkPalette.make(rgba: solid(110, 20, 30))
        expect(dark.hasColor, "暗红有色")
        expect(dark.text.relativeLuminance > ArtworkRGB(r: 0.3, g: 0.3, b: 0.3).relativeLuminance * 0.5, "暗色被抬亮")
        // 纯黑上的灰 0.92 也过 7:1。
        expect(ArtworkPalette.neutral.text.contrastAgainstBlack >= 7, "neutral 对纯黑 ≥ 7:1")
    }

    static func testUnpremultiplyAndFingerprint() {
        let restored = ArtworkPalette.unpremultiplied([100, 50, 0, 200, 9, 9, 9, 0, 40, 40, 40, 255])
        expect(restored[0] == 128 && restored[1] == 64 && restored[2] == 0 && restored[3] == 200, "按 alpha 还原")
        expect(restored[4] == 0 && restored[5] == 0 && restored[6] == 0 && restored[7] == 0, "alpha 0 清零")
        expect(restored[8] == 40 && restored[11] == 255, "不透明不变")
        expect(ArtworkPalette.fingerprint(of: [1, 2, 3]) != ArtworkPalette.fingerprint(of: [1, 2, 4]), "指纹随内容变")
    }

    static func makeInfo(title: String = "歌", artist: String = "手") -> NowPlayingInfo {
        NowPlayingInfo(bundleID: "com.apple.Music", title: title, artist: artist, isPlaying: true,
                       duration: 200, elapsed: 1, timestamp: 1, rate: 1)
    }

    static func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    static func testPayload() {
        let image = Data(repeating: 7, count: 1000)
        let ok = json(["title": "歌", "artist": "手", "artworkMimeType": "image/jpeg", "artworkData": image.base64EncodedString()])
        let payload = NowPlayingArtworkPayload.parse(ok)
        expect(payload?.imageData == image && payload?.mimeType == "image/jpeg", "解出封面字节")
        expect(payload?.matches(makeInfo()) == true, "歌名歌手对得上")
        expect(payload?.matches(makeInfo(title: "别的歌")) == false, "换了歌不收")

        // 上限 4 MB：刚好收，多一个字节当没有。
        let atLimit = Data(count: NowPlayingArtworkPayload.maxImageBytes)
        expect(NowPlayingArtworkPayload.parse(json(["artworkData": atLimit.base64EncodedString()])) != nil, "4 MB 整收")
        let over = Data(count: NowPlayingArtworkPayload.maxImageBytes + 1)
        expect(NowPlayingArtworkPayload.parse(json(["artworkData": over.base64EncodedString()])) == nil, "超 4 MB 当没有")
        expect(NowPlayingArtworkPayload.parse(Data(count: NowPlayingArtworkPayload.maxOutputBytes + 1)) == nil, "输出过大当没有")

        expect(NowPlayingArtworkPayload.parse(Data("null".utf8)) == nil, "null 当没有")
        expect(NowPlayingArtworkPayload.parse(json(["title": "歌"])) == nil, "没有封面键当没有")
        expect(NowPlayingArtworkPayload.parse(json(["artworkData": "!!!"])) == nil, "坏 base64 当没有")
        expect(NowPlayingArtworkPayload.parse(Data()) == nil, "空输出当没有")

        // 推送流解析器仍不留封面，行上限不变。
        var parser = NowPlayingStreamParser()
        _ = parser.consume("{\"type\":\"data\",\"diff\":false,\"payload\":{\"title\":\"歌\",\"artworkData\":\"AAAA\"}}")
        expect(!parser.retainedFieldNames.contains("artworkData"), "推送流不留封面")
        expect(NowPlayingStreamParser.maxLineBytes == 64 * 1024, "推送流行上限不放宽")
        expect(makeInfo().artworkTrackKey != makeInfo(title: "x").artworkTrackKey, "换曲键不同")
        var paused = makeInfo(); paused = NowPlayingInfo(bundleID: paused.bundleID, title: paused.title, artist: paused.artist,
                                                         isPlaying: false, duration: 1, elapsed: 0.5, timestamp: 2, rate: 0)
        expect(paused.artworkTrackKey == makeInfo().artworkTrackKey, "暂停、进度不改曲目键")
    }

    static func png(width: Int, height: Int, fill: (Int, Int) -> (UInt8, UInt8, UInt8)) -> Data {
        var bytes: [UInt8] = []
        for y in 0..<height { for x in 0..<width { let c = fill(x, y); bytes += [c.0, c.1, c.2, 255] } }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        precondition(CGImageDestinationFinalize(dest))
        return out as Data
    }

    static func testDecoder() {
        // 非正方形（300 × 200）也缩成 128 × 128，并且取到红色。
        let data = png(width: 300, height: 200) { _, _ in (230, 40, 40) }
        let decoded = NowPlayingArtworkDecoder.decode(imageData: data, trackKey: "k")
        expect(decoded != nil, "能解 PNG")
        expect(decoded?.rgba.count == 128 * 128 * 4, "缩到 128 × 128")
        expect(decoded?.palette.hasColor == true && hueDistance(decoded?.palette.primary.h ?? 0, 28) < 20, "取到红色")
        expect(decoded?.makeCGImage()?.width == 128, "能造出 128 的图")
        expect(decoded?.trackKey == "k", "带曲目键")
        // 同一张图重解结果相同。
        expect(NowPlayingArtworkDecoder.decode(imageData: data, trackKey: "k") == decoded, "同图同结果")
        // 灰图回白 0.92。
        let gray = png(width: 64, height: 64) { _, _ in (128, 128, 128) }
        expect(NowPlayingArtworkDecoder.decode(imageData: gray, trackKey: "g")?.palette == ArtworkPalette.neutral, "灰封面回白 0.92")
        // 不是图片、超 4 MB 当没有。
        expect(NowPlayingArtworkDecoder.decode(imageData: Data("not an image".utf8), trackKey: "x") == nil, "非图片当没有")
        expect(NowPlayingArtworkDecoder.decode(imageData: Data(count: NowPlayingArtworkPayload.maxImageBytes + 1), trackKey: "x") == nil,
               "超 4 MB 当没有")
    }
}

/// NowPlayingStream.swift 要用的命令类型（真身在 NotchActivitySources.swift，那个文件拖进太多别的东西）。
enum NotchMusicCommand: String { case playPause, previous, next }
