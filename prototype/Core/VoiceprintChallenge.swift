import Foundation

/// 声纹辅助（D11 ②，Aaron 10-03 / 10-29）：只加不减，不单独放行，不顶替手机或手表。纯逻辑。
///
/// - 每一轮出一句新的随机短语（挡录音重放）；念对了字、说话人也对上，这一轮才算 `.matched`。
/// - 字对不对由本机语音识别判断（只确认说了什么，不证明是谁）；是不是你由 `SpeakerVerifier` 判断。
/// - 一轮只能出一次结果；超时、字不对、比对不可用、比对说不是你，都是没过。
/// - 用途有两个：锁屏上补脸的分数（`.unlockAssist`），以及以后放行高风险的编程会话动作（`.highRiskApproval`）。
///   第二个只留了接缝，今天没有任何审批会来问它（见 `VoiceprintPurpose`）。
enum VoiceprintPurpose: Equatable, Sendable {
    case unlockAssist
    /// 接缝：高风险的编程会话动作可以要求再念一句。今天没接任何审批，不要从这里放行任何东西。
    case highRiskApproval
}

/// 说话人比对的结果。
enum SpeakerVerdict: Equatable, Sendable {
    case sameSpeaker
    case differentSpeaker
    /// 没有能用的比对模型、或这一段声音不够用。
    case unavailable
}

/// 可替换的说话人比对。真实现要一个能在本机跑的说话人模型（Core ML），并按 authentication-boundaries 另做防伪评估。
protocol SpeakerVerifier: Sendable {
    /// 这台 Mac 上能不能比对。不能就不开麦克风、不问短语。
    var isAvailable: Bool { get }
    /// 拿这一轮录到的声音特征和登记的比。`sample` 只活在这一次调用里，不存、不写日志。
    func verify(sample: [Float], purpose: VoiceprintPurpose) -> SpeakerVerdict
}

/// NOT YET REAL：仓库里还没有本机说话人比对模型。它永远说不可用，声纹那条路因此永远不通过（失败即关）。
/// 换成真实现之前，不要改这里让它返回 `.sameSpeaker`。
struct UnavailableSpeakerVerifier: SpeakerVerifier {
    var isAvailable: Bool { false }
    func verify(sample: [Float], purpose: VoiceprintPurpose) -> SpeakerVerdict { .unavailable }
}

/// 随机短语。词表是常用、好念、不易混淆的词；每轮由调用方给随机源（生产用 SystemRandomNumberGenerator）。
enum VoiceprintPhrase {
    static let chineseWords = [
        "苹果", "月亮", "火车", "蓝天", "小猫", "西瓜", "书包", "雨伞", "灯塔", "钢琴",
        "森林", "风筝", "海边", "面包", "星星", "邮票", "台灯", "茶杯", "公园", "白云",
    ]
    static let englishWords = [
        "apple", "river", "garden", "yellow", "window", "rocket", "silver", "pencil", "orange", "forest",
        "candle", "violin", "bridge", "planet", "harbor", "copper", "meadow", "lantern", "puzzle", "tiger",
    ]
    static let wordCount = 3

    /// 不重复地抽 `wordCount` 个词。中文直接相连，英文用空格隔开。
    static func make<R: RandomNumberGenerator>(english: Bool, using generator: inout R) -> String {
        var pool = english ? englishWords : chineseWords
        var picked: [String] = []
        for _ in 0..<min(wordCount, pool.count) {
            let index = Int.random(in: 0..<pool.count, using: &generator)
            picked.append(pool.remove(at: index))
        }
        return picked.joined(separator: english ? " " : "")
    }

    /// 比较用：去掉空白和标点、转小写、全角转半角。识别结果多出或少了标点不算错，字错了就是错。
    static func normalized(_ text: String) -> String {
        let folded = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return String(folded.lowercased().unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0)
                && !CharacterSet.symbols.contains($0)
        }.map(Character.init))
    }

    static func matches(expected: String, heard: String) -> Bool {
        let want = normalized(expected), got = normalized(heard)
        return !want.isEmpty && want == got
    }
}

/// 一轮短语挑战。时间是调用方给的单调秒。
struct VoiceprintChallenge: Equatable, Sendable {
    enum Failure: String, Equatable, Sendable {
        case timedOut = "timeout"
        case wrongPhrase = "wrong-phrase"
        case differentSpeaker = "different-speaker"
        case verifierUnavailable = "verifier-unavailable"
        /// 同一轮交第二次结果（重放或重复回调）。
        case alreadyFinished = "already-finished"
        case cancelled = "cancelled"
    }
    enum Outcome: Equatable, Sendable {
        case matched
        case failed(Failure)
    }

    /// 实验参数：念一句短语给多久。
    static let defaultWindow: Double = 8

    let phrase: String
    let purpose: VoiceprintPurpose
    let issuedAt: Double
    let deadline: Double
    private(set) var outcome: Outcome?

    init(phrase: String, purpose: VoiceprintPurpose, issuedAt: Double, window: Double = VoiceprintChallenge.defaultWindow) {
        self.phrase = phrase
        self.purpose = purpose
        self.issuedAt = issuedAt
        let safe = window.isFinite && window > 0 ? window : Self.defaultWindow
        deadline = issuedAt.isFinite ? issuedAt + safe : -Double.infinity
    }

    var isFinished: Bool { outcome != nil }

    /// 识别和比对都回来了：交结果。字先对、再看说话人；任何一项不成都是没过。
    mutating func finish(heard: String, verdict: SpeakerVerdict, at now: Double) -> Outcome {
        if outcome != nil { return .failed(.alreadyFinished) }
        let result: Outcome
        if !now.isFinite || now < issuedAt || now > deadline {
            result = .failed(.timedOut)
        } else if !VoiceprintPhrase.matches(expected: phrase, heard: heard) {
            result = .failed(.wrongPhrase)
        } else {
            switch verdict {
            case .sameSpeaker: result = .matched
            case .differentSpeaker: result = .failed(.differentSpeaker)
            case .unavailable: result = .failed(.verifierUnavailable)
            }
        }
        outcome = result
        return result
    }

    /// 到点、锁态变了、睡眠：这一轮作废。
    mutating func cancel(_ reason: Failure = .cancelled) -> Outcome {
        if let outcome { return outcome }
        let result = Outcome.failed(reason)
        outcome = result
        return result
    }

    /// 交给闸门的那一项。
    var gateValue: FaceAutofill.Voiceprint {
        switch outcome {
        case nil: return .notAsked
        case .matched?: return .matched
        case .failed(.verifierUnavailable)?: return .unavailable
        case .failed?: return .failed
        }
    }
}

/// 攻击矩阵（硬要求 4）：五种攻击，各自的真机结果。设置里的风险说明只按这张表写——
/// 没测过的不说挡得住。Aaron 在真机上填 tools/probes/face-attack-matrix.json，再照抄到这里
/// （tests/run-face-autofill-tests.sh 会核对两边一致）。
enum FaceAttackMatrix {
    enum Attack: String, CaseIterable, Sendable {
        case photo
        case phoneScreen = "phone-screen"
        case video
        case differentPerson = "different-person"
        case differentPhone = "different-phone"
    }
    enum Status: String, Equatable, Sendable {
        case notRun = "not_run"
        /// 实测挡住了（附证据）。
        case blocked
        /// 实测没挡住。
        case notBlocked = "not_blocked"
        case inconclusive
    }
    struct Row: Equatable, Sendable {
        let attack: Attack
        let status: Status
        /// 哪次真机、记在哪；没测就是 nil。
        let evidence: String?
    }

    /// 今天的实测结果：一项都没测。
    static let current: [Row] = Attack.allCases.map { Row(attack: $0, status: .notRun, evidence: nil) }

    /// 风险说明能说到哪一步。
    enum Claim: Equatable, Sendable {
        /// 有没测的：只能说「实验，还没针对这几种攻击测过」。
        case untested
        /// 有测出来挡不住的：要明说挡不住哪几种。
        case knownWeak([Attack])
        /// 五种都实测挡住、都有证据。
        case allBlocked
    }

    static func claim(_ rows: [Row] = current) -> Claim {
        let byAttack = Dictionary(rows.map { ($0.attack, $0) }, uniquingKeysWith: { first, _ in first })
        let weak = Attack.allCases.filter { byAttack[$0]?.status == .notBlocked }
        if !weak.isEmpty { return .knownWeak(weak) }
        let proven = Attack.allCases.allSatisfy { attack in
            guard let row = byAttack[attack], row.status == .blocked, let evidence = row.evidence else { return false }
            return !evidence.isEmpty
        }
        return proven ? .allBlocked : .untested
    }
}
