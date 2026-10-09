import Foundation

/// Personal, dialect-specific geometry templates. No transcription or security use.
struct WS2MouthFrame: Codable, Equatable, Sendable {
    var time: Double
    var values: [Double]
    /// Translation/scale normalization, keeping lip motion relative to mouth width.
    static func make(time: Double, points: [CGPoint]) -> Self? {
        guard time.isFinite, points.count >= 8, points.count <= 64,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }),
              let lo = points.map(\.x).min(), let hi = points.map(\.x).max(), hi - lo > 0.01 else { return nil }
        let cx = points.map(\.x).reduce(0, +) / Double(points.count)
        let cy = points.map(\.y).reduce(0, +) / Double(points.count)
        let width = hi - lo
        return Self(time: time, values: points.flatMap { [($0.x - cx) / width, ($0.y - cy) / width] })
    }
}
struct WS2MouthRecording: Codable, Equatable, Sendable {
    let session: UUID
    let commandID: String? // nil is an explicit no-command holdout
    let frames: [WS2MouthFrame]
    var valid: Bool {
        guard (8...100).contains(frames.count), let first = frames.first, let last = frames.last,
              (0.25...4).contains(last.time - first.time), !first.values.isEmpty,
              first.values.count <= 128 else { return false }
        return frames.enumerated().allSatisfy { i, f in
            f.time.isFinite && f.values.count == first.values.count && f.values.allSatisfy { $0.isFinite && abs($0) <= 4 }
                && (i == 0 || (f.time > frames[i-1].time && f.time - frames[i-1].time <= 0.25))
        }
    }
}
/// 一次取帧尝试：取到嘴形就带 frame，没找到脸就是 nil。time 与 WS2MouthFrame.time 同一时间轴（秒）。
struct WS2MouthAttempt: Equatable, Sendable {
    var time: Double
    var frame: WS2MouthFrame?
}
enum WS2MouthQualityResult: Equatable, Sendable {
    case accepted(frames: [WS2MouthFrame])
    /// 质量不够，请用户重录。
    case reRecord(Reason)
    enum Reason: Equatable, Sendable {
        case tooFewFrames
        case faceMissing
    }
}
/// 录制质量门。纯逻辑，不碰相机。思路参考 lipflow dictation.py（MIT）。
enum WS2MouthQuality {
    /// 至少要有的取帧次数；少于这个数直接重录（lipflow dictation.py，MIT）。
    static let minimumAttempts = 12
    /// 有脸的帧至少占 40%，以整数百分比比较避免浮点边界（lipflow dictation.py，MIT）。
    static let minimumFacePercent = 40
    /// 松手后继续收 0.4 秒，更晚的丢掉（lipflow dictation.py，MIT）。
    static let postRollSeconds = 0.4

    static func evaluate(_ attempts: [WS2MouthAttempt], releasedAt: Double) -> WS2MouthQualityResult {
        guard releasedAt.isFinite else { return .reRecord(.tooFewFrames) }
        let limit = releasedAt + postRollSeconds
        let kept = attempts.filter { $0.time.isFinite && $0.time <= limit }
        guard kept.count >= minimumAttempts else { return .reRecord(.tooFewFrames) }
        let frames = kept.compactMap(\.frame)
        guard frames.count * 100 >= kept.count * minimumFacePercent else { return .reRecord(.faceMissing) }
        return .accepted(frames: frames)
    }
}
/// 宿主用的取帧窗口：每次取帧（有脸或没脸）都记一笔，凑够录制长度加松手后 0.4 秒再交质量门。纯逻辑。
struct WS2MouthAttemptWindow: Sendable {
    /// 一次录制的名义长度（秒）。
    static let recordingSeconds = 1.5
    static let maximumAttempts = 100
    private(set) var attempts: [WS2MouthAttempt] = []

    mutating func reset() { attempts.removeAll() }

    /// 记一次取帧。时间倒退或相邻间隔超过 0.25 秒视为断流，先清空再记。
    mutating func record(_ attempt: WS2MouthAttempt) {
        guard attempt.time.isFinite else { return }
        if let last = attempts.last, attempt.time <= last.time || attempt.time - last.time > 0.25 { attempts.removeAll() }
        attempts.append(attempt)
        let horizon = Self.recordingSeconds + WS2MouthQuality.postRollSeconds + 0.3
        while attempts.count > Self.maximumAttempts || attempts.first.map({ attempt.time - $0.time > horizon }) == true {
            attempts.removeFirst()
        }
    }

    /// 窗口够长时给出松手时刻（最新一笔往前 0.4 秒）；不够长返回 nil。
    var releasedAt: Double? {
        guard let first = attempts.first, let last = attempts.last,
              last.time - first.time >= Self.recordingSeconds + WS2MouthQuality.postRollSeconds else { return nil }
        return last.time - WS2MouthQuality.postRollSeconds
    }

    /// 取帧数够就过质量门；还没够长返回 nil。
    func evaluate() -> WS2MouthQualityResult? {
        guard let releasedAt else { return nil }
        return WS2MouthQuality.evaluate(attempts, releasedAt: releasedAt)
    }
}
struct WS2MouthProfile: Codable, Sendable {
    let speech: String
    let templates: [WS2MouthRecording]
    /// Must be calibrated with independent no-command samples; defaults are experimental.
    let maximumDistance: Double
    let minimumMargin: Double
    var valid: Bool {
        ["mandarin", "cantonese", "wu"].contains(speech)
            && maximumDistance.isFinite && maximumDistance > 0 && maximumDistance <= 1
            && minimumMargin.isFinite && minimumMargin > 0 && minimumMargin <= 1
            && !templates.isEmpty && templates.count <= 120
            && templates.allSatisfy { $0.valid && $0.commandID.map { WS2SilentPhrases.starterCommandIDs.contains($0) } == true }
    }
}
enum WS2MouthMatcher {
    /// Bounded dynamic time warping; preserves real frame ordering and rejects capture gaps.
    static func distance(_ a: WS2MouthRecording, _ b: WS2MouthRecording) -> Double {
        guard a.valid, b.valid, a.frames[0].values.count == b.frames[0].values.count else { return .infinity }
        var previous = Array(repeating: Double.infinity, count: b.frames.count + 1); previous[0] = 0
        for i in 1...a.frames.count {
            var current = Array(repeating: Double.infinity, count: b.frames.count + 1)
            for j in 1...b.frames.count {
                let cost = zip(a.frames[i-1].values, b.frames[j-1].values).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(a.frames[i-1].values.count)
                current[j] = cost + min(previous[j], current[j-1], previous[j-1])
            }
            previous = current
        }
        return previous[b.frames.count] / Double(max(a.frames.count, b.frames.count))
    }
    static func match(_ sample: WS2MouthRecording, speech: String, profile: WS2MouthProfile) -> String? {
        guard profile.valid, sample.valid, speech == profile.speech else { return nil }
        var scores: [String: Double] = [:]
        for template in profile.templates {
            guard let id = template.commandID else { continue }
            scores[id] = min(scores[id] ?? .infinity, distance(sample, template))
        }
        let ranked = scores.sorted { $0.value < $1.value }
        guard ranked.count >= 2, let best = ranked.first, best.value <= profile.maximumDistance,
              ranked[1].value - best.value >= profile.minimumMargin else { return nil }
        return best.key
    }
    struct Evaluation: Codable {
        var confusion: [String: [String: Int]] = [:]
        var noCommandSamples = 0
        var falseTriggers = 0
        var captureDurations: [Double] = []
        var rejectedInvalidSamples = 0
    }
    static func evaluate(_ holdout: [WS2MouthRecording], speech: String, profile: WS2MouthProfile) -> Evaluation? {
        let training = Set(profile.templates.map(\.session))
        guard profile.valid, speech == profile.speech, !holdout.isEmpty,
              holdout.allSatisfy({ !training.contains($0.session) }) else { return nil }
        var result = Evaluation()
        for sample in holdout {
            guard sample.valid else { result.rejectedInvalidSamples += 1; continue }
            let prediction = match(sample, speech: speech, profile: profile)
            let expected = sample.commandID ?? "no_command"
            result.confusion[expected, default: [:]][prediction ?? "unknown", default: 0] += 1
            if sample.commandID == nil { result.noCommandSamples += 1; if prediction != nil { result.falseTriggers += 1 } }
            result.captureDurations.append(sample.frames.last!.time - sample.frames.first!.time)
        }
        return result
    }
}
