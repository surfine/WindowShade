// 正在播放紧凑两耳（设计稿《正在播放》NP-2）：封面边长与退回规则、静止点颜色取自取色结果、没封面时的占位。
// 纯逻辑，无权限、无 UI、不起子进程。

import Foundation

@main struct NowPlayingEarsTests {
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, "断言失败: \(message)")
    }

    static func split(_ a: (UInt8, UInt8, UInt8), count first: Int, _ b: (UInt8, UInt8, UInt8)) -> [UInt8] {
        var out: [UInt8] = []
        for index in 0..<4096 {
            let c = index < first ? a : b
            out += [c.0, c.1, c.2, 255]
        }
        return out
    }

    static func close(_ a: Double?, _ b: Double, _ message: String) {
        expect(a != nil && abs(a! - b) < 1e-9, "\(message)（实际 \(String(describing: a))）")
    }

    static func main() {
        testCoverSide()
        testSqueezeAndFallback()
        testDotColors()
        testPlaceholderAndPaused()
        testLayout()
        testGate()
        print("PASS now-playing-ears")
    }

    static func testCoverSide() {
        // 33.5 高的刘海：round(0.6 × 33.5) = round(20.1) = 20；34 宽的耳 = 主体 26.6 + 肩 7.4。
        close(NowPlayingEars.coverSide(body: 26.6, shoulder: 7.4, notchHeight: 33.5), 20, "本机边长 20")
        close(NowPlayingEars.coverCorner(side: 20), 5, "圆角 5")
        // 没画肩：主体就是 34。
        close(NowPlayingEars.coverSide(body: 34, shoulder: 0, notchHeight: 33.5), 20, "没肩也是 20")
        // 别的刘海高：32 → round(19.2) = 19；38 → round(22.8) = 23。
        close(NowPlayingEars.coverSide(body: 26.6, shoulder: 7.4, notchHeight: 32), 19, "刘海 32 高")
        close(NowPlayingEars.coverSide(body: 30, shoulder: 7.4, notchHeight: 38), 23, "刘海 38 高")
        // 刚好 30 宽的耳：还是整边长。
        close(NowPlayingEars.coverSide(body: 22.6, shoulder: 7.4, notchHeight: 33.5), 20, "耳宽 30 整边长")
    }

    static func testSqueezeAndFallback() {
        // 耳宽 < 30：边长 = 主体 − 6。耳宽 29 = 主体 21.6 + 肩 7.4 → 15.6。
        close(NowPlayingEars.coverSide(body: 21.6, shoulder: 7.4, notchHeight: 33.5), 15.6, "耳宽 29 边长 = 主体 − 6")
        // 边长刚好 14 还画；13.9 退回。
        close(NowPlayingEars.coverSide(body: 20, shoulder: 0, notchHeight: 33.5), 14, "边长 14 还画")
        expect(NowPlayingEars.coverSide(body: 19.9, shoulder: 0, notchHeight: 33.5) == nil, "边长不到 14 退回音符")
        // 稿的验收：耳宽压到 26（主体 18.6 + 肩 7.4）退回音符。
        expect(NowPlayingEars.coverSide(body: 18.6, shoulder: 7.4, notchHeight: 33.5) == nil, "耳宽 26 退回音符")
        // 不合理的输入一律退回。
        expect(NowPlayingEars.coverSide(body: 0, shoulder: 7.4, notchHeight: 33.5) == nil, "主体 0 退回")
        expect(NowPlayingEars.coverSide(body: 26.6, shoulder: 7.4, notchHeight: 0) == nil, "没有刘海高退回")
        expect(NowPlayingEars.coverSide(body: .nan, shoulder: 7.4, notchHeight: 33.5) == nil, "NaN 退回")
        // 整边长不会超过主体。
        let side = NowPlayingEars.coverSide(body: 31, shoulder: 0, notchHeight: 80)
        expect(side != nil && side! <= 31, "不超过主体")
    }

    static func testDotColors() {
        let red: (UInt8, UInt8, UInt8) = (230, 40, 40)
        let blue: (UInt8, UInt8, UInt8) = (40, 80, 230)
        let palette = ArtworkPalette.make(rgba: split(red, count: 3000, blue))
        expect(palette.hasColor, "测试封面有颜色")
        let colors = NowPlayingEars.dotColors(palette: palette, paused: false)
        expect(colors.count == 5, "5 个点")
        for (index, color) in colors.enumerated() {
            let source = index % 2 == 0 ? palette.fill : palette.secondaryFill
            expect(color == NowPlayingEars.DotColor(r: source.r, g: source.g, b: source.b, alpha: 1),
                   "第 \(index) 个点取自 palette 的\(index % 2 == 0 ? "主色" : "副色")填充色")
        }
        expect(colors[0] != colors[1], "主色副色确实不同")
        expect(colors[0] == colors[2] && colors[2] == colors[4] && colors[1] == colors[3], "主色、副色交替")
        // 同一份 palette 结果不变。
        expect(NowPlayingEars.dotColors(palette: palette, paused: false) == colors, "颜色稳定")
    }

    static func testPlaceholderAndPaused() {
        // 没封面（palette 为 nil）和封面没有颜色（灰图）：都是白 0.92，两种点一个样。
        let none = NowPlayingEars.dotColors(palette: nil, paused: false)
        let neutral = ArtworkPalette.neutral.fill
        expect(none.count == 5 && none.allSatisfy { $0.r == neutral.r && $0.g == neutral.g && $0.b == neutral.b && $0.alpha == 1 },
               "没封面时点是白 0.92（palette.neutral）")
        expect(abs(neutral.r - neutral.g) < 1e-3 && abs(neutral.g - neutral.b) < 1e-3 && neutral.r > 0.85, "neutral 是中性亮灰（OKLCH L 0.92）")
        expect(none == NowPlayingEars.dotColors(palette: ArtworkPalette.neutral, paused: false), "灰图与没封面一样")
        // 暂停：5 个点都是白 0.45，不看 palette；封面透明度 0.5。
        let red: (UInt8, UInt8, UInt8) = (230, 40, 40)
        let palette = ArtworkPalette.make(rgba: split(red, count: 4096, red))
        for source in [palette, nil] {
            let paused = NowPlayingEars.dotColors(palette: source, paused: true)
            expect(paused.count == 5 && paused.allSatisfy { $0 == NowPlayingEars.DotColor(r: 0.45, g: 0.45, b: 0.45, alpha: 1) },
                   "暂停时点是白 0.45")
        }
        expect(NowPlayingEars.coverAlpha(paused: true) == 0.5 && NowPlayingEars.coverAlpha(paused: false) == 1, "封面透明度")
        // 占位的数字就是稿里的。
        expect(NowPlayingEars.placeholderFillWhite == 0.14 && NowPlayingEars.placeholderNoteWhite == 0.6, "占位 白 0.14 + 音符白 0.6")
        expect(NowPlayingEars.fadeSeconds == 0.18, "淡过去 0.18 秒")
    }

    static func testLayout() {
        let slot = NowPlayingEars.Slot(minX: 0, minY: 0, width: 26.6, height: 33.5)
        let cover = NowPlayingEars.coverFrame(in: slot, side: 20)
        close(cover.y, 6.75, "封面上下各 6.75")
        close(cover.x, 3.3, "封面在主体里水平居中")
        // 点：宽 2、间距 1.6、2.4 高；整组居中。
        close(NowPlayingEars.dotsWidth, 16.4, "5 个点总宽 16.4")
        let first = NowPlayingEars.dotFrame(index: 0, in: slot)
        let last = NowPlayingEars.dotFrame(index: 4, in: slot)
        close(first.width, 2, "点宽 2")
        close(first.height, 2.4, "点高 2.4（一个圆点）")
        close(NowPlayingEars.dotFrame(index: 1, in: slot).x - first.x, 3.6, "点距 = 宽 2 + 间距 1.6")
        close((first.x + (last.x + last.width)) / 2, slot.width / 2, "整组水平居中")
        close(first.y, (33.5 - 2.4) / 2, "上下居中")
        expect(NowPlayingEars.spoken(title: "歌", artist: "人", paused: false) == "歌，人", "读屏：歌名，歌手")
        expect(NowPlayingEars.spoken(title: "歌", artist: "", paused: true) == "歌，已暂停", "读屏：没歌手、暂停")
    }

    static func testGate() {
        expect(!NowPlayingEars.usesCoverEars(streamEnabled: false, isMusic: true), "推送流关着：今天的样子")
        expect(!NowPlayingEars.usesCoverEars(streamEnabled: true, isMusic: false), "不是音乐：不走封面耳")
        expect(NowPlayingEars.usesCoverEars(streamEnabled: true, isMusic: true), "推送流开着的音乐：封面耳")
    }
}
