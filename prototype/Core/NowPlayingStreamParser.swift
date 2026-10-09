// 正在播放的推送流：把 mediaremote-adapter `stream` 模式吐出的 JSON 行解析成一份现状。
// 纯逻辑，只依赖 Foundation，不碰 AppKit、不读时钟（时间由调用方传入）。
//
// 输入格式（上游 README，固定提交见 prototype/Vendor/mediaremote-adapter/UPSTREAM.md）：
//   {"type":"data","diff":false,"payload":{...}}
// payload 为空字典表示没有播放器在报告；diff 为 true 时只含变了的键，值为 null 表示该键消失。
// 我们启动时带 --no-diff --no-artwork --micros，但 diff 和秒单位也照样认，免得上游换默认值就失明。
//
// 只留下画卡片要用的几个键（白名单）。封面数据、专辑、队列等一律不进内存里的状态——
// 即使上游哪天忽略了 --no-artwork，这里也不会把几百 KB 的图留下来。

import Foundation

/// 一份「现在在放什么」。只含刘海卡片要用的字段。
struct NowPlayingInfo: Sendable, Equatable {
    /// 打开、显示用的 App：网页播放器优先用宿主 App（parentApplicationBundleIdentifier）。
    let bundleID: String
    let title: String
    let artist: String
    let isPlaying: Bool
    /// 秒；未知为 nil。
    let duration: Double?
    /// `timestamp` 那一刻已经播了多少秒。
    let elapsed: Double?
    /// 自 1970 起的秒数；`elapsed` 对应的时刻。
    let timestamp: Double?
    let rate: Double?

    /// 某个时刻（自 1970 起的秒）的进度 0...1。时长或位置未知时为 nil。
    func progress(atEpoch now: Double) -> Double? {
        guard let duration, duration.isFinite, duration > 0, let elapsed, elapsed.isFinite else { return nil }
        var position = elapsed
        if isPlaying, let timestamp, timestamp.isFinite, now.isFinite {
            let speed = (rate.map { $0.isFinite && $0 > 0 ? $0 : 1 }) ?? 1
            position += max(0, now - timestamp) * speed
        }
        return min(1, max(0, position / duration))
    }
}

/// 一行解析的结果。
enum NowPlayingParse: Equatable {
    /// 坏行、不是数据行、超长：忽略，现状不变。
    case ignored
    /// 现状更新；nil 表示没有播放器（停了、关了，或只剩无标题的媒体）。
    case update(NowPlayingInfo?)
}

/// 有状态的行解析器：diff 行要叠在上一份完整现状上。调用方串行使用。
struct NowPlayingStreamParser {
    /// 单行上限。--no-artwork 下一行通常不到 2 KB；超过就当坏行扔掉，不去解析。
    static let maxLineBytes = 64 * 1024
    /// 标题、艺人截断长度，和直接问 Music / Spotify 那条路一致。
    static let maxTextLength = 256

    private enum Field: Equatable {
        case text(String)
        case number(Double)
        case flag(Bool)
    }

    /// 只认这些键；别的（尤其 artworkData）连读都不读进状态。
    private static let retainedKeys: Set<String> = [
        "bundleIdentifier", "parentApplicationBundleIdentifier", "title", "artist", "playing",
        "duration", "elapsedTime", "durationMicros", "elapsedTimeMicros", "timestampEpochMicros", "playbackRate",
    ]

    private var fields: [String: Field] = [:]

    init() {}

    /// 当前保留的键名（测试用：确认封面等没有留下来）。
    var retainedFieldNames: Set<String> { Set(fields.keys) }

    mutating func consume(_ line: String) -> NowPlayingParse {
        guard line.utf8.count <= Self.maxLineBytes else { return .ignored }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any] else { return .ignored }
        let diff = object["diff"] as? Bool ?? false
        if !diff { fields = [:] }
        for (key, value) in payload where Self.retainedKeys.contains(key) {
            if value is NSNull { fields[key] = nil; continue }
            if let field = Self.field(key: key, value: value) { fields[key] = field } else { fields[key] = nil }
        }
        return .update(info)
    }

    private static func field(key: String, value: Any) -> Field? {
        switch key {
        case "playing":
            return (value as? Bool).map(Field.flag)
        case "bundleIdentifier", "parentApplicationBundleIdentifier", "title", "artist":
            guard let text = value as? String else { return nil }
            return .text(String(text.prefix(maxTextLength)))
        default:
            // JSONSerialization 把 true/false 也给成 NSNumber；数值键只收真正的数。
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let double = number.doubleValue
            return double.isFinite ? .number(double) : nil
        }
    }

    private func text(_ key: String) -> String? {
        if case .text(let value)? = fields[key], !value.isEmpty { return value }
        return nil
    }
    private func number(_ key: String) -> Double? {
        if case .number(let value)? = fields[key] { return value }
        return nil
    }

    /// 由保留下来的键拼出现状。没有标题或没有来源 App 就当没有播放器。
    var info: NowPlayingInfo? {
        guard let title = text("title"),
              let bundle = text("parentApplicationBundleIdentifier") ?? text("bundleIdentifier") else { return nil }
        let playing: Bool
        if case .flag(let value)? = fields["playing"] { playing = value } else { playing = false }
        let duration = number("durationMicros").map { $0 / 1_000_000 } ?? number("duration")
        let elapsed = number("elapsedTimeMicros").map { $0 / 1_000_000 } ?? number("elapsedTime")
        let timestamp = number("timestampEpochMicros").map { $0 / 1_000_000 }
        return NowPlayingInfo(bundleID: bundle, title: title, artist: text("artist") ?? "", isPlaying: playing,
                              duration: duration, elapsed: elapsed, timestamp: timestamp, rate: number("playbackRate"))
    }
}

/// 把子进程 stdout 的字节流切成行。行内容不出这个缓冲区就被解析掉；超长行整行丢弃。
struct NowPlayingLineBuffer {
    private var pending = Data()
    /// 当前这一行已经超长，丢到下一个换行为止。
    private var discarding = false

    init() {}

    mutating func append(_ chunk: Data) -> [String] {
        var lines: [String] = []
        var start = chunk.startIndex
        while let newline = chunk[start...].firstIndex(of: 0x0A) {
            let piece = chunk[start..<newline]
            if discarding {
                discarding = false
            } else if pending.count + piece.count <= NowPlayingStreamParser.maxLineBytes {
                pending.append(piece)
                if let line = String(data: pending, encoding: .utf8) { lines.append(line) }
            }
            pending.removeAll(keepingCapacity: true)
            start = chunk.index(after: newline)
        }
        let rest = chunk[start...]
        if !discarding {
            if pending.count + rest.count > NowPlayingStreamParser.maxLineBytes {
                pending.removeAll(keepingCapacity: false)
                discarding = true
            } else {
                pending.append(rest)
            }
        }
        return lines
    }
}

// MARK: - 封面（只走 adapter 的 get，推送流仍带 --no-artwork）

extension NowPlayingInfo {
    /// 曲目身份：来源 App + 歌名 + 歌手。暂停、继续、进度变化不改它，换曲才变。
    var artworkTrackKey: String { "\(bundleID)\u{1F}\(title)\u{1F}\(artist)" }
}

/// adapter `get` 一次的输出里的封面部分。输出是一个 JSON 对象，封面是 base64 字符串（`artworkData`）。
/// 上限 4 MB（解码后的图片字节数）；超了、不是图片字段、整份输出过大，都当没有封面。
struct NowPlayingArtworkPayload: Sendable, Equatable {
    /// 解码后的图片上限。只在 get 这条路放宽；推送流那条 64 KB 行上限不动。
    static let maxImageBytes = 4 * 1024 * 1024
    /// 整份 get 输出的读取上限：4 MB 的 base64 约 5.33 MB，再留一点给其它键。
    static let maxOutputBytes = 6 * 1024 * 1024

    let title: String?
    let artist: String?
    let mimeType: String?
    let imageData: Data

    static func parse(_ output: Data) -> NowPlayingArtworkPayload? {
        guard !output.isEmpty, output.count <= maxOutputBytes,
              let object = (try? JSONSerialization.jsonObject(with: output)) as? [String: Any],
              let encoded = object["artworkData"] as? String else { return nil }
        // 先按长度挡掉：base64 每 4 字符 3 字节。
        guard encoded.utf8.count <= (maxImageBytes + 2) / 3 * 4 + 4,
              let image = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
              !image.isEmpty, image.count <= maxImageBytes else { return nil }
        func text(_ key: String) -> String? {
            (object[key] as? String).map { String($0.prefix(NowPlayingStreamParser.maxTextLength)) }
        }
        return NowPlayingArtworkPayload(title: text("title"), artist: text("artist"),
                                        mimeType: object["artworkMimeType"] as? String, imageData: image)
    }

    /// get 取到的是不是我们要的那首：歌名和歌手都对得上才收，免得换曲太快把上一首的封面贴给下一首。
    func matches(_ info: NowPlayingInfo) -> Bool {
        title == info.title && (artist ?? "") == info.artist
    }
}
