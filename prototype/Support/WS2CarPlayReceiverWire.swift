import Foundation

// 外部接收器的 WebSocket 线协议（对端是独立进程，见 docs/handoff/ws2-reuse-2026-10-07/carplay.md）。
// 这里只有字节格式：小端二进制媒体帧 + 文本 JSON 控制消息。纯解析，不碰网络、不碰窗口。
// 线格式属于协议事实；实现是原创 Swift，不复制上游代码。

/// 接收器 → 本机的二进制媒体帧。全部小端；未知类型一律忽略，不当作错误。
enum WS2CarPlayReceiverWire {

    enum VideoCodec: UInt8 {
        case h264 = 1
        case h265 = 2
    }

    struct VideoConfig: Equatable, Sendable {
        var streamType: UInt8
        var codec: VideoCodec
        var width: Int
        var height: Int
        /// avcC（H.264）或 hvcC（HEVC）记录，原样喂给解码器。
        var codecRecord: [UInt8]
    }

    struct VideoFrame: Equatable, Sendable {
        var streamType: UInt8
        var isKeyframe: Bool
        /// Annex B 的 NAL 序列，直接进解码器转换。
        var annexB: [UInt8]
    }

    struct AudioConfig: Equatable, Sendable {
        var streamType: UInt8
        var codec: UInt8
        var sampleRate: Int
        var channels: UInt8
        var name: String
        /// AAC-LC 时是 AudioSpecificConfig；其余编码为空。
        var description: [UInt8]
    }

    struct AudioPacket: Equatable, Sendable {
        var streamType: UInt8
        var timestampMicros: UInt64
        var payload: [UInt8]
    }

    /// 解析一条二进制消息。格式不完整或类型未知返回 nil（调用方直接丢弃）。
    static func parseMedia(_ data: Data) -> MediaMessage? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }
        switch bytes[0] {
        case 1: return videoConfig(bytes).map(MediaMessage.videoConfig)
        case 2: return videoFrame(bytes).map(MediaMessage.videoFrame)
        case 3: return audioConfig(bytes).map(MediaMessage.audioConfig)
        case 4: return audioPacket(bytes).map(MediaMessage.audioPacket)
        case 5:
            guard bytes.count >= 3 else { return nil }
            return .screenActive(streamType: bytes[1], active: bytes[2] != 0)
        case 6:
            guard bytes.count >= 2 else { return nil }
            return .audioStopped(streamType: bytes[1])
        default: return nil
        }
    }

    enum MediaMessage: Equatable, Sendable {
        case videoConfig(VideoConfig)
        case videoFrame(VideoFrame)
        case audioConfig(AudioConfig)
        case audioPacket(AudioPacket)
        case screenActive(streamType: UInt8, active: Bool)
        case audioStopped(streamType: UInt8)
    }

    private static func u32LE(_ bytes: [UInt8], _ offset: Int) -> Int? {
        guard offset + 4 <= bytes.count else { return nil }
        return Int(bytes[offset])
            | Int(bytes[offset + 1]) << 8
            | Int(bytes[offset + 2]) << 16
            | Int(bytes[offset + 3]) << 24
    }

    private static func u64LE(_ bytes: [UInt8], _ offset: Int) -> UInt64? {
        guard offset + 8 <= bytes.count else { return nil }
        var value: UInt64 = 0
        for index in 0..<8 { value |= UInt64(bytes[offset + index]) << (8 * index) }
        return value
    }

    private static func videoConfig(_ bytes: [UInt8]) -> VideoConfig? {
        // [1][streamType][codec][width u32][height u32][avcC/hvcC]；记录从 11 起（与接收器网页端一致）。
        guard bytes.count >= 12, let codec = VideoCodec(rawValue: bytes[2]),
              let width = u32LE(bytes, 3), let height = u32LE(bytes, 7), width > 0, height > 0
        else { return nil }
        return VideoConfig(streamType: bytes[1], codec: codec, width: width, height: height,
                           codecRecord: Array(bytes[11...]))
    }

    private static func videoFrame(_ bytes: [UInt8]) -> VideoFrame? {
        // [2][streamType][flags][pts u64][Annex B NAL units]
        guard bytes.count >= 11, u64LE(bytes, 3) != nil else { return nil }
        return VideoFrame(streamType: bytes[1], isKeyframe: bytes[2] & 1 != 0,
                          annexB: Array(bytes[11...]))
    }

    private static func audioConfig(_ bytes: [UInt8]) -> AudioConfig? {
        // [3][streamType][codec][sampleRate u32][channels][nameLen][name][description]
        guard bytes.count >= 9, let sampleRate = u32LE(bytes, 3), sampleRate > 0 else { return nil }
        let nameLength = Int(bytes[8])
        guard bytes.count >= 9 + nameLength else { return nil }
        let name = nameLength > 0 ? String(decoding: bytes[9..<(9 + nameLength)], as: UTF8.self) : ""
        return AudioConfig(streamType: bytes[1], codec: bytes[2], sampleRate: sampleRate,
                           channels: bytes[7], name: name, description: Array(bytes[(9 + nameLength)...]))
    }

    private static func audioPacket(_ bytes: [UInt8]) -> AudioPacket? {
        // [4][streamType][pts u64][一个编码帧]
        guard bytes.count >= 10, let timestamp = u64LE(bytes, 2) else { return nil }
        return AudioPacket(streamType: bytes[1], timestampMicros: timestamp, payload: Array(bytes[10...]))
    }

    // MARK: 本机 → 接收器的 JSON 控制消息

    static func keyframeJSON() -> String { #"{"type":"keyframe"}"# }
    static func pingJSON() -> String { #"{"type":"ping"}"# }
    static func siriJSON() -> String { #"{"type":"siri"}"# }

    /// 播放控制：3 播放/暂停，4 下一首，5 上一首。
    static func mediaJSON(_ code: Int) -> String {
        guard (3...5).contains(code) else { return "" }
        return #"{"type":"media","media":\#(code)}"#
    }

    static func knobJSON(select: Bool = false, home: Bool = false, back: Bool = false,
                         x: Int = 0, y: Int = 0) -> String {
        let parts = [
            select ? #""select":true"# : nil,
            home ? #""home":true"# : nil,
            back ? #""back":true"# : nil,
            x != 0 ? #""x":\#(x)"# : nil,
            y != 0 ? #""y":\#(y)"# : nil,
        ].compactMap { $0 }
        return #"{"type":"knob","knob":{\#(parts.joined(separator: ","))}}"#
    }

    /// 触摸：坐标是 0...1 的相对值（相对整块画面），id 是并发触点槽位；列表发当前全部触点，缺席即抬起。
    static func touchJSON(_ contacts: [TouchContact]) -> String {
        let items = contacts.map { contact -> String in
            let x = String(format: "%.6f", max(0, min(1, contact.x)))
            let y = String(format: "%.6f", max(0, min(1, contact.y)))
            return #"{"id":\#(contact.id),"x":\#(x),"y":\#(y),"down":\#(contact.down ? "true" : "false")}"#
        }
        return #"{"type":"touch","contacts":[\#(items.joined(separator: ","))]}"#
    }

    struct TouchContact: Equatable, Sendable {
        var id: Int
        var x: Double
        var y: Double
        var down: Bool
    }

    /// 接收器 → 本机的文本 JSON 控制消息。字段缺失按缺省处理（上游就是这样）。
    static func parseControl(_ text: String) -> ControlMessage? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }
        switch type {
        case "hello":
            return .hello(phoneName: object["message"] as? String,
                          sessionActive: object["sessionActive"] as? Bool ?? false,
                          width: object["width"] as? Int, height: object["height"] as? Int)
        case "session":
            return .session(phoneName: object["message"] as? String,
                            sessionActive: object["sessionActive"] as? Bool ?? false)
        case "pong":
            return .pong
        case "mic":
            return .mic(active: object["micActive"] as? Bool ?? false)
        default:
            return nil
        }
    }

    enum ControlMessage: Equatable, Sendable {
        case hello(phoneName: String?, sessionActive: Bool, width: Int?, height: Int?)
        case session(phoneName: String?, sessionActive: Bool)
        case pong
        case mic(active: Bool)
    }
}
