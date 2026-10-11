import Foundation

// iAP2 控制会话消息（CSM）的纯编解码。线格式：0x4040 | u16 总长 | u16 消息 | 参数体，大端、无校验。
// 参数体：u16 参数长（含自身）| u16 参数 ID | 载荷，可重复、按序。
// 协议格式参考固定上游（见 docs/handoff/ws2-reuse-2026-10-07/carplay.md）；实现为原创 Swift。

enum Iap2Csm {

    static let start: UInt16 = 0x4040
    static let headerBytes = 6
    static let maxFrameBytes = 0xffff
    static let maxBodyBytes = maxFrameBytes - headerBytes
    static let paramHeaderBytes = 4
    static let maxParamBytes = 0xffff

    struct Frame: Equatable {
        var messageId: UInt16
        var parameters: [Parameter]

        init(messageId: UInt16, parameters: [Parameter] = []) {
            self.messageId = messageId
            self.parameters = parameters
        }

        var encoded: [UInt8] {
            var body: [UInt8] = []
            for parameter in parameters { body += parameter.encoded }
            var out: [UInt8] = []
            out += be16(Iap2Csm.start)
            out += be16(UInt16(Iap2Csm.headerBytes + body.count))
            out += be16(messageId)
            out += body
            return out
        }
    }

    struct Parameter: Equatable {
        var id: UInt16
        var payload: [UInt8]

        var encoded: [UInt8] {
            be16(UInt16(Iap2Csm.paramHeaderBytes + payload.count)) + be16(id) + payload
        }
    }

    /// 从字节流里解出所有完整 CSM 帧；残缺的留在缓冲区（返回偏移）。垃圾字节逐字节跳过。
    static func parse(from buffer: [UInt8]) -> (frames: [Frame], consumed: Int) {
        var frames: [Frame] = []
        var index = 0
        while index + headerBytes <= buffer.count {
            if be16At(buffer, index) != start {
                index += 1
                continue
            }
            let length = Int(be16At(buffer, index + 2))
            guard length >= headerBytes, length <= maxFrameBytes else { index += 1; continue }
            guard index + length <= buffer.count else { break }
            let messageId = be16At(buffer, index + 4)
            let body = Array(buffer[(index + headerBytes)..<(index + length)])
            guard let parameters = parseParameters(body) else { index += 1; continue }
            frames.append(Frame(messageId: messageId, parameters: parameters))
            index += length
        }
        return (frames, index)
    }

    static func parseParameters(_ body: [UInt8]) -> [Parameter]? {
        var parameters: [Parameter] = []
        var offset = 0
        while offset < body.count {
            guard offset + paramHeaderBytes <= body.count else { return nil }
            let length = Int(be16At(body, offset))
            guard length >= paramHeaderBytes, offset + length <= body.count else { return nil }
            parameters.append(Parameter(
                id: be16At(body, offset + 2),
                payload: Array(body[(offset + paramHeaderBytes)..<(offset + length)])))
            offset += length
        }
        return parameters
    }

    // MARK: 消息常量（识别与配件认证）

    enum Identify {
        static let start: UInt16 = 0x1d00
        static let information: UInt16 = 0x1d01
        static let accepted: UInt16 = 0x1d02
        static let rejected: UInt16 = 0x1d03
    }

    enum Mfi {
        static let requestCertificate: UInt16 = 0xaa00
        static let certificate: UInt16 = 0xaa01
        static let requestChallenge: UInt16 = 0xaa02
        static let response: UInt16 = 0xaa03
        static let failed: UInt16 = 0xaa04
        static let succeeded: UInt16 = 0xaa05

        static let maximumChallengeBytes = 128
        static let maximumCertificateBytes = 65_525
    }

    // MARK: 识别信息（0x1d01）的参数布局
    // 参数 0-5 是 NUL 结尾串：名字、型号、厂商、序列号、固件、硬件。
    // 6：本端会发的消息 ID 表（u16 拼接）；7：本端会收的消息表；8：u8（无线 0 / 有线 2）；9：u16 常量 20。
    // 10：外设协议组；12/13：语言；17：蓝牙传输组；24：Wi-Fi 组；30：路线引导组。

    static let messagesSentByAccessory: [UInt16] = [
        0xaa01, 0xaa03,            // 配件认证：证书、应答
        0x5000, 0x5002,            // 正在播放更新开关
        0x5200, 0x5203,            // 路线引导更新开关
        0xae00, 0xae02,            // 电源更新开关
        0x4157, 0x4159,            // 通讯更新开关
        0x4154, 0x4156,            // 通话状态更新开关
        0x4301,                    // CarPlay 开始会话
        0x5703,                    // Wi-Fi 配置信息（无线）
    ]

    static let messagesReceivedFromPhone: [UInt16] = [
        0xaa00, 0xaa02, 0xaa04, 0xaa05, // 配件认证全套
        0xea00, 0xea01,            // 外设协议会话开关
        0x5001, 0x5201, 0x5202,    // 正在播放 / 路线引导更新
        0xae01,                    // 电源更新
        0x4158, 0x4155,            // 通讯 / 通话状态更新
        0x4300,                    // CarPlay 可用性
        0x4e0d, 0x4e0e, 0x5702,    // 无线：手机侧 Wi-Fi/链路消息
    ]

    /// 无线（蓝牙引导）识别信息。mac 是六段冒号大写地址；ssid 不为空。
    static func identificationInformation(
        name: String, model: String, manufacturer: String, serialNumber: String,
        firmwareVersion: String, hardwareVersion: String, externalAccessoryProtocol: String,
        bluetoothMac: String, ssid: String, language: String = "zh-Hans"
    ) -> Frame {
        var parameters: [Parameter] = [
            Parameter(id: 0, payload: nul(name)),
            Parameter(id: 1, payload: nul(model)),
            Parameter(id: 2, payload: nul(manufacturer)),
            Parameter(id: 3, payload: nul(serialNumber)),
            Parameter(id: 4, payload: nul(firmwareVersion)),
            Parameter(id: 5, payload: nul(hardwareVersion)),
            Parameter(id: 6, payload: u16List(messagesSentByAccessory)),
            Parameter(id: 7, payload: u16List(messagesReceivedFromPhone)),
            Parameter(id: 8, payload: [0]), // 无线
            Parameter(id: 9, payload: be16(20)),
            Parameter(id: 10, payload: encodeParameters([
                Parameter(id: 0, payload: [1]),
                Parameter(id: 1, payload: nul(externalAccessoryProtocol)),
                Parameter(id: 2, payload: []),
            ])),
            Parameter(id: 12, payload: nul(language)),
            Parameter(id: 13, payload: nul(language)),
        ]
        parameters.append(Parameter(id: 17, payload: encodeParameters([
            Parameter(id: 0, payload: be16(0)),
            Parameter(id: 1, payload: nul("blue")),
            Parameter(id: 2, payload: []),
            Parameter(id: 3, payload: macBytes(bluetoothMac) ?? []),
            Parameter(id: 4, payload: nul("blue")),
            Parameter(id: 5, payload: []),
        ])))
        parameters.append(Parameter(id: 24, payload: encodeParameters([
            Parameter(id: 0, payload: be16(1)),
            Parameter(id: 1, payload: nul(ssid)),
            Parameter(id: 2, payload: []),
            Parameter(id: 3, payload: be16(1)),
            Parameter(id: 4, payload: []),
            Parameter(id: 5, payload: []),
        ])))
        parameters.append(Parameter(id: 30, payload: encodeParameters([
            Parameter(id: 0, payload: be16(42)),
            Parameter(id: 1, payload: nul("RouteGuidance")),
            Parameter(id: 2, payload: be16(64)),
            Parameter(id: 4, payload: be16(64)),
            Parameter(id: 6, payload: be16(8)),
        ])))
        return Frame(messageId: Identify.information, parameters: parameters)
    }

    static func accessoryCertificate(_ certificate: [UInt8]) -> Frame {
        Frame(messageId: Mfi.certificate, parameters: [
            Parameter(id: 0, payload: certificate),
        ])
    }

    static func authenticationResponse(_ signature: [UInt8]) -> Frame {
        Frame(messageId: Mfi.response, parameters: [
            Parameter(id: 0, payload: signature),
        ])
    }

    static func challenge(of frame: Frame) -> [UInt8]? {
        frame.parameters.first { $0.id == 0 }?.payload
    }

    /// 组参数：嵌套的同格式参数表，整体作为外层参数的载荷。
    static func encodeParameters(_ parameters: [Parameter]) -> [UInt8] {
        parameters.flatMap { $0.encoded }
    }

    // MARK: 小工具

    static func nul(_ string: String) -> [UInt8] {
        Array(string.utf8) + [0]
    }

    static func u16List(_ values: [UInt16]) -> [UInt8] {
        values.flatMap { be16($0) }
    }

    static func macBytes(_ mac: String) -> [UInt8]? {
        let parts = mac.split(separator: ":")
        guard parts.count == 6 else { return nil }
        var out: [UInt8] = []
        for part in parts {
            guard let value = UInt8(part, radix: 16) else { return nil }
            out.append(value)
        }
        return out
    }

    static func be16(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8 & 0xff), UInt8(value & 0xff)]
    }

    static func be32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xff), UInt8(value >> 16 & 0xff), UInt8(value >> 8 & 0xff), UInt8(value & 0xff)]
    }

    static func be16At(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }
}
