// 大卡里的右耳波形（设计稿《正在播放》“波形留在右耳原处不动”）：位置、静止点、跟着跳、暂停、静音。
import Foundation

@main struct NowPlayingWaveDotsTests {
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, "断言失败: \(message)")
    }

    static func main() {
        let slot = NowPlayingWaveDots.trailingSlot(cardWidth: 420, notchWidth: 185, notchHeight: 33.5)
        expect(slot.minX == 302.5 && slot.minY == 0 && slot.width == 26.6 && slot.height == 33.5, "右耳在刘海右边，宽一个主体、高一个刘海")
        let palette = ArtworkPalette.neutral

        let still = NowPlayingWaveDots.dots(wave: .dots, paused: false, palette: palette, in: slot)
        expect(still.count == 5, "5 个点")
        expect(still.allSatisfy { $0.frame.height == NowPlayingEars.dotRestingHeight }, "静止点是最低一档")
        expect(still.map(\.frame) == (0..<5).map { NowPlayingEars.dotFrame(index: $0, in: slot) }, "位置和紧凑右耳同一套")
        let left = still[0].frame.x, right = still[4].frame.x + still[4].frame.width
        expect(abs((left + right) / 2 - (slot.minX + slot.width / 2)) < 1e-9, "整组居中")

        let live = NowPlayingWaveDots.dots(wave: NowPlayingWave(mode: .live, levels: [0, 0.5, 1, 0.25, 0]), paused: false,
                                           palette: palette, in: slot)
        expect(abs(live[0].frame.height - 2.4) < 1e-9 && abs(live[2].frame.height - 14) < 1e-9, "根高 2.4 + 11.6 × 电平")
        expect(live.allSatisfy { abs(($0.frame.y + $0.frame.height / 2) - (slot.minY + slot.height / 2)) < 1e-9 }, "竖直居中")

        let paused = NowPlayingWaveDots.dots(wave: NowPlayingWave(mode: .live, levels: [1, 1, 1, 1, 1]), paused: true,
                                             palette: palette, in: slot)
        expect(paused.allSatisfy { $0.frame.height == NowPlayingEars.dotRestingHeight && $0.color.r == 0.45 }, "暂停：白 0.45 静止点，不跟着跳")

        // 静音（控制器给的模式是 .dots）和减少动态效果（.still）。
        let muted = NowPlayingWaveDots.dots(wave: .dots, paused: false, palette: palette, in: slot)
        expect(muted.allSatisfy { $0.frame.height == 2.4 }, "静音：静止点")
        let reduced = NowPlayingWaveDots.dots(wave: NowPlayingWave(mode: .still, levels: []), paused: false, palette: palette, in: slot)
        expect(reduced.allSatisfy { $0.frame.height == 2.4 && $0.color == reduced[0].color }, "减少动态效果：静止的填充色点")
        expect(NowPlayingWaveDots.effectiveMode(NowPlayingWave(mode: .paused, levels: []), paused: false) == .dots, "没暂停却报暂停：按静止点")
        print("PASS now-playing-wave-dots")
    }
}
