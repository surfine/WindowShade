// WindowShade 2.1 · 个人口令。第一次只认封闭目录里的前 6 条。
// 普通话、粤语、吴语各用调用者传入的词。这里不读麦克风、不执行、不解锁。
import Foundation

enum WS2SilentSpeech: String, Hashable, Sendable {
    case mandarin, cantonese, wu
}

struct WS2SilentPhraseProfile: Equatable, Sendable {
    var speech: WS2SilentSpeech
    /// 目录 id → 这个人自己的词。没写、或写空的，保持未录。
    var words: [String: String]
}

struct WS2SilentPhraseSample: Equatable, Sendable {
    var speech: WS2SilentSpeech?
    /// 这一帧摄像头对上的词。没有摄像头时不使用。
    var seenWord: String?
    var cameraAvailable: Bool
    /// 麦克风读到的词。静音失败时不拿它来补。
    var microphoneWord: String?
}

enum WS2SilentPhraseMatch: Equatable, Sendable {
    case unknown
    /// 和点选同一条命令。只交出 id，不确认、不执行。
    case sameAsTap(commandID: String)
}

enum WS2SilentPhrases {
    /// 目录顺序里的前 6 条：四个入口，然后上一项、下一项。
    static var starterCommandIDs: [String] {
        WS2SilentCatalog.commands.prefix(6).map(\.id)
    }

    static func match(_ sample: WS2SilentPhraseSample, profile: WS2SilentPhraseProfile) -> WS2SilentPhraseMatch {
        // 没有摄像头就不猜。麦克风读数不参与，也不作为退路。
        _ = sample.microphoneWord
        guard sample.cameraAvailable else { return .unknown }
        guard let speech = sample.speech, speech == profile.speech else { return .unknown }
        guard let word = sample.seenWord, !word.isEmpty else { return .unknown }
        let hits = starterCommandIDs.filter { id in
            guard let recorded = profile.words[id], !recorded.isEmpty else { return false }
            return recorded == word
        }
        guard hits.count == 1, let id = hits.first else { return .unknown }
        return .sameAsTap(commandID: id)
    }
}

struct WS2SilentPhraseBuffer: Sendable {
    private(set) var mode: WS2SilentMode
    private var held: WS2SilentPhraseSample?

    init(mode: WS2SilentMode = .command) {
        self.mode = mode
        self.held = nil
    }

    var isEmpty: Bool { held == nil }

    /// 换模式就丢掉还没变成提案的那一帧。同一种模式再设一次不清。
    mutating func setMode(_ next: WS2SilentMode) {
        guard next != mode else { return }
        mode = next
        held = nil
    }

    mutating func hold(_ sample: WS2SilentPhraseSample) {
        held = sample
    }

    /// 口令只在命令模式里对上个人词表。对上了也只是点选那条的 id。
    func match(profile: WS2SilentPhraseProfile) -> WS2SilentPhraseMatch {
        guard mode == .command, let held else { return .unknown }
        return WS2SilentPhrases.match(held, profile: profile)
    }
}
