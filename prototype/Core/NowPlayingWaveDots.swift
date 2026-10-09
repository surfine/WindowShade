// 右耳 5 根的画法（设计稿《正在播放》“长成大卡”：“波形留在右耳原处不动”）。纯函数：给模式、电平、封面取色和右耳那块地方，
// 出 5 个点的外框与颜色。紧凑的两耳和大卡里的右耳都按它画，大卡盖住刘海时波形不消失。
// 不碰 AppKit、不读时钟、不起计时器。

import Foundation

enum NowPlayingWaveDots {
    /// 右耳主体宽（稿：耳宽 34 = 主体 26.6 + 肩 7.4）。大卡里右耳也按这个宽，镜像左耳。
    static let earBody = 26.6

    struct Dot: Equatable, Sendable {
        var frame: NowPlayingEars.Frame
        var color: NowPlayingEars.DotColor
    }

    /// 大卡坐标里（左上角原点，含刘海那一截）右耳那块地方：从刘海右边起，宽一个主体，高一个刘海。
    static func trailingSlot(cardWidth: Double, notchWidth: Double, notchHeight: Double) -> NowPlayingEars.Slot {
        NowPlayingEars.Slot(minX: (cardWidth + notchWidth) / 2, minY: 0, width: earBody, height: notchHeight)
    }

    /// 这一刻真正画的模式：暂停一律按暂停画；调用方报了暂停、事实上没暂停，按静止点。
    static func effectiveMode(_ wave: NowPlayingWave, paused: Bool) -> NowPlayingWaveMode {
        paused ? .paused : (wave.mode == .paused ? .dots : wave.mode)
    }

    /// 5 个点。跟着跳：根高 = 2.4 + 11.6 × 电平，竖直居中，全部主色；减少动态效果：静止的填充色点（全部主色）；
    /// 其余（没开、没权限、录不到、静音、蓝牙 + Spotify）：主色副色交替的静止点；暂停：白 0.45。
    static func dots(wave: NowPlayingWave, paused: Bool, palette: ArtworkPalette?, in slot: NowPlayingEars.Slot) -> [Dot] {
        let mode = effectiveMode(wave, paused: paused)
        let base = NowPlayingEars.dotColors(palette: palette, paused: paused)
        let filled = mode == .live || mode == .still
        return (0..<NowPlayingEars.dotCount).map { index in
            var box = NowPlayingEars.dotFrame(index: index, in: slot)
            if mode == .live, index < wave.levels.count {
                let height = AudioLevelBands.rootHeight(level: wave.levels[index])
                box.y += (box.height - height) / 2
                box.height = height
            }
            return Dot(frame: box, color: filled ? base[0] : base[index])
        }
    }
}
