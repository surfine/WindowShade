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
