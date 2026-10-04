import Foundation

/// 新的恢复记录不写窗口标题。读的时候旧档里已有的标题仍可取到。
enum WS2JournalWrite {
    static func omitTitle(_ entry: [String: Any]) -> [String: Any] {
        var copy = entry
        copy.removeValue(forKey: "title")
        return copy
    }

    static func readableTitle(_ entry: [String: Any]) -> String? {
        guard let title = entry["title"] as? String else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
