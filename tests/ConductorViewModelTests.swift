// R10：指挥回合的刘海画面。只测纯逻辑（Core/ConductorSession.swift 里的 ConductorShape / ConductorBeatDots /
// ConductorWaveform / ConductorDraftMarks / ConductorPresentation），以及草稿没把握的词怎么从会话流到画面上。
// AppKit 视图只照着这些画，没有自己的判断。
import Foundation

private struct Rig {
    var state = ConductorSession(bootID: fixtureBoot, emptyDraftDigest: digest(0))
    var context = fixtureContext()
    var sequence: UInt64 = 0
    var now = 0.0
    let model = WS2.ModelID(provider: .codex, modelID: "mock-model")
    init() {
        let caps = [ConductorCapabilities(model: model, supportedEfforts: ["low", "medium", "high", "xhigh", "max", "ultra"],
                                          revision: 1, ultracodeWorkflowID: nil)]
        let config = WS2.ExecutionConfig(model: model, effort: "high", workflowID: nil, capabilityRevision: 1)
        _ = state.setEnabled(true, at: sec(0))
        _ = send(.connected(projectLabel: "测试项目", initial: config, capabilities: caps, slots: [model, nil, nil, nil]), at: 0)
        _ = send(.snapshot(turnID: nil, actual: nil), at: 0.01)
    }
    @discardableResult mutating func send(_ event: ConductorSession.Event, at time: Double? = nil) -> [ConductorSession.Effect] {
        now = time ?? now + 0.1; sequence += 1
        return state.receive(.init(context: context, sequence: sequence, receivedAt: sec(now), commandID: nil, turnID: nil, payload: event))
    }
    /// 侧键点一下开始收音，返回采集令牌。
    mutating func startCapture() -> WS2.Token? {
        _ = send(.source(id: "mic", label: "测试麦克风"))
        let start = now + 0.1
        let effects = send(.button(button(.side, .clickOnly, 1, start, start)), at: start)
        return effects.compactMap { if case .startCapture(let id, _) = $0 { return id }; return nil }.first
    }
    mutating func draw(_ points: [ConductorPoint]) {
        let start = now + 0.1
        for (i, p) in points.enumerated() {
            _ = send(.touch(i == 0 ? .begin : i == points.count - 1 ? .end : .move, .init(x: p.x, y: p.y)), at: start + p.t)
        }
    }
}

@main
struct ConductorViewModelTests {
    static func main() {
        var t = TestSuite("R10")
        let target = ConductorPresentation.Target(project: "测试项目", assistant: "Codex")

        t.section("R10-01", "形状：指挥态 40×12.6cqw，模型选择 50×13.6cqw，cqw 是屏宽 1%")
        let conductor = ConductorShape.size(.conductor, screenWidth: 1440)
        t.expect(conductor.width == 576 && conductor.height == 181, "1440 宽：576×181（\(conductor.width)×\(conductor.height)）")
        let picker = ConductorShape.size(.modelPicker, screenWidth: 1440)
        t.expect(picker.width == 720 && picker.height == 196, "1440 宽模型选择：720×196（\(picker.width)×\(picker.height)）")
        t.expect(ConductorShape.size(.conductor, screenWidth: 1000).width == 400, "屏宽 1000：40cqw = 400")
        t.expect(ConductorShape.size(.conductor, screenWidth: 0).width == 0 && ConductorShape.size(.conductor, screenWidth: .nan).height == 0,
                 "屏宽无效：不给尺寸")

        t.section("R10-02", "拍点：只亮已完成的拍，给定 beatPreview 序列逐次亮灭")
        let sequence = [0, 1, 2, 3, 4, 4, 5, 6, 3, 0]
        var previous = 0
        for beats in sequence {
            let lit = ConductorBeatDots.lit(forBeats: beats)
            t.expect(lit.count == 6 && lit.filter { $0 }.count == beats && lit.prefix(beats).allSatisfy { $0 } && !lit.dropFirst(beats).contains(true),
                     "\(beats) 拍：前 \(beats) 个亮，后面的灭")
            let fresh = ConductorBeatDots.newlyLit(from: previous, to: beats)
            t.expect(beats > previous ? fresh == Array(previous..<beats) : fresh.isEmpty, "\(previous)→\(beats)：新亮的点 \(fresh)")
            previous = beats
        }
        t.expect(ConductorBeatDots.newlyLit(from: 3, to: 4) == [3], "第四拍时只新亮第四个点")
        t.expect(ConductorBeatDots.lit(forBeats: 9).filter { $0 }.count == 6 && ConductorBeatDots.lit(forBeats: -2).allSatisfy { !$0 },
                 "超出范围按 0…6 夹住")
        let drawing = ConductorPresentation.make(.trajectory(points: [], beats: 4), target: target)
        t.expect(drawing.beatDots == ConductorBeatDots.lit(forBeats: 4) && drawing.title == "抬手才判定", "画到第四拍：亮四个点，标题仍是“抬手才判定”")
        let drawingText = drawing.title + drawing.subtitle
        t.expect(!["low", "medium", "high", "xhigh", "max", "ultra", "声", "拍 ·"].contains { drawingText.contains($0) },
                 "抬手前不写手势名、不写档位（不先切档）")

        t.section("R10-03", "判定之后：手势名 · 档位，副句写项目 · 助手")
        var rig = Rig()
        rig.draw([.init(t: 0, x: 0.2, y: 0.7), .init(t: 0.3, x: 0.5, y: 0.3), .init(t: 0.6, x: 0.8, y: 0.7)])
        let judged = ConductorPresentation.make(rig.state.notch, target: target)
        t.expect(judged.title == "三声 · high" && judged.subtitle == "测试项目 · Codex", "三声 · high / 测试项目 · Codex（\(judged.title) / \(judged.subtitle)）")
        t.expect(judged.beatDots == nil, "判定后不再画拍点")
        let connected = ConductorNotch.connected(project: "测试项目", provider: .codex, effort: "high")
        t.expect(ConductorPresentation.target(from: connected) == target && ConductorPresentation.target(from: .transcribing) == nil,
                 "目标只从“连上”那一行取")
        let costly = ConductorPresentation.make(.cost(label: "五拍 · max"), target: target)
        t.expect(costly.title == "五拍 · max" && costly.subtitle == "点一下确认", "高开销档位：手势名 · 档位，副句点一下确认")
        let noTarget = ConductorPresentation.make(.staged(label: "三声 · high　下一轮"), target: nil)
        t.expect(noTarget.title == "三声 · high" && noTarget.subtitle.isEmpty, "不知道目标时副句留空，不编")

        t.section("R10-04", "听写：有 audioSamples 才画波形，没收到声音写“没有收到声音”")
        t.expect(ConductorPresentation.make(.waitingForAudio, target: target).showsWaveform == false
                 && ConductorPresentation.make(.waitingForAudio, target: target).title == "没有收到声音", "等声音：不画波形")
        var audio = Rig()
        let capture = audio.startCapture()
        t.expect(capture != nil && audio.state.notch == .waitingForAudio, "开始收音，还没有样本")
        t.expect(!ConductorPresentation.make(audio.state.notch, target: target).showsWaveform, "没有 audioSamples：不画波形")
        if let capture { _ = audio.send(.audioSamples(capture: capture)) }
        let heard = ConductorPresentation.make(audio.state.notch, target: target)
        t.expect(heard.showsWaveform && heard.subtitle == "测试麦克风 · 松开出草稿", "收到样本后：画波形，副句“来源 · 松开出草稿”")
        t.expect(!ConductorPresentation.make(.transcribing, target: target).showsWaveform
                 && !ConductorPresentation.make(.draft("x", header: "草稿"), target: target).showsWaveform, "转写和草稿不画波形")
        t.expect(ConductorWaveform.bars(from: []).isEmpty, "没有样本：没有柱")
        let quiet = ConductorWaveform.bars(from: [Float](repeating: 0, count: 480))
        t.expect(quiet.count == 20 && quiet.allSatisfy { $0 == 0 }, "20 根柱；静音全是 0")
        let loud = ConductorWaveform.bars(from: [Float](repeating: 1, count: 480))
        t.expect(loud.allSatisfy { $0 == 1 }, "满幅：全 1")
        let half = ConductorWaveform.bars(from: [Float](repeating: 0.1, count: 480))
        t.expect(half.allSatisfy { $0 > 0.5 && $0 < 0.8 }, "RMS 0.1（-20 dBFS）：中等高度（\(half[0])）")
        let ramp = ConductorWaveform.bars(from: (0..<400).map { Float($0) / 400 })
        t.expect(ramp.count == 20 && zip(ramp, ramp.dropFirst()).allSatisfy { $0 <= $1 } && ramp.last! > ramp.first!, "每根柱是自己那一段的 RMS，随幅度递增")
        t.expect(ConductorWaveform.bars(from: [0.5, .nan, .infinity]).allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }, "不是数的样本按 0 算")
        t.expect(ConductorWaveform.bars(from: [0.5]).count == 20, "样本比柱少也是 20 根")

        t.section("R10-05", "草稿：没把握的词划线，区间映射到下划线范围")
        t.expect(ConductorDraftMarks.nsRanges([1..<3], in: "改一下阴影") == [NSRange(location: 1, length: 2)], "中文：字数区间 = UTF-16 区间")
        t.expect(ConductorDraftMarks.nsRanges([1..<2], in: "a👍b") == [NSRange(location: 1, length: 2)], "表情占两个 UTF-16 单位")
        t.expect(ConductorDraftMarks.nsRanges([2..<3], in: "a👍b") == [NSRange(location: 3, length: 1)], "表情之后的字位置正确")
        t.expect(ConductorDraftMarks.sanitize([4..<9, 0..<0, -3..<2, 1..<3, 7..<20], in: "0123456789") == [0..<3, 4..<10],
                 "夹进全文、去空、并拢重叠")
        t.expect(ConductorDraftMarks.sanitize([2..<4, 4..<6], in: "0123456789") == [2..<6], "相连的区间并成一条")
        t.expect(ConductorDraftMarks.sanitize([10..<12], in: "0123456789").isEmpty, "全在文本之外：没有")
        let many = (0..<200).map { ($0 * 2)..<($0 * 2 + 1) }
        t.expect(ConductorDraftMarks.sanitize(many, in: String(repeating: "字", count: 500)).count == ConductorDraftMarks.maximumRanges, "最多 64 段")
        let drafted = ConductorPresentation.make(.draft("改一下阴影", header: "草稿 · 给 测试项目 · Codex · high", uncertain: [3..<5, 1..<2]), target: target)
        t.expect(drafted.uncertainRanges == [1..<2, 3..<5] && drafted.draftBody == "改一下阴影", "画面带的是整理过的区间")
        t.expect(drafted.title == "草稿 · 给 测试项目 · Codex · high" && drafted.draftFooter == "播放键发出去 · 返回收起", "三行：给谁 / 全文 / 怎么发出去")

        t.section("R10-06", "没把握的词从听写一路流到草稿；人手一改就清掉")
        var flow = Rig()
        if let capture = flow.startCapture() {
            _ = flow.send(.audioSamples(capture: capture))
            _ = flow.send(.button(button(.side, .clickOnly, 2, flow.now + 0.1, flow.now + 0.1)), at: flow.now + 0.1)
            _ = flow.send(.transcript(capture: capture, text: "改一下阴影", digest: digest(3), uncertain: [3..<9, 1..<2, -1..<0]))
        }
        t.expect(flow.state.draft?.text == "改一下阴影" && flow.state.draft?.uncertainRanges == [1..<2, 3..<5], "草稿模型存的是整理过的区间")
        if case .draft(let text, let header, let marks) = flow.state.notch {
            t.expect(text == "改一下阴影" && marks == [1..<2, 3..<5] && header.hasPrefix("草稿 · 给 测试项目"), "刘海上的草稿带着同一份区间")
        } else { t.expect(false, "转写后应显示草稿，实际 \(flow.state.notch)") }
        t.expect(flow.state.notch.text == "草稿 · 给 测试项目 · Codex · high\n改一下阴影\n播放键发出去 · 返回收起", "三行文案不变")
        _ = flow.send(.editDraft(text: "改一下阴影和高光", digest: digest(4)))
        t.expect(flow.state.draft?.uncertainRanges.isEmpty == true, "手改过：标记作废")
        var plain = Rig()
        _ = plain.send(.editDraft(text: "手打的草稿", digest: digest(2)))
        t.expect(plain.state.notch == .draft("手打的草稿", header: "草稿 · 给 测试项目 · Codex · high"), "不带标记的草稿和以前一样")

        t.section("R10-07", "完成：折起来一行，点一下展开全文")
        let done = ConductorPresentation.make(.completed("改了 3 个文件\nA.swift\nB.swift"), target: target)
        t.expect(done.title == "完成" && done.subtitle == "改了 3 个文件" && done.summary == "改了 3 个文件\nA.swift\nB.swift", "折起来只露第一行，全文留着")
        t.expect(ConductorNotch.completed("改了 3 个文件").text == "完成 · 改了 3 个文件", "会话层的文字不变")

        t.section("R10-08", "其它画面保持原文字")
        for notch: ConductorNotch in [.transcribing, .sent, .stopped, .message("已取消"), .muted(true), .waitingForAudio] {
            let p = ConductorPresentation.make(notch, target: target)
            t.expect(p.title == notch.text && p.beatDots == nil && !p.showsWaveform, "\(notch.text)")
        }
        let models = ConductorPresentation.make(.models(["a", "b", "c", "d", "e"], selected: 1), target: target)
        t.expect(models.modelRows == ["a", "b", "c", "d"] && models.selectedModel == 1 && models.title == "下一轮用哪个模型", "模型位置最多四个")

        t.finish()
    }
}
