import Foundation
import Synchronization

// 说话人比对：fbank 对参考值、特征编码、登记、比对门槛、失败即关；有模型时再对一遍 Core ML 的端到端结果。
// 声音全是合成的（公式见 tools/speaker-model/convert.py），没有真人的声音。

func synthPCM(kind: Int, count: Int) -> [Float] {
    let params: [(Double, Double, Double)] = [(220, 1130, 3), (140, 2400, 5), (330, 700, 2)]
    let (f0, f1, am) = params[kind % 3]
    var s = UInt32(12345 + kind)
    var out = [Float](repeating: 0, count: count)
    for i in 0..<count {
        s = s &* 1664525 &+ 1013904223
        let noise = (Double((s >> 16) & 0x7FFF) - 16384) * 0.25
        let t = Double(i) / 16000
        let v = 6000 * sin(2 * Double.pi * f0 * t) + 3000 * sin(2 * Double.pi * f1 * t + sin(2 * Double.pi * am * t)) + noise
        out[i] = Float((v + 0.5).rounded(.down) / 32768)
    }
    return out
}

/// 按调用顺序吐预设向量的假模型。
final class ScriptedEmbedder: SpeakerEmbedder, @unchecked Sendable {
    private let queue: Mutex<[[Float]]>
    let fallback: [Float]?
    init(_ vectors: [[Float]], fallback: [Float]? = nil) { queue = Mutex(vectors); self.fallback = fallback }
    func embedding(window: [Float]) -> [Float]? {
        queue.withLock { q in q.isEmpty ? fallback : q.removeFirst() }
    }
}

final class MemoryStore: SpeakerTemplateStoring, @unchecked Sendable {
    private let box = Mutex<SpeakerTemplate?>(nil)
    func load() -> SpeakerTemplate? { box.withLock { $0 } }
    func write(_ template: SpeakerTemplate) -> Bool { box.withLock { $0 = template }; return true }
    func delete() -> Bool { box.withLock { $0 = nil }; return true }
}

func unit(_ index: Int, noise: Float = 0, seed: Int = 0) -> [Float] {
    var v = [Float](repeating: 0, count: 256)
    v[index % 256] = 1
    var s = UInt32(truncatingIfNeeded: 77 + seed)
    for i in 0..<256 { s = s &* 1664525 &+ 1013904223; v[i] += noise * (Float(s >> 16 & 0xFF) / 255 - 0.5) }
    return v
}

@main
struct SpeakerVerificationTests {
    static func main() throws {
        var t = TestSuite("speaker-verification")
        let root = FileManager.default.currentDirectoryPath

        // 1) fbank 对 torchaudio 的参考值
        t.section("fbank", "Swift fbank matches torchaudio kaldi.fbank on a synthetic waveform")
        let fixtureData = try Data(contentsOf: URL(fileURLWithPath: root + "/tests/fixtures/speaker-fbank-reference.json"))
        let fixture = try JSONSerialization.jsonObject(with: fixtureData) as! [String: Any]
        let fb = fixture["fbank"] as! [String: Any]
        let samples = fb["samples"] as! Int, frames = fb["frames"] as! Int
        let expected = (fb["values"] as! [[Double]]).flatMap { $0.map(Float.init) }
        let mine = SpeakerFbank.logMel(pcm: synthPCM(kind: fb["kind"] as! Int, count: samples))
        t.expect(SpeakerFbank.frameCount(samples: samples) == frames, "frame count \(frames)")
        t.expect(mine.count == expected.count, "value count \(expected.count)")
        var maxDiff: Float = 0, sumDiff: Float = 0
        for (a, b) in zip(mine, expected) { let d = abs(a - b); maxDiff = max(maxDiff, d); sumDiff += d }
        print("fbank max abs diff \(maxDiff), mean \(sumDiff / Float(max(1, mine.count)))")
        t.expect(maxDiff < 0.05, "fbank max abs diff < 0.05 (\(maxDiff))")
        t.expect(SpeakerFbank.logMel(pcm: [Float](repeating: 0, count: 100)).isEmpty, "shorter than one frame -> empty")
        t.expect(SpeakerFbank.logMel(pcm: [Float.nan] + [Float](repeating: 0.1, count: 1000)).isEmpty, "non-finite input -> empty")

        // 2) CMN 与窗口
        t.section("windows", "CMN zero-mean; windows tile short audio and slide over long audio")
        let cm = SpeakerFbank.cmn(mine, frames: frames)
        var colMeanMax: Float = 0
        for b in 0..<80 { var s: Float = 0; for f in 0..<frames { s += cm[f * 80 + b] }; colMeanMax = max(colMeanMax, abs(s / Float(frames))) }
        t.expect(colMeanMax < 1e-3, "CMN column means ~0 (\(colMeanMax))")
        let short = SpeakerFbank.windows(cmnFeatures: cm, frames: frames)
        t.expect(short.count == 1 && short[0].count == 300 * 80, "short audio -> one tiled 300-frame window")
        t.expect(Array(short[0][(frames * 80)..<((frames + 1) * 80)]) == Array(cm[0..<80]), "tiling wraps to the first frame")
        let longFrames = 800
        let long = SpeakerFbank.windows(cmnFeatures: [Float](repeating: 0, count: longFrames * 80), frames: longFrames)
        t.expect(long.count == 5 && long.allSatisfy { $0.count == 300 * 80 }, "800 frames -> 5 windows (\(long.count))")
        t.expect(SpeakerFbank.windows(cmnFeatures: [], frames: 0).isEmpty, "no frames -> no windows")

        // 3) 数学与编码
        t.section("math", "cosine, mean, template encode/decode")
        t.expect(SpeakerMath.cosine(unit(1), unit(1)) == 1, "cosine of identical = 1")
        t.expect(abs(SpeakerMath.cosine(unit(1), unit(2))!) < 1e-6, "orthogonal = 0")
        t.expect(SpeakerMath.cosine([0, 0], [0, 0]) == nil, "zero vector -> nil")
        t.expect(SpeakerMath.cosine([1, .nan], [1, 2]) == nil, "NaN -> nil")
        t.expect(SpeakerMath.cosine([1, 2], [1, 2, 3]) == nil, "length mismatch -> nil")
        let tpl = SpeakerTemplate(utterances: 3, embedding: unit(5, noise: 0.2))!
        t.expect(SpeakerTemplate.decode(tpl.encoded()) == tpl, "template round-trips")
        t.expect(abs(SpeakerMath.norm(tpl.embedding) - 1) < 1e-5, "template stored normalised")
        var bad = tpl.encoded(); bad[0] = 0x58
        t.expect(SpeakerTemplate.decode(bad) == nil, "bad magic -> nil")
        t.expect(SpeakerTemplate.decode(tpl.encoded().dropLast()) == nil, "truncated -> nil")
        t.expect(SpeakerTemplate.decode(tpl.encoded(), expectedVersion: "other") == nil, "other model version -> nil")
        t.expect(SpeakerTemplate.decode(Data()) == nil, "empty -> nil")
        t.expect(SpeakerTemplate(utterances: 3, embedding: [Float](repeating: 0, count: 256)) == nil, "zero template refused")
        t.expect(SpeakerTemplate(utterances: 3, embedding: [1, 2]) == nil, "wrong dimension refused")

        // 4) 登记
        t.section("enrolment", "three correct, consistent phrases build a template; anything else is rejected")
        let speech = synthPCM(kind: 0, count: 16000 * 2)
        let phrase = "apple river garden"
        let me = unit(10, noise: 0.1, seed: 1)
        var enrol = SpeakerEnrolment(embedder: ScriptedEmbedder([me, unit(10, noise: 0.1, seed: 2), unit(10, noise: 0.1, seed: 3)]))
        t.expect(enrol.add(expected: phrase, heard: "apple river garden", sample: speech) == .accepted(remaining: 2), "first phrase accepted")
        t.expect(enrol.add(expected: phrase, heard: "apple river", sample: speech) == .rejected(.wrongPhrase), "wrong words rejected, no embedding used")
        t.expect(enrol.add(expected: phrase, heard: "Apple, river garden.", sample: [Float](repeating: 0.2, count: 3000)) == .rejected(.tooShort), "short audio rejected")
        t.expect(enrol.add(expected: phrase, heard: "apple river garden", sample: speech) == .accepted(remaining: 1), "second accepted")
        if case .complete(let done) = enrol.add(expected: phrase, heard: "apple river garden", sample: speech) {
            t.expect(done.utterances == 3 && done.modelVersion == SpeakerVerification.modelVersion, "third completes a 3-utterance template")
        } else { t.expect(false, "third completes") }
        var mixed = SpeakerEnrolment(embedder: ScriptedEmbedder([unit(10), unit(77)]))
        _ = mixed.add(expected: phrase, heard: phrase, sample: speech)
        t.expect(mixed.add(expected: phrase, heard: phrase, sample: speech) == .rejected(.inconsistent), "a different voice mid-enrolment is rejected")
        var noModel = SpeakerEnrolment(embedder: ScriptedEmbedder([]))
        t.expect(noModel.add(expected: phrase, heard: phrase, sample: speech) == .rejected(.modelUnavailable), "model failure rejected")

        // 5) 比对与失败即关
        t.section("verifier", "threshold, fail closed without model/template/enough speech")
        let store = MemoryStore()
        let none = CoreMLSpeakerVerifier(embedder: ScriptedEmbedder([], fallback: unit(10)), store: store)
        t.expect(!none.isAvailable, "no template -> unavailable (no microphone)")
        t.expect(none.verify(sample: speech, purpose: .unlockAssist) == .unavailable, "no template -> .unavailable")
        _ = store.write(SpeakerTemplate(utterances: 3, embedding: unit(10))!)
        none.refresh()
        t.expect(none.isAvailable, "template -> available after refresh")
        t.expect(none.verify(sample: speech, purpose: .unlockAssist) == .sameSpeaker, "identical embedding -> same")
        let other = CoreMLSpeakerVerifier(embedder: ScriptedEmbedder([], fallback: unit(200)), store: store)
        t.expect(other.verify(sample: speech, purpose: .unlockAssist) == .differentSpeaker, "orthogonal embedding -> different")
        t.expect(none.verify(sample: [Float](repeating: 0, count: 32000), purpose: .unlockAssist) == .unavailable, "silence -> unavailable")
        t.expect(none.verify(sample: Array(speech.prefix(4000)), purpose: .unlockAssist) == .unavailable, "too short -> unavailable")
        t.expect(none.verify(sample: [], purpose: .unlockAssist) == .unavailable, "empty -> unavailable")
        let dead = CoreMLSpeakerVerifier(embedder: ScriptedEmbedder([], fallback: nil), store: store)
        t.expect(dead.verify(sample: speech, purpose: .unlockAssist) == .unavailable, "model failure -> unavailable, not different")
        let edge = SpeakerVerification.provisionalCosineThreshold
        func vec(cos c: Float) -> [Float] { var v = [Float](repeating: 0, count: 256); v[10] = c; v[11] = (1 - c * c).squareRoot(); return v }
        t.expect(CoreMLSpeakerVerifier(embedder: ScriptedEmbedder([], fallback: vec(cos: edge + 0.01)), store: store)
            .verify(sample: speech, purpose: .unlockAssist) == .sameSpeaker, "just above threshold -> same")
        t.expect(CoreMLSpeakerVerifier(embedder: ScriptedEmbedder([], fallback: vec(cos: edge - 0.01)), store: store)
            .verify(sample: speech, purpose: .unlockAssist) == .differentSpeaker, "just below threshold -> different")
        // 声纹单独不放行：整轮挑战里，字不对就算说话人对也不过。
        var round = VoiceprintChallenge(phrase: phrase, purpose: .unlockAssist, issuedAt: 0)
        t.expect(round.finish(heard: "apple river", verdict: .sameSpeaker, at: 1) == .failed(.wrongPhrase), "right voice, wrong words -> fail")

        // 6) 真模型（有 SPEAKER_MODEL 才跑）
        if let path = ProcessInfo.processInfo.environment["SPEAKER_MODEL"] {
            t.section("coreml", "Core ML end to end against torch/Core ML reference")
            guard let model = CoreMLSpeakerEmbedder(compiledModelURL: URL(fileURLWithPath: path)) else {
                t.expect(false, "model loads"); t.finish(); return
            }
            let e = fixture["embedding"] as! [String: Any]
            let pcm = synthPCM(kind: e["kind"] as! Int, count: e["samples"] as! Int)
            let f = SpeakerFbank.frameCount(samples: pcm.count)
            t.expect(f == e["frames"] as! Int, "300 frames")
            let window = SpeakerFbank.windows(cmnFeatures: SpeakerFbank.cmn(SpeakerFbank.logMel(pcm: pcm), frames: f), frames: f)[0]
            let started = DispatchTime.now().uptimeNanoseconds
            let mine = model.embedding(window: window)
            let firstMs = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e6
            t.expect(mine != nil && mine!.count == 256, "256-d embedding")
            let torchRef = (e["torch"] as! [Double]).map(Float.init), coremlRef = (e["coreml"] as! [Double]).map(Float.init)
            let vsTorch = SpeakerMath.cosine(mine!, torchRef)!, vsCoreML = SpeakerMath.cosine(mine!, coremlRef)!
            print("swift front end + Core ML vs torch cosine \(vsTorch), vs python Core ML \(vsCoreML), first call \(firstMs) ms")
            t.expect(vsTorch >= 0.99, "Swift pipeline vs torch cosine >= 0.99 (\(vsTorch))")
            var times: [Double] = []
            for _ in 0..<20 {
                let s = DispatchTime.now().uptimeNanoseconds
                _ = model.embedding(window: window)
                times.append(Double(DispatchTime.now().uptimeNanoseconds - s) / 1e6)
            }
            times.sort()
            print("Core ML latency (cpu+ne, 3 s window) median \(times[10]) ms, p90 \(times[18]) ms")
            let fs = DispatchTime.now().uptimeNanoseconds
            _ = SpeakerFbank.logMel(pcm: pcm)
            print("Swift fbank 3 s: \(Double(DispatchTime.now().uptimeNanoseconds - fs) / 1e6) ms")
            // 同一个"说话人"的两段 vs 另一种信号
            let a = SpeakerEmbedding.embed(pcm: synthPCM(kind: 1, count: 16000 * 3), using: model)
            let b = SpeakerEmbedding.embed(pcm: synthPCM(kind: 1, count: 16000 * 3 + 5000), using: model)
            t.expect(a != nil && b != nil, "embed() works on synthetic speech-like audio")
            if let a, let b { print("same-signal cosine \(SpeakerMath.cosine(a, b)!)") }
        } else {
            print("SKIP coreml: set SPEAKER_MODEL to a compiled .mlmodelc")
        }
        t.finish()
    }
}
