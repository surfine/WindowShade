// 接收器线协议与 Annex B 转换（纯字节，不碰网络、不解真码流）。
import Foundation
import CoreMedia

@main struct WS2CarPlayReceiverWireTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        // 二进制：VIDEO_CONFIG
        do {
            var bytes: [UInt8] = [1, 7, 1] // videoConfig, stream 7, h264
            func le32(_ value: Int) -> [UInt8] {
                [UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)]
            }
            bytes += le32(1280) + le32(720) + [0x01, 0x64, 0x00, 0x1f]
            guard case .videoConfig(let config)? = WS2CarPlayReceiverWire.parseMedia(Data(bytes)) else {
                expect(false, "video config parses"); return
            }
            expect(config.streamType == 7 && config.codec == .h264 && config.width == 1280 && config.height == 720,
                   "video config fields decode little-endian")
            expect(config.codecRecord == [0x01, 0x64, 0x00, 0x1f], "codec record passes through untouched")
            expect(WS2CarPlayReceiverWire.parseMedia(Data([1, 7, 1])) == nil, "truncated config is dropped")
            var hevc = bytes; hevc[2] = 2
            if case .videoConfig(let hevcConfig)? = WS2CarPlayReceiverWire.parseMedia(Data(hevc)) {
                expect(hevcConfig.codec == .h265, "hevc codec id maps to h265")
            } else { expect(false, "hevc config parses") }
            var bad = bytes; bad[2] = 9
            expect(WS2CarPlayReceiverWire.parseMedia(Data(bad)) == nil, "unknown codec id drops the config")
        }

        // 二进制：VIDEO_FRAME（pts 恒为 0，也要能读）
        do {
            var bytes: [UInt8] = [2, 1, 1] // videoFrame, stream 1, keyframe
            bytes += [0, 0, 0, 0, 0, 0, 0, 0]
            bytes += [0, 0, 0, 1, 0x65, 0x88, 0x84, 0x21, 0, 0, 0, 1, 0x41, 0x9a]
            guard case .videoFrame(let frame)? = WS2CarPlayReceiverWire.parseMedia(Data(bytes)) else {
                expect(false, "video frame parses"); return
            }
            expect(frame.isKeyframe && frame.annexB.count == 14, "frame keeps keyframe flag and payload")
            var delta = bytes; delta[2] = 0
            if case .videoFrame(let nonKey)? = WS2CarPlayReceiverWire.parseMedia(Data(delta)) {
                expect(!nonKey.isKeyframe, "delta frames are not keyframes")
            } else { expect(false, "delta frame parses") }
            expect(WS2CarPlayReceiverWire.parseMedia(Data([2, 1, 1, 0, 0])) == nil, "truncated pts drops the frame")
        }

        // 二进制：SCREEN_ACTIVE / AUDIO_STOPPED / 未知
        do {
            if case .screenActive(let stream, let active)? = WS2CarPlayReceiverWire.parseMedia(Data([5, 3, 1])) {
                expect(stream == 3 && active, "screen active parses")
            } else { expect(false, "screen active parses") }
            if case .audioStopped(let stream)? = WS2CarPlayReceiverWire.parseMedia(Data([6, 4])) {
                expect(stream == 4, "audio stopped parses")
            } else { expect(false, "audio stopped parses") }
            expect(WS2CarPlayReceiverWire.parseMedia(Data([9, 1])) == nil, "unknown type is ignored")
            expect(WS2CarPlayReceiverWire.parseMedia(Data([5, 1])) == nil, "truncated screen active is dropped")
        }

        // 二进制：AUDIO_CONFIG / AUDIO_PACKET
        do {
            var bytes: [UInt8] = [3, 2, 1] // audioConfig, stream 2, aac
            func le32(_ value: Int) -> [UInt8] {
                [UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)]
            }
            bytes += le32(44_100) + [2, 5] + Array("Music".utf8) + [0x12, 0x10]
            guard case .audioConfig(let audio)? = WS2CarPlayReceiverWire.parseMedia(Data(bytes)) else {
                expect(false, "audio config parses"); return
            }
            expect(audio.sampleRate == 44_100 && audio.channels == 2 && audio.name == "Music",
                   "audio config decodes rate, channels, name")
            expect(audio.description == [0x12, 0x10], "audio specific config passes through")
            var packet: [UInt8] = [4, 2]
            packet += [0x31, 0, 0, 0, 0, 0, 0, 0] // pts
            packet += [0xaa, 0xbb]
            if case .audioPacket(let p)? = WS2CarPlayReceiverWire.parseMedia(Data(packet)) {
                expect(p.timestampMicros == 0x31 && p.payload == [0xaa, 0xbb], "audio packet decodes pts and payload")
            } else { expect(false, "audio packet parses") }
        }

        // 控制 JSON：发出去的字符串字段齐全
        do {
            expect(WS2CarPlayReceiverWire.keyframeJSON() == #"{"type":"keyframe"}"#, "keyframe request is exact")
            let touch = WS2CarPlayReceiverWire.touchJSON([
                .init(id: 0, x: 0.5, y: 0.25, down: true),
                .init(id: 1, x: 1.5, y: -0.1, down: false),
            ])
            expect(touch.contains(#""type":"touch""#) && touch.contains(#""x":0.500000"#) && touch.contains(#""down":true"#),
                   "touch encodes clamped normalized contacts")
            expect(touch.contains(#""x":1.000000"#) && touch.contains(#""y":0.000000"#), "touch coordinates clamp to 0...1")
            expect(WS2CarPlayReceiverWire.knobJSON(back: true) == #"{"type":"knob","knob":{"back":true}}"#,
                   "knob encodes only set fields")
            expect(WS2CarPlayReceiverWire.mediaJSON(3) == #"{"type":"media","media":3}"#, "media play/pause encodes 3")
            expect(WS2CarPlayReceiverWire.mediaJSON(7).isEmpty, "unknown media codes are refused")
            let empty = WS2CarPlayReceiverWire.touchJSON([])
            expect(empty == #"{"type":"touch","contacts":[]}"#, "empty contact list lifts every touch")
        }

        // 控制 JSON：收进来的消息按缺省补齐
        do {
            if case .hello(let name, let active, let width, _)? = WS2CarPlayReceiverWire.parseControl(
                #"{"type":"hello","deviceName":"p","sessionActive":true,"width":1920,"message":"iPhone"}"#) {
                expect(name == "iPhone" && active && width == 1920, "hello decodes name, session, size")
            } else { expect(false, "hello parses") }
            if case .session(let name, let active)? = WS2CarPlayReceiverWire.parseControl(
                #"{"type":"session","sessionActive":false}"#) {
                expect(name == nil && !active, "session end without a name still parses")
            } else { expect(false, "session message parses") }
            if case .pong = WS2CarPlayReceiverWire.parseControl(#"{"type":"pong"}"#) {} else {
                expect(false, "pong parses")
            }
            expect(WS2CarPlayReceiverWire.parseControl(#"{"type":"future"}"#) == nil, "unknown control types are ignored")
            expect(WS2CarPlayReceiverWire.parseControl("not json") == nil, "garbage text is ignored")
        }

        // Annex B → AVCC：起始码改长度前缀，3/4 字节都认
        do {
            let annexB: [UInt8] = [0, 0, 0, 1, 0x67, 0x64, 0x00, 0x1f,
                                   0, 0, 1, 0x68, 0xeb, 0xec, 0xb2,
                                   0, 0, 0, 1, 0x65, 0x88]
            guard let buffer = WS2CarPlayVideoDecoder.avccBlockBuffer(fromAnnexB: annexB) else {
                expect(false, "annex b converts")
                if failures > 0 { print("\(failures) FAILED"); exit(1) }
                return
            }
            var out = [UInt8](repeating: 0, count: CMBlockBufferGetDataLength(buffer))
            expect(CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: out.count, destination: &out) == kCMBlockBufferNoErr,
                   "converted buffer copies out")
            expect(out == [0, 0, 0, 4, 0x67, 0x64, 0x00, 0x1f,
                           0, 0, 0, 4, 0x68, 0xeb, 0xec, 0xb2,
                           0, 0, 0, 2, 0x65, 0x88],
                   "each nal gets a big-endian length prefix")
            expect(WS2CarPlayVideoDecoder.avccBlockBuffer(fromAnnexB: [0x65, 0x88]) == nil,
                   "payload without start codes is refused")
            expect(WS2CarPlayVideoDecoder.avccBlockBuffer(fromAnnexB: []) == nil, "empty payload is refused")
        }

        if failures > 0 { print("\(failures) FAILED"); exit(1) }
        print("PASS CarPlay receiver wire")
    }
}
