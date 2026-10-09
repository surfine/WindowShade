// 音量、亮度、键盘灯：按一下走多远、落在哪、到头了怎么拉、符号用哪一档（照《音量与亮度》稿）。
//
// - 步长照系统：一下 1/16，按着 ⌥⇧ 是 1/64；总是落在格子上（细调之后再普通按，先落到 1/16 的格上）。
// - 夹在 0–1；已经到头再按，数值不变，数“到头了第几下”，条用橡皮筋拉长（c = 0.55，最多 8 点）。
// - 符号分档：音量 0 / ≤⅓ / ≤⅔ / 以上 / 静音斜线；亮度 <50% 小太阳；键盘灯 0 / <50% / 以上。
//
// 纯逻辑，不碰 AppKit；橡皮筋用 FluidMotion.rubberBand（Core/FlickMotion.swift）。

import Foundation

enum NotchLevelStep {
    /// 一下按键的步长：1/16（条上 3.4 点）。
    static let coarse = 1.0 / 16.0
    /// 按着 ⌥⇧：1/64（条上 0.84 点）。
    static let fine = 1.0 / 64.0

    enum Direction: Equatable, Sendable { case up, down }

    /// 到了哪一头：.upper 是 100%（再按 +），.lower 是 0%（再按 −）。
    enum Edge: Equatable, Sendable { case upper, lower }

    struct Result: Equatable, Sendable {
        /// 按完之后的数值，0–1，落在格子上。
        var value: Double
        /// 已经在头上还往外按：数值没变，条该拉长。
        var edge: Edge?
        /// 静音时按音量 +/−：先取消静音再走一格（照系统；− 的方向真机核对）。
        var unmutes: Bool
        var changed: Bool
    }

    static func size(modifiers: NotchLevelModifiers) -> Double {
        modifiers == .optionShift ? fine : coarse
    }

    static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    /// 落格走一步。value 是现在的数值（读到什么算什么，可以不在格上）。
    static func step(from value: Double, direction: Direction, modifiers: NotchLevelModifiers = .none,
                     muted: Bool = false) -> Result {
        let size = size(modifiers: modifiers)
        let current = clamp(value)
        // 现在在第几格（可以是小数）；离整数格 1e-6 以内当作就在格上，免得浮点误差多走或少走一格。
        var cells = current / size
        let nearest = cells.rounded()
        let onGrid = abs(cells - nearest) < 1e-6
        if onGrid { cells = nearest }
        let target: Double
        switch direction {
        case .up: target = onGrid ? cells + 1 : cells.rounded(.up)
        case .down: target = onGrid ? cells - 1 : cells.rounded(.down)
        }
        let next = clamp(target * size)
        let moved = abs(next - current) > 1e-9
        var edge: Edge?
        if !moved {
            if direction == .up, current >= 1 - 1e-9 { edge = .upper }
            if direction == .down, current <= 1e-9 { edge = .lower }
        }
        return Result(value: moved ? next : current, edge: edge, unmutes: muted, changed: moved)
    }

    // MARK: 到头了再按

    /// 到头了第几下。连续往同一头顶才累加；按到别处、换了头或隔太久（超过按键窗口）就从头数。
    struct EdgeCounter: Equatable, Sendable {
        private(set) var count = 0
        private var edge: Edge?
        private var last: TimeInterval = -.infinity

        init() {}

        /// 这一下按完的结果；返回到头次数（没到头就是 0）。
        mutating func record(_ result: Result, at time: TimeInterval) -> Int {
            guard let hit = result.edge else { count = 0; edge = nil; return 0 }
            if edge == hit, time >= last, time - last <= NotchLevelGate.window {
                count += 1
            } else {
                count = 1
            }
            edge = hit
            last = time
            return count
        }

        mutating func reset() { count = 0; edge = nil; last = -.infinity }
    }

    /// 条被拉长的样子。方向跟着哪一头：.upper 往外沿，.lower 往刘海那侧。
    struct Stretch: Equatable, Sendable {
        var edge: Edge
        /// 条多拉出的点数，0…8，永远到不了 8。
        var points: Double
        /// 拉着时条变细到 5（平时 6）。
        var thickness: Double
        /// 符号顺着挪的点数，拉长量的 ¼。
        var symbolShift: Double
    }

    static let maxStretch = 8.0
    static let barThickness = 6.0
    static let stretchedThickness = 5.0
    /// 每顶一下相当于手指往外拉了多少点，再过橡皮筋。一下约 3 点，第二下约 4.4，一直顶着慢慢逼近 8。
    static let pullPerPush = 8.0

    /// 顶到头第 n 下（n ≥ 1）的拉长；n ≤ 0 返回 nil（没在拉）。
    static func stretch(edge: Edge, pushes: Int) -> Stretch? {
        guard pushes > 0 else { return nil }
        let points = FluidMotion.rubberBand(Double(pushes) * pullPerPush, limit: maxStretch)
        return Stretch(edge: edge, points: points, thickness: stretchedThickness, symbolShift: points / 4)
    }

    // MARK: 符号分档

    /// 左耳的符号档。设备符号（AirPods、耳机）另算，不在这里：静音仍是带斜线的喇叭。
    enum Tier: Equatable, Sendable {
        case volumeMuted, volumeZero, volumeLow, volumeMid, volumeHigh
        case brightnessLow, brightnessHigh
        case keyboardOff, keyboardLow, keyboardHigh

        /// SF Symbols 名。键盘灯“熄灭”没有单独的符号，用 light.min 并按 isDimmed 画暗（LV3 在真机核对）。
        var symbolName: String {
            switch self {
            case .volumeMuted: return "speaker.slash.fill"
            case .volumeZero: return "speaker.fill"
            case .volumeLow: return "speaker.wave.1.fill"
            case .volumeMid: return "speaker.wave.2.fill"
            case .volumeHigh: return "speaker.wave.3.fill"
            case .brightnessLow: return "sun.min.fill"
            case .brightnessHigh: return "sun.max.fill"
            case .keyboardOff, .keyboardLow: return "light.min"
            case .keyboardHigh: return "light.max"
            }
        }

        var isDimmed: Bool { self == .keyboardOff }
    }

    /// 0 → 无声波的喇叭；≤ ⅓ → 一道；≤ ⅔ → 两道；以上 → 三道；静音一律斜线（哪怕数值不是 0）。
    static func volumeTier(_ value: Double, muted: Bool) -> Tier {
        if muted { return .volumeMuted }
        let v = clamp(value)
        if v <= 1e-9 { return .volumeZero }
        if v <= 1.0 / 3.0 + 1e-9 { return .volumeLow }
        if v <= 2.0 / 3.0 + 1e-9 { return .volumeMid }
        return .volumeHigh
    }

    /// 不到 50% 小太阳，否则大太阳。
    static func brightnessTier(_ value: Double) -> Tier {
        clamp(value) < 0.5 ? .brightnessLow : .brightnessHigh
    }

    /// 0 熄灭，不到 50% 一档，否则两档。
    static func keyboardLightTier(_ value: Double) -> Tier {
        let v = clamp(value)
        if v <= 1e-9 { return .keyboardOff }
        return v < 0.5 ? .keyboardLow : .keyboardHigh
    }

    static func tier(kind: NotchLevelKind, value: Double, muted: Bool = false) -> Tier {
        switch kind {
        case .volume: return volumeTier(value, muted: muted)
        case .brightness: return brightnessTier(value)
        case .keyboardLight: return keyboardLightTier(value)
        }
    }
}
