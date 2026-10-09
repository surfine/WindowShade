// 正在播放的紧凑两耳（设计稿《正在播放》“紧凑”两张卡片，工作包 NP-2）。纯函数，只依赖 Foundation：
// 左耳封面的边长与退回规则、右耳 5 个静止取色点的颜色与尺寸。不碰 AppKit、不读时钟、不起任何计时器。
//
// 稿里的数字：
// - 左耳封面边长 = round(0.6 × 刘海高)（33.5 高的刘海上是 20），圆角 = 边长 ÷ 4（20 → 5），上下居中、在主体里水平居中；
// - 耳宽 = 主体 + 肩（34 = 26.6 + 7.4）。耳宽被压到 30 以下时，边长 = 主体 − 6；不到 14 就退回音符符号；
// - 右耳 5 个点：宽 2、间距 1.6、静止时一个圆点 2.4 高，上下居中；主色、副色交替；
// - 暂停：点变成白 0.45、封面透明度降到 0.5（0.18 秒淡过去）；没有封面：白 0.14 的圆角方块，中间白 0.6 的音符。
// - 不画任何会动的波形：真实波形要系统音频录制（NP-6），本包不做。

import Foundation

enum NowPlayingEars {
    // MARK: 左耳封面

    /// 边长 = 刘海高的这个比例，四舍五入。
    static let coverHeightFraction = 0.6
    /// 圆角 = 边长的 1/4（连续曲线）。
    static let coverCornerFraction = 0.25
    /// 耳宽（主体 + 肩）低于它，封面改用“主体 − 留白”。
    static let squeezedEarWidth = 30.0
    /// 耳宽被压窄时，主体里左右各留 3，合计 6。
    static let squeezedMargin = 6.0
    /// 边长小于它就放不下封面，退回音符符号（今天的样子）。
    static let minimumCoverSide = 14.0

    /// 封面边长；nil = 放不下，退回音符符号。
    /// - body：这一耳主体的宽（不含肩）；shoulder：肩的宽（没画肩就是 0）；notchHeight：刘海高。
    static func coverSide(body: Double, shoulder: Double, notchHeight: Double) -> Double? {
        guard body.isFinite, shoulder.isFinite, notchHeight.isFinite, body > 0, notchHeight > 0 else { return nil }
        let nominal = (coverHeightFraction * notchHeight).rounded()
        let earWidth = body + max(0, shoulder)
        let side = earWidth < squeezedEarWidth ? body - squeezedMargin : min(nominal, body)
        return side >= minimumCoverSide ? side : nil
    }

    static func coverCorner(side: Double) -> Double { side * coverCornerFraction }

    // MARK: 右耳静止点

    static let dotCount = 5
    static let dotWidth = 2.0
    static let dotSpacing = 1.6
    /// 最低一档：一个圆点（稿里的“最低 2.4”）。静止点就画在这一档。
    static let dotRestingHeight = 2.4
    static let pausedDotWhite = 0.45
    static let pausedCoverAlpha = 0.5
    static let placeholderFillWhite = 0.14
    static let placeholderNoteWhite = 0.6
    /// 暂停、继续时颜色与透明度淡过去的时长。
    static let fadeSeconds = 0.18

    static var dotsWidth: Double { Double(dotCount) * dotWidth + Double(dotCount - 1) * dotSpacing }

    /// 一个点的颜色（sRGB，分量 0…1）。
    struct DotColor: Equatable, Sendable {
        var r: Double
        var g: Double
        var b: Double
        var alpha: Double
    }

    /// 5 个点的颜色。在放：主色、副色交替（没有封面或封面没有颜色时 palette 是白 0.92，点就是白 0.92）；暂停：白 0.45。
    static func dotColors(palette: ArtworkPalette?, paused: Bool) -> [DotColor] {
        if paused {
            return Array(repeating: DotColor(r: pausedDotWhite, g: pausedDotWhite, b: pausedDotWhite, alpha: 1), count: dotCount)
        }
        let pal = palette ?? ArtworkPalette.neutral
        let primary = DotColor(r: pal.fill.r, g: pal.fill.g, b: pal.fill.b, alpha: 1)
        let secondary = DotColor(r: pal.secondaryFill.r, g: pal.secondaryFill.g, b: pal.secondaryFill.b, alpha: 1)
        return (0..<dotCount).map { $0 % 2 == 0 ? primary : secondary }
    }

    static func coverAlpha(paused: Bool) -> Double { paused ? pausedCoverAlpha : 1 }

    // MARK: 版式

    struct Slot: Equatable, Sendable {
        var minX: Double
        var minY: Double
        var width: Double
        var height: Double
    }

    struct Frame: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// 封面在左耳主体里水平居中、竖直居中。
    static func coverFrame(in slot: Slot, side: Double) -> Frame {
        Frame(x: slot.minX + (slot.width - side) / 2, y: slot.minY + (slot.height - side) / 2, width: side, height: side)
    }

    /// 第 index 个点的外框：整组在右耳主体里水平居中，竖直居中。
    static func dotFrame(index: Int, in slot: Slot) -> Frame {
        let startX = slot.minX + (slot.width - dotsWidth) / 2
        return Frame(x: startX + Double(index) * (dotWidth + dotSpacing),
                     y: slot.minY + (slot.height - dotRestingHeight) / 2, width: dotWidth, height: dotRestingHeight)
    }

    /// 读屏念的话：歌名，歌手；暂停加“已暂停”。
    static func spoken(title: String, artist: String, paused: Bool) -> String {
        var text = artist.isEmpty ? title : "\(title)，\(artist)"
        if paused { text += "，已暂停" }
        return text
    }

    /// 紧凑两耳走新样子的前提：推送流开着（它才有封面）。关着时一律是今天的样子，不改。
    static func usesCoverEars(streamEnabled: Bool, isMusic: Bool) -> Bool { streamEnabled && isMusic }
}
