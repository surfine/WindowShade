// 卷轴按 App 记住列宽（稿：docs/design-drafts/卷轴.html“新窗口多宽”，工作包 SS-06）。
//
// 你给某个 App 在卷轴里改过一次宽度，下次它开在卷轴里就用你改的那档，不用写配置。
// 只存 App 的标识和一个比例（屏幕宽度的几分之几，只取 ⅓ ½ ⅔ 整屏这几档），放在本机设置里；
// 不记窗口标题、不联网。默认开（稿“权限与隐私”），设置里一键忘掉（forgetAll）。
// 读写点登记在 tools/privacy/registry.json 的 settings 一行。纯逻辑 + 一层本机设置读写，可单测。

import CoreGraphics
import Foundation

struct StripWidthMemory: Equatable {
    /// 本机设置里的键：App 标识 → 比例。
    static let storageKey = "ScrollStrip.widthMemory"
    /// 开关（默认开）：关掉后不再记、也不再用记下的宽度（已记下的留着，等你按“忘掉”）。
    static let enabledKey = "ScrollStrip.rememberWidths"
    /// 最多记几个 App：够用，又不让这份设置无限长。满了先丢最早记下的那个。
    static let capacity = 64

    /// 记下的比例，按记下的先后排（最后一个最新）。
    private(set) var entries: [(bundleID: String, fraction: CGFloat)] = []

    static func == (a: StripWidthMemory, b: StripWidthMemory) -> Bool {
        a.entries.map(\.bundleID) == b.entries.map(\.bundleID) && a.entries.map(\.fraction) == b.entries.map(\.fraction)
    }

    init() {}

    /// 比例落到最近的那一档（⅓ ½ ⅔ 整屏）；差太远（不是我们给的宽度，比如 App 自己的最小宽度挤出来的）返回 nil。
    static func preset(for fraction: CGFloat) -> CGFloat? {
        guard fraction.isFinite, fraction > 0 else { return nil }
        let nearest = ScrollStrip.presets.min { abs($0 - fraction) < abs($1 - fraction) }
        guard let nearest, abs(nearest - fraction) <= 0.04 else { return nil }
        return nearest
    }

    func fraction(for bundleID: String?) -> CGFloat? {
        guard let bundleID else { return nil }
        return entries.last { $0.bundleID == bundleID }?.fraction
    }

    /// 这个 App 下次开在卷轴里用多宽（点）；没记过返回 nil，照 App 要的地方给。
    func width(for bundleID: String?, in area: CGRect) -> CGFloat? {
        fraction(for: bundleID).map { (area.width * $0).rounded() }
    }

    /// 你给这个 App 改了宽度：记下那一档。没有标识、宽度不是那几档之一时不记。返回是否记下了（或改了）。
    @discardableResult
    mutating func remember(bundleID: String?, width: CGFloat, screenWidth: CGFloat) -> Bool {
        guard let bundleID, !bundleID.isEmpty, screenWidth > 0, let fraction = Self.preset(for: width / screenWidth) else { return false }
        entries.removeAll { $0.bundleID == bundleID }
        entries.append((bundleID, fraction))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        return true
    }

    mutating func forget(bundleID: String) { entries.removeAll { $0.bundleID == bundleID } }
    mutating func forgetAll() { entries.removeAll() }

    // MARK: 本机设置

    /// 存成 [[标识, 比例], …]：保留先后，读回来坏掉的项跳过。
    var stored: [[Any]] { entries.map { [$0.bundleID, Double($0.fraction)] } }

    init(stored: Any?) {
        guard let list = stored as? [[Any]] else { return }
        for item in list {
            guard item.count == 2, let id = item[0] as? String, let value = item[1] as? Double else { continue }
            remember(bundleID: id, width: CGFloat(value), screenWidth: 1)
        }
    }

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    static func setEnabled(_ on: Bool, _ defaults: UserDefaults = .standard) {
        if on { defaults.removeObject(forKey: enabledKey) } else { defaults.set(false, forKey: enabledKey) }
    }

    static func load(_ defaults: UserDefaults = .standard) -> StripWidthMemory {
        StripWidthMemory(stored: defaults.array(forKey: storageKey))
    }

    func save(_ defaults: UserDefaults = .standard) {
        if entries.isEmpty { defaults.removeObject(forKey: Self.storageKey) } else { defaults.set(stored, forKey: Self.storageKey) }
    }

    /// 设置里“忘掉卷轴记住的宽度”：一键清空。
    static func forgetAll(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}
