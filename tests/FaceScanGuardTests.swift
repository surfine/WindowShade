// 刷脸扫描守卫（Core/FaceScanGuard.swift）：锁态重查、帧去重（Hub 的相机 / 代次 / 帧号）、路人、双阈值、模型版本、
// 认错 2 秒、唤醒合并、录入序号。
// 只验证证据怎么产生；放行仍归授权账本。
import Foundation

@main
struct FaceScanGuardTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  static let owner: [Float] = [1, 0, 0, 0]
  static let stranger: [Float] = [0, 1, 0, 0]
  static let enrolled = [FaceTemplate(embedding: [1, 0.1, 0, 0], modelVersion: "m2", enrolledAt: 1),
                         FaceTemplate(embedding: [1, -0.1, 0, 0], modelVersion: "m2", enrolledAt: 2)]

  static func frame(_ number: UInt64, at time: Double, _ embedding: [Float]?, width: Double = 0.3,
                    model: String = "m2", extra: [FaceScanFace] = [], camera: String = "cam", generation: UInt64 = 1)
    -> FaceScanFrame {
    FaceScanFrame(cameraID: camera, generation: generation, sequence: number, capturedAt: time, modelVersion: model,
                  faces: [FaceScanFace(widthFraction: width, embedding: embedding)] + extra)
  }
  static func started(_ templates: [FaceTemplate] = enrolled) -> FaceScanGuard {
    var guardian = FaceScanGuard(templates: templates)
    _ = guardian.wake(at: 0, lock: .locked, lockGeneration: 7)
    return guardian
  }
  static func isOwner(_ outcome: FaceScanGuard.Outcome) -> Bool {
    if case .owner = outcome { return true }; return false
  }

  static func main() {
    do {
      var g = started()
      expect(g.receive(frame(1, at: 0.1, owner), lock: .locked, lockGeneration: 7) == .scanning, "one owner frame is only a partial match")
      let outcome = g.receive(frame(2, at: 0.2, owner), lock: .locked, lockGeneration: 7)
      expect(outcome == .owner(FaceScanEvidence(scanID: 1, lockGeneration: 7, cameraID: "cam", generation: 1,
                                                frames: 1...2, matchedAt: 0.2, modelVersion: "m2")),
             "two owner frames in a row produce evidence bound to scan, lock generation, camera, Hub generation and frames")
      expect(g.receive(frame(3, at: 0.3, owner), lock: .locked, lockGeneration: 7) == .discarded(.finished), "a finished scan takes no more frames")
    }

    do {  // 锁态每帧重查
      var g = started()
      _ = g.receive(frame(1, at: 0.1, owner), lock: .locked, lockGeneration: 7)
      expect(g.receive(frame(2, at: 0.2, owner), lock: .unlocked, lockGeneration: 7) == .discarded(.notLocked),
             "a frame arriving after the session unlocked is discarded, not counted as owner")
      expect(g.receive(frame(3, at: 0.3, owner), lock: .locked, lockGeneration: 7) == .discarded(.noScan), "and the scan is gone")
      var u = started()
      _ = u.receive(frame(1, at: 0.1, owner), lock: .locked, lockGeneration: 7)
      expect(u.receive(frame(2, at: 0.2, owner), lock: .unknown, lockGeneration: 7) == .discarded(.notLocked), "unknown lock state is not locked")
      var r = started()
      _ = r.receive(frame(1, at: 0.1, owner), lock: .locked, lockGeneration: 7)
      expect(r.receive(frame(2, at: 0.2, owner), lock: .locked, lockGeneration: 8) == .discarded(.notLocked),
             "a frame from an earlier lock (generation changed) is discarded")
      var w = FaceScanGuard(templates: enrolled)
      expect(w.wake(at: 0, lock: .unlocked, lockGeneration: 7) == .notLocked && !w.isScanning, "waking an unlocked session starts nothing")
    }

    do {  // 帧号去重
      var g = started()
      _ = g.receive(frame(5, at: 0.1, owner), lock: .locked, lockGeneration: 7)
      expect(g.receive(frame(5, at: 0.1, owner), lock: .locked, lockGeneration: 7) == .discarded(.duplicateFrame),
             "the same frame number twice is ignored")
      expect(g.receive(frame(4, at: 0.15, owner), lock: .locked, lockGeneration: 7) == .discarded(.duplicateFrame),
             "an older frame number is ignored")
      expect(isOwner(g.receive(frame(6, at: 0.2, owner), lock: .locked, lockGeneration: 7)), "a duplicate never completes a match by itself")
    }

    do {  // Hub 的帧链：换相机或代次就是另一路，部分匹配不接上；新一代帧号从头数照收
      var g = started()
      _ = g.receive(frame(9, at: 0.1, owner), lock: .locked, lockGeneration: 7)
      expect(g.receive(frame(1, at: 0.2, owner, generation: 2), lock: .locked, lockGeneration: 7) == .scanning,
             "a reopened camera (new Hub generation) restarts the frame numbers and the partial match")
      let outcome = g.receive(frame(2, at: 0.3, owner, generation: 2), lock: .locked, lockGeneration: 7)
      expect(outcome == .owner(FaceScanEvidence(scanID: 1, lockGeneration: 7, cameraID: "cam", generation: 2,
                                                frames: 1...2, matchedAt: 0.3, modelVersion: "m2")),
             "the evidence covers only frames of one stream")
      var c = started()
      _ = c.receive(frame(5, at: 0.1, owner), lock: .locked, lockGeneration: 7)
      expect(c.receive(frame(6, at: 0.2, owner, camera: "other"), lock: .locked, lockGeneration: 7) == .scanning,
             "a frame from another camera does not complete a match started on the first")
      var m = started()
      _ = m.receive(frame(1, at: 0.1, owner), lock: .locked, lockGeneration: 7)
      _ = m.receive(frame(2, at: 0.2, stranger), lock: .locked, lockGeneration: 7)
      _ = m.receive(frame(3, at: 0.3, owner), lock: .locked, lockGeneration: 7)
      if case .owner(let evidence) = m.receive(frame(4, at: 0.4, owner), lock: .locked, lockGeneration: 7) {
        expect(evidence.frames == 3...4, "the evidence frames start at the current run, not before the stranger frame")
      } else { expect(false, "owner after a stranger frame") }
    }

    do {  // 录入序号：接在已有最大值后面，不读墙钟
      let v = "m2"
      expect(FaceTemplateSet.nextEnrollmentSequence(after: [], modelVersion: v) == 1, "the first enrolment is number 1")
      let wallClock = [FaceTemplate(embedding: [1], modelVersion: v, enrolledAt: 1_760_000_000.5),
                       FaceTemplate(embedding: [1], modelVersion: "other", enrolledAt: 9e9)]
      let next = FaceTemplateSet.nextEnrollmentSequence(after: wallClock, modelVersion: v)
      expect(next == 1_760_000_001, "a new enrolment still sorts after an old wall-clock template of the same version")
      let same = [FaceTemplate(embedding: [1, 0], modelVersion: v, enrolledAt: 1_760_000_000),
                  FaceTemplate(embedding: [0, 1], modelVersion: v, enrolledAt: next)]
      expect(!FaceScanGuard(templates: same).isOwner([1, 0.3], modelVersion: v)
               && FaceScanGuard(templates: same).isOwner([0.3, 1], modelVersion: v),
             "the sequenced enrolment is the latest one")
    }

    do {  // 平均模板改成 init 里算一次：与原来每帧重算的结果逐个相同（固定种子的随机向量、混版本混维度）
      struct LCG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
      }
      func legacy(_ templates: [FaceTemplate], _ e: [Float], _ version: String, _ threshold: Float) -> Bool {
        let eligible = templates.filter { $0.modelVersion == version && $0.embedding.count == e.count }
        guard !eligible.isEmpty, let latest = eligible.max(by: { $0.enrolledAt < $1.enrolledAt }) else { return false }
        let normalized = eligible.map { v -> [Float] in
          let n = v.embedding.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
          return n > 0 && n.isFinite ? v.embedding.map { $0 / n } : v.embedding
        }
        var sum = [Float](repeating: 0, count: normalized[0].count)
        for v in normalized { for i in sum.indices { sum[i] += v[i] } }
        let mean = sum.map { $0 / Float(normalized.count) }
        guard let a = FaceScanGuard.cosine(e, mean), let b = FaceScanGuard.cosine(e, latest.embedding) else { return false }
        return a >= threshold && b >= threshold
      }
      var rng = LCG(state: 42)
      var agree = 0, total = 0
      for _ in 0..<200 {
        let templates = (0..<Int.random(in: 0...6, using: &rng)).map { _ in
          FaceTemplate(embedding: (0..<(Bool.random(using: &rng) ? 4 : 3)).map { _ in Float.random(in: -1...1, using: &rng) },
                       modelVersion: Bool.random(using: &rng) ? "m2" : "m1",
                       enrolledAt: Double(Int.random(in: 0...3, using: &rng)))
        }
        let guardian = FaceScanGuard(templates: templates)
        for _ in 0..<5 {
          let probe = (0..<4).map { _ in Float.random(in: -1...1, using: &rng) }
          total += 1
          if guardian.isOwner(probe, modelVersion: "m2") == legacy(templates, probe, "m2", 0.6) { agree += 1 }
        }
      }
      expect(agree == total, "precomputed references match the per-frame computation on \(total) random probes")
    }

    do {  // 非主人清掉部分匹配
      var g = started()
      _ = g.receive(frame(1, at: 0.1, owner), lock: .locked, lockGeneration: 7)
      expect(g.receive(frame(2, at: 0.2, stranger), lock: .locked, lockGeneration: 7) == .scanning, "a stranger frame does not fail at once")
      expect(g.receive(frame(3, at: 0.3, owner), lock: .locked, lockGeneration: 7) == .scanning, "the earlier partial match was cleared")
      expect(isOwner(g.receive(frame(4, at: 0.4, owner), lock: .locked, lockGeneration: 7)), "two fresh owner frames still match")
    }

    do {  // 双阈值：平均过、最近一次不过
      let templates = [FaceTemplate(embedding: [1, 0, 0, 0], modelVersion: "m2", enrolledAt: 1),
                       FaceTemplate(embedding: [1, 0, 0, 0], modelVersion: "m2", enrolledAt: 2),
                       FaceTemplate(embedding: [1, 0, 0, 0], modelVersion: "m2", enrolledAt: 3),
                       FaceTemplate(embedding: [0, 1, 0, 0], modelVersion: "m2", enrolledAt: 4)]
      let g = FaceScanGuard(templates: templates)
      let probe: [Float] = [1, 0, 0, 0]
      let mean = FaceScanGuard.cosine(probe, [0.75, 0.25, 0, 0])!
      expect(mean >= g.tuning.similarityThreshold, "precondition: probe passes against the mean template")
      expect(!g.isOwner(probe, modelVersion: "m2"), "passing the mean but failing the latest enrolled sample is not a match")
      let both = FaceScanGuard(templates: Array(templates.prefix(3)))
      expect(both.isOwner(probe, modelVersion: "m2"), "passing both is a match")
    }

    do {  // 模型版本
      let old = [FaceTemplate(embedding: owner, modelVersion: "m1", enrolledAt: 1)]
      expect(!FaceScanGuard(templates: old).isOwner(owner, modelVersion: "m2"), "templates from an older model version are excluded")
      let mixed = old + [FaceTemplate(embedding: stranger, modelVersion: "m2", enrolledAt: 0)]
      expect(!FaceScanGuard(templates: mixed).isOwner(owner, modelVersion: "m2"), "old-version templates do not pull the mean toward a match")
      expect(FaceScanGuard(templates: mixed).isOwner(stranger, modelVersion: "m2"), "same-version templates still work")
    }

    do {  // 路人：宽度 0.17
      var g = started()
      _ = g.receive(frame(1, at: 0.1, owner), lock: .locked, lockGeneration: 7)
      expect(g.receive(frame(2, at: 0.2, stranger, width: 0.17), lock: .locked, lockGeneration: 7) == .scanning,
             "a 0.17-wide stranger is a bystander")
      expect(isOwner(g.receive(frame(3, at: 0.3, owner), lock: .locked, lockGeneration: 7)), "and does not clear the owner's partial match")
      var o = started()
      _ = o.receive(frame(1, at: 0.1, owner, width: 0.17), lock: .locked, lockGeneration: 7)
      expect(o.receive(frame(2, at: 0.2, owner, width: 0.17), lock: .locked, lockGeneration: 7) == .scanning,
             "a 0.17-wide face is never a candidate, even the owner's")
      var b = started()
      let mix = frame(1, at: 0.1, owner, width: 0.18, extra: [FaceScanFace(widthFraction: 0.1, embedding: stranger)])
      _ = b.receive(mix, lock: .locked, lockGeneration: 7)
      expect(isOwner(b.receive(frame(2, at: 0.2, owner, width: 0.18), lock: .locked, lockGeneration: 7)), "0.18 counts; a small face behind is ignored")
    }

    do {  // 认错 2 秒才失败
      var g = started()
      expect(g.receive(frame(1, at: 0.5, stranger), lock: .locked, lockGeneration: 7) == .scanning, "a wrong face starts the 2 s grace")
      expect(g.receive(frame(2, at: 2.4, stranger), lock: .locked, lockGeneration: 7) == .scanning, "1.9 s of wrong face is still scanning")
      expect(g.receive(frame(3, at: 2.5, stranger), lock: .locked, lockGeneration: 7) == .failed, "2 s of wrong face fails")
      expect(g.receive(frame(4, at: 2.6, owner), lock: .locked, lockGeneration: 7) == .discarded(.finished), "a failed scan stays failed")
    }

    do {  // 唤醒风暴
      var g = FaceScanGuard(templates: enrolled)
      let wakes = [0, 0.3, 0.9, 1.5, 1.99].map { g.wake(at: $0, lock: .locked, lockGeneration: 7) }
      expect(wakes.first == .started(scanID: 1) && wakes.dropFirst().allSatisfy { $0 == .coalesced(scanID: 1) },
             "five wakes within 2 s count as one scan")
      expect(g.wake(at: 2.1, lock: .locked, lockGeneration: 7) == .started(scanID: 2), "a wake after 2 s starts a new scan")
      expect(g.wake(at: 2.2, lock: .locked, lockGeneration: 8) == .started(scanID: 3), "a new lock starts a new scan at once")
    }

    do {  // 按模型版本选阈值：Vision 特征用自己的（未标定、偏严）阈值，其余版本仍是 0.6
      let vision = FaceScanModelProfile.visionFeaturePrintVersion
      let tuning = FaceScanTuning()
      expect(tuning.similarityThreshold(for: "m2") == 0.6, "an unlisted model keeps the 0.6 default")
      expect(tuning.similarityThreshold(for: vision) == FaceScanModelProfile.visionFeaturePrint.similarityThreshold,
             "the Vision feature print uses its own threshold")
      expect(!FaceScanModelProfile.visionFeaturePrint.calibrated, "the Vision threshold is marked uncalibrated")
      expect(FaceScanModelProfile.table.allSatisfy { $0.key == $0.value.modelVersion }, "the table is keyed by each entry's own version")
      var extra = FaceScanTuning()
      extra.modelProfiles["arcface-test"] = FaceScanModelProfile(modelVersion: "arcface-test", similarityThreshold: 0.45, calibrated: false)
      expect(extra.similarityThreshold(for: "arcface-test") == 0.45 && extra.similarityThreshold(for: vision) == 0.92,
             "another backend adds one entry without touching the Vision one")
      expect(FaceScanModelProfile.visionFeaturePrint.similarityThreshold > 0.6,
             "the uncalibrated Vision threshold is stricter than the ArcFace-era default, never looser")
      // cosine([1,0.6,0,0], templates) ≈ 0.85：过 0.6，不过 Vision 的 0.92。
      let probe: [Float] = [1, 0.6, 0, 0]
      let legacy = FaceScanGuard(templates: enrolled)
      expect(legacy.isOwner(probe, modelVersion: "m2"), "0.85 passes the 0.6 default")
      let visionTemplates = enrolled.map { FaceTemplate(embedding: $0.embedding, modelVersion: vision, enrolledAt: $0.enrolledAt) }
      let strict = FaceScanGuard(templates: visionTemplates)
      expect(!strict.isOwner(probe, modelVersion: vision), "the same 0.85 fails the Vision threshold")
      expect(strict.isOwner(owner, modelVersion: vision), "a near-identical Vision embedding still matches")
      expect(!strict.isOwner(owner, modelVersion: "vision-featureprint-r1-crop1.3-224"),
             "another revision/pipeline string finds no templates")
      for bad: Float in [.nan, .infinity, 0, -0.5, 1.5] {
        var broken = FaceScanTuning()
        broken.modelProfiles = [vision: FaceScanModelProfile(modelVersion: vision, similarityThreshold: bad, calibrated: true)]
        expect(!FaceScanGuard(templates: visionTemplates, tuning: broken).isOwner(owner, modelVersion: vision),
               "an invalid threshold (\(bad)) never matches")
      }
      var nanDefault = FaceScanTuning(); nanDefault.similarityThreshold = .nan
      expect(!FaceScanGuard(templates: enrolled, tuning: nanDefault).isOwner(owner, modelVersion: "m2"),
             "a NaN default threshold never matches")
      // 整条扫描：Vision 版本下 0.85 的脸按认错计，满 2 秒失败。
      var g = FaceScanGuard(templates: visionTemplates)
      _ = g.wake(at: 0, lock: .locked, lockGeneration: 1)
      _ = g.receive(frame(1, at: 0.1, probe, model: vision), lock: .locked, lockGeneration: 1)
      expect(g.receive(frame(2, at: 2.1, probe, model: vision), lock: .locked, lockGeneration: 1) == .failed,
             "below the Vision threshold counts as a wrong face")
    }

    do {  // 模板集合：编码、校验、追加
      let v = FaceScanModelProfile.visionFeaturePrintVersion
      let a = FaceTemplate(embedding: [0.6, 0.8], modelVersion: v, enrolledAt: 10)
      let b = FaceTemplate(embedding: [0.8, 0.6], modelVersion: v, enrolledAt: 20)
      let other = FaceTemplate(embedding: [1, 0], modelVersion: "m2", enrolledAt: 30)
      let data = FaceTemplateSet.encode([a, other, b], modelVersion: v)
      expect(data.map { FaceTemplateSet.decode($0, modelVersion: v) } == [a, b], "round trip keeps only this model version")
      expect(data.map { FaceTemplateSet.decode($0, modelVersion: "m2") } == [], "a set is never read under another version")
      expect(FaceTemplateSet.encode([other], modelVersion: v) == nil, "nothing to store for this version")
      expect(FaceTemplateSet.encode([FaceTemplate(embedding: [.nan, 1], modelVersion: v, enrolledAt: 1)], modelVersion: v) == nil,
             "non-finite embeddings are not stored")
      func b64(_ v: [Float]) -> String { FaceTemplateSet.bytes(v).base64EncodedString() }
      expect(FaceTemplateSet.floats(FaceTemplateSet.bytes([0.25, -1, 3])) == [0.25, -1, 3], "float bytes round trip")
      expect(FaceTemplateSet.floats(Data([1, 2, 3])) == nil, "a truncated vector is rejected")
      let mixedDims = Data(#"{"format":1,"modelVersion":"\#(v)","templates":[{"embedding":"\#(b64([1, 0]))","enrolledAt":1},{"embedding":"\#(b64([1, 0, 0]))","enrolledAt":2}]}"#.utf8)
      expect(FaceTemplateSet.decode(mixedDims, modelVersion: v).isEmpty, "a stored set with mixed dimensions is dropped whole")
      expect(FaceTemplateSet.decode(Data("garbage".utf8), modelVersion: v).isEmpty, "garbage reads as no templates")
      let wrongFormat = Data(#"{"format":2,"modelVersion":"\#(v)","templates":[{"embedding":"\#(b64([1, 0]))","enrolledAt":1}]}"#.utf8)
      expect(FaceTemplateSet.decode(wrongFormat, modelVersion: v).isEmpty, "an unknown format reads as no templates")
      let many = (0..<25).map { FaceTemplate(embedding: [1, Float($0)], modelVersion: v, enrolledAt: Double($0)) }
      let capped = FaceTemplateSet.appending(many, to: [a], modelVersion: v)
      expect(capped.count == FaceTemplateSet.capacity && capped.first?.enrolledAt == 6 && capped.last?.enrolledAt == 24,
             "appending keeps the newest \(FaceTemplateSet.capacity)")
      let redimensioned = FaceTemplateSet.appending([FaceTemplate(embedding: [1, 0, 0], modelVersion: v, enrolledAt: 40)],
                                                    to: [a, b], modelVersion: v)
      expect(redimensioned.count == 1 && redimensioned[0].embedding.count == 3, "a new dimension replaces the old set")
      expect(FaceTemplateSet.appending([], to: [a, other], modelVersion: v) == [a], "appending nothing keeps the valid old set")
    }

    if failures > 0 { print("\(failures) failure(s)"); exit(1) }
    print("FaceScanGuardTests passed (evidence only, never unlock)")
  }
}
