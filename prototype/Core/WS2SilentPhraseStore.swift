import Foundation

// 个人口令的持久化（2.1 六口令的前半：把「哪条命令配哪个词」存在本机）。
// 模板（这个人怎么说这个词的嘴形数据）仍在隔离工具里录，不进 App；这里只有文字词与方言选择。
// 读到的词与用户配置的词完全相等才命中（WS2SilentPhrases.match），不做模糊匹配。

enum WS2SilentPhraseStore {
    static let defaultsKey = "Silent.phrases.v1"

    /// 存的形状：方言 + 命令 id → 词。空词不存。
    private struct Payload: Codable {
        var speech: String
        var words: [String: String]
    }

    static func load() -> WS2SilentPhraseProfile {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let speech = WS2SilentSpeech(rawValue: payload.speech) else {
            return WS2SilentPhraseProfile(speech: .mandarin, words: [:])
        }
        var words: [String: String] = [:]
        for id in WS2SilentPhrases.starterCommandIDs {
            if let word = payload.words[id]?.trimmingCharacters(in: .whitespaces), !word.isEmpty {
                words[id] = word
            }
        }
        return WS2SilentPhraseProfile(speech: speech, words: words)
    }

    /// 整份保存。只收 starter 六条；重复词拒绝（两条命令配同一个词就分不清了）。
    @discardableResult
    static func save(_ profile: WS2SilentPhraseProfile) -> Bool {
        var words: [String: String] = [:]
        var seen = Set<String>()
        for id in WS2SilentPhrases.starterCommandIDs {
            guard let raw = profile.words[id] else { continue }
            let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty, word.count <= 12 else { continue }
            guard seen.insert(word).inserted else { return false }
            words[id] = word
        }
        guard let data = try? JSONEncoder().encode(Payload(speech: profile.speech.rawValue, words: words)) else { return false }
        UserDefaults.standard.set(data, forKey: defaultsKey)
        return true
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
