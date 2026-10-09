import Foundation

@MainActor final class SpyOutput: ConductorSoundOutput {
    var played: [ConductorSoundCue] = []
    func play(_ cue: ConductorSoundCue) { played.append(cue) }
}

func trajectory(_ beats: Int) -> ConductorSession.Effect { .showNotch(.trajectory(points: [], beats: beats)) }

/// 过零次数，粗略看音高走向。
func crossings(_ s: ArraySlice<Float>) -> Int {
    var n = 0
    var prev: Float = 0
    for v in s {
        if prev != 0, (v > 0) != (prev > 0) { n += 1 }
        prev = v
    }
    return n
}

@main struct ConductorSoundTests {
    @MainActor static func main() {
        var t = TestSuite("ConductorSoundTests")

        t.section("map", "事件 → 音色")
        var beats = 0
        t.expect(ConductorSoundCue.cues(for: [trajectory(1)], lastBeats: &beats) == [.beat], "第一拍敲一声")
        t.expect(ConductorSoundCue.cues(for: [trajectory(1)], lastBeats: &beats).isEmpty, "拍数没涨不重复敲")
        t.expect(ConductorSoundCue.cues(for: [trajectory(2)], lastBeats: &beats) == [.beat], "拍数涨了再敲")
        t.expect(ConductorSoundCue.cues(for: [.sound("未识别")], lastBeats: &beats) == [.miss], "没认出是低闷一声")
        t.expect(beats == 0, "一笔结束后重新数")
        t.expect(ConductorSoundCue.cues(for: [trajectory(1)], lastBeats: &beats) == [.beat], "下一笔第一拍又敲")
        for (i, name) in ["一声", "二声", "三声", "四声"].enumerated() {
            let c = ConductorSoundCue.cues(for: [.showNotch(.staged(label: "\(name) · high　下一轮")), .sound("已识别")], lastBeats: &beats)
            t.expect(c == [.tone(i + 1)], "\(name) 回对应的声调")
        }
        t.expect(ConductorSoundCue.cues(for: [.showNotch(.staged(label: "三拍 · high　下一轮")), .sound("已识别")], lastBeats: &beats) == [.tone(1)],
                 "拍数手势认出回平调")
        t.expect(ConductorSoundCue.cues(for: [.showNotch(.message("x"))], lastBeats: &beats).isEmpty, "别的画面不出声")

        t.section("synth", "合成的时长与走向")
        func ms(_ c: ConductorSoundCue) -> Double { Double(c.samples().count) / ConductorSoundCue.sampleRate * 1000 }
        t.expect(abs(ms(.beat) - 30) < 1, "每拍 30 ms")
        t.expect(abs(ms(.miss) - 80) < 1, "没认出 80 ms")
        for n in 1...4 { t.expect(abs(ms(.tone(n)) - 120) < 1, "声调 \(n) 120 ms") }
        let up = ConductorSoundCue.tone(2).samples()
        let down = ConductorSoundCue.tone(4).samples()
        let half = up.count / 2
        t.expect(crossings(up[half...]) > crossings(up[..<half]), "二声升")
        t.expect(crossings(down[half...]) < crossings(down[..<half]), "四声降")
        let dip = ConductorSoundCue.tone(3).samples()
        let quarter = dip.count / 4
        t.expect(crossings(dip[(quarter * 2)..<(quarter * 3)]) < crossings(dip[..<quarter]) && crossings(dip[(dip.count - quarter)...]) > crossings(dip[(quarter * 2)..<(quarter * 3)]),
                 "三声先降后升")
        t.expect(ConductorSoundCue.all.allSatisfy { cue in cue.samples().allSatisfy { abs($0) <= 0.31 } }, "不削波")
        let tick = ConductorSoundCue.beat.samples()
        let thud = ConductorSoundCue.miss.samples()
        t.expect(Double(crossings(tick[...])) / Double(tick.count) > Double(crossings(thud[...])) / Double(thud.count) * 5, "敲声比咚声高得多")

        t.section("gate", "开关")
        let spy = SpyOutput()
        nonisolated(unsafe) var on = false
        let player = ConductorSoundPlayer(isEnabled: { on }, output: spy)
        player.play(.beat); player.play(.miss)
        t.expect(spy.played.isEmpty, "开关关着一声都不响")
        on = true
        player.play(.tone(3))
        t.expect(spy.played == [.tone(3)], "开着照响")

        t.finish()
    }
}
