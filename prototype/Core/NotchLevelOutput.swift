// 默认输出设备是什么：把 Core Audio 读到的传输方式、型号名、耳机口，翻成两耳左边该换哪个符号
// （《音量与亮度》稿“左耳”：AirPods Pro / AirPods / AirPods Max / 耳机，别的沿用扬声器分档）。
// 纯逻辑，不碰 Core Audio：读设备在 NotchLevelControl，这里只管分类，方便单测。

import Foundation

/// 设备的传输方式（kAudioDevicePropertyTransportType 的四字符码）。
enum NotchLevelTransport: Equatable, Sendable {
    case builtIn, bluetooth, usb, hdmi, displayPort, airPlay, virtual, other
    /// 读不到。
    case unknown

    static func fourCC(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    init(code value: UInt32?) {
        guard let value else { self = .unknown; return }
        switch value {
        case Self.fourCC("bltn"): self = .builtIn
        case Self.fourCC("blue"), Self.fourCC("blea"): self = .bluetooth
        case Self.fourCC("usb "): self = .usb
        case Self.fourCC("hdmi"): self = .hdmi
        case Self.fourCC("dprt"): self = .displayPort
        case Self.fourCC("airp"): self = .airPlay
        case Self.fourCC("virt"), Self.fourCC("grup"): self = .virtual
        default: self = .other
        }
    }
}

extension NotchLevelEars.Output {
    /// 内建输出的“耳机”数据源（kAudioDevicePropertyDataSource 的四字符码 'hdpn'）：耳机口插着东西。
    static let headphoneJackSource: UInt32 = NotchLevelTransport.fourCC("hdpn")

    private static let headphoneWords = ["headphone", "headset", "earphone", "earbud", "buds", "beats", "耳机", "耳麦", "耳塞"]
    private static let speakerWords = ["speaker", "soundbar", "homepod", "display", "音箱", "音响", "扬声器", "显示器"]

    /// 按型号名、传输方式、数据源分：AirPods 系列各取各的；耳机口插着、名字像耳机的是耳机；
    /// 名字像音箱的一律是扬声器；没有名字线索时，蓝牙当耳机，其它（内建、USB、HDMI、隔空播放、读不到）当扬声器。
    static func classify(name: String?, transport: NotchLevelTransport, dataSource: UInt32? = nil) -> Self {
        let lowered = (name ?? "").lowercased()
        let airPods = classify(name: name, isHeadphoneTransport: false)
        if airPods != .speaker { return airPods }
        if transport == .builtIn, dataSource == headphoneJackSource { return .headphones }
        if headphoneWords.contains(where: lowered.contains) { return .headphones }
        if speakerWords.contains(where: lowered.contains) { return .speaker }
        return transport == .bluetooth ? .headphones : .speaker
    }
}
