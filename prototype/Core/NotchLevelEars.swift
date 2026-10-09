// 音量、亮度、键盘灯的“两耳”长什么样（《音量与亮度》稿“形状：两耳，不往下鼓”“左耳”“右耳”“多久出、多久收”）。
//
// 数字取稿上 MacBook Air 15 英寸：刘海 185 × 33.5，每只耳朵 76，总宽 = 刘海宽 + 2 × 76 = 337，高同刘海，不往下鼓。
// 左耳一个会变的符号（离外沿 14），右耳一根 54 × 6 的胶囊条（离刘海 8、离外沿 14），不写百分比。
// 纯逻辑，不碰 AppKit：几何、符号（含 AirPods、耳机换设备符号）、读屏那一句、全屏里“看不看得见”的判定都在这里，方便单测。

import Foundation

enum NotchLevelEars {
    // MARK: 形状

    /// 每只耳朵多宽。
    static let earWidth: Double = 76
    /// 左耳符号离外沿。
    static let symbolInset: Double = 14
    /// 右耳条长、条高（条高与 NotchLevelStep.barThickness 同值）。
    static let barLength: Double = 54
    static let barThickness: Double = NotchLevelStep.barThickness
    /// 条离刘海、离外沿。
    static let barNotchGap: Double = 8
    static let barOuterInset: Double = 14
    /// 比这个宽的耳朵不画肩（令牌 §5.1 S3），肩跟着同一根弹簧收到 0（稿上“前 24 点”就是这一段行程）；紧凑两耳最宽 34，两耳 76 一定比它宽。
    static let shoulderlessAbove: Double = 34

    /// 总宽：刘海宽 + 两只耳朵。
    static func totalWidth(notchWidth: Double) -> Double { notchWidth + 2 * earWidth }

    /// 这一耳要不要画肩。耳朵比 34 宽就不画。
    static func drawsShoulders(earWidth: Double = NotchLevelEars.earWidth) -> Bool { earWidth <= shoulderlessAbove }

    // MARK: 条

    /// 轨道的白：平时 0.22，增强对比度 0.45；填充永远是白 1.0（Aaron 2026-10-09 定，替换 C01 的强调色）。
    static func trackAlpha(increasedContrast: Bool) -> Double { increasedContrast ? 0.45 : 0.22 }
    static let fillAlpha: Double = 1.0
    /// 减少动态效果到头时，条的那一头从白 0.6 亮到 1，用这么久。
    static let reducedFlashFrom: Double = 0.6
    static let reducedFlashSeconds: TimeInterval = 0.25

    /// 条的外框（本耳坐标，原点在左下，y 向上）。
    struct Bar: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        /// 填充的宽，0…width（拉长时填充不变，仍按 barLength 算）。
        var fillWidth: Double
        var maxX: Double { x + width }
    }

    /// 右耳那根条。slot 是右耳整块（x 起点、宽、高）；stretch 是到头再按的拉长（nil 就是平时）。
    /// .upper 往外沿拉长，.lower 往刘海那侧拉长；拉着时变细到 5，仍垂直居中。
    static func bar(slotMinX: Double, slotHeight: Double, value: Double, stretch: NotchLevelStep.Stretch?) -> Bar {
        let clamped = NotchLevelStep.clamp(value)
        let thickness = stretch?.thickness ?? barThickness
        var x = slotMinX + barNotchGap
        var width = barLength
        if let stretch {
            switch stretch.edge {
            case .upper: width += stretch.points
            case .lower: x -= stretch.points; width += stretch.points
            }
        }
        return Bar(x: x, y: (slotHeight - thickness) / 2, width: width, height: thickness,
                   fillWidth: barLength * clamped)
    }

    /// 左耳符号被顶着挪了多少（左耳坐标里 x 方向，正数往右）：拉长量的 ¼，顺着条的方向——
    /// 条往外沿，符号也往外沿（左耳的外沿在左，所以是负数）；条往刘海，符号也往刘海。
    static func symbolOffset(stretch: NotchLevelStep.Stretch?) -> Double {
        guard let stretch else { return 0 }
        return stretch.edge == .upper ? -stretch.symbolShift : stretch.symbolShift
    }

    // MARK: 符号

    /// 声音从哪出。不是内建扬声器时左耳换设备符号。
    enum Output: Equatable, Sendable {
        case speaker, airPodsPro, airPods, airPodsMax, headphones

        /// 按设备名和连接方式猜。名字里带 AirPods Pro / Max / AirPods 的各取各的；
        /// 其它蓝牙耳机、有线耳机（耳机口）取 headphones；别的都当扬声器。
        static func classify(name: String?, isHeadphoneTransport: Bool) -> Output {
            let lowered = (name ?? "").lowercased()
            if lowered.contains("airpods pro") { return .airPodsPro }
            if lowered.contains("airpods max") { return .airPodsMax }
            if lowered.contains("airpods") { return .airPods }
            return isHeadphoneTransport ? .headphones : .speaker
        }

        /// 设备符号；扬声器没有（沿用分档符号）。
        var deviceSymbol: String? {
            switch self {
            case .speaker: return nil
            case .airPodsPro: return "airpodspro"
            case .airPods: return "airpods"
            case .airPodsMax: return "airpodsmax"
            case .headphones: return "headphones"
            }
        }
    }

    /// 左耳这一下用哪个符号。音量接了设备就换设备符号；静音一律带斜线的喇叭（一个意思一个符号）；亮度、键盘灯不看设备。
    static func symbolName(kind: NotchLevelKind, value: Double, muted: Bool, output: Output = .speaker) -> String {
        let tier = NotchLevelStep.tier(kind: kind, value: value, muted: muted)
        if kind == .volume, tier != .volumeMuted, let device = output.deviceSymbol { return device }
        return tier.symbolName
    }

    // MARK: 读屏

    /// 读屏念的那一句：“音量 45%”“静音”“亮度 70%”“键盘灯 40%”。
    static func spokenText(kind: NotchLevelKind, value: Double, muted: Bool) -> String {
        let percent = Int((NotchLevelStep.clamp(value) * 100).rounded())
        switch kind {
        case .volume: return muted ? "静音" : "音量 \(percent)%"
        case .brightness: return "亮度 \(percent)%"
        case .keyboardLight: return "键盘灯 \(percent)%"
        }
    }

    /// 最后一下之后多久念一次，不逐格念。
    static let announceDelay: TimeInterval = 0.5
    /// 最后一下之后多久收（`Motion.Hold.level` 取这个值）。
    static let holdSeconds: TimeInterval = 1.2

    // MARK: 全屏里看不看得见

    /// 原生全屏桌面：面板此刻在这张全屏桌面上真的可见才出两耳；任何一项查不到（nil）按“看不见”处理，不出。
    static func fullScreenVisibility(panelVisible: Bool?, onActiveSpace: Bool?, occlusionVisible: Bool?)
        -> NotchLevelSuppression.FullScreen {
        guard panelVisible == true, onActiveSpace == true, occlusionVisible == true else { return .notVisible }
        return .visible
    }

    /// 这一刻要不要画：不在让开状态一定画；让开着（全屏或调度中心）时，只有“不是调度中心，且全屏里面板看得见”才画。
    /// missionControl 查不到（nil）也不画：调度中心里我们不能保证画在它上面。
    static func mayDraw(yielding: Bool, missionControl: Bool?, fullScreen: NotchLevelSuppression.FullScreen) -> Bool {
        guard yielding else { return true }
        guard missionControl == false else { return false }
        return fullScreen == .visible
    }
}
