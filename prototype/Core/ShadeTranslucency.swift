// 收起后留下的东西（卷帘条或缩略图）透多少：设置里的一个滑块，0 = 不透明，最多 70%。
//
// 原来只有“卷帘条半透明”一个开关：开 = 透 18%（不透明度 0.82）。换成滑块时照搬老用户的选择：
// 没动过滑块之前，数值按老开关算，所以升级后什么都不变。拖过滑块以后，新数值为准，老开关跟着写
// （大于 0 就算开），降级回老版本时也还是它最接近的样子。
// 老开关还在设置里时（滑块接上之前、或只接了一半），拨它照样管用：滑块每次都把两个设置写成一致，
// 两者对不上，就说明之后有人拨过老开关，按老开关算；再拨回来和滑块一致时，又回到滑块的数值。

import Foundation

enum ShadeTranslucency {
    /// 滑块的数值（0…maximum，透明的比例）。
    static let defaultsKey = "ShadeTranslucency"
    /// 老开关（WindowShade.swift 的 shadeTranslucentDefaultsKey）。
    static let legacyDefaultsKey = "ShadeTranslucent"
    /// 老开关打开时透的比例：不透明度 0.82（shadeTranslucentAlpha）。
    static let legacyFraction: Double = 0.18
    static let maximum: Double = 0.7

    /// 现在透多少。没拖过滑块时按老开关算；拖过以后又拨了老开关（两者对不上）时，也按老开关算。
    static func fraction(in defaults: UserDefaults = .standard) -> Double {
        let legacyOn = defaults.bool(forKey: legacyDefaultsKey)
        if let stored = defaults.object(forKey: defaultsKey) as? NSNumber {
            let value = clamp(stored.doubleValue)
            if (value > 0.001) == legacyOn { return value }
        }
        return legacyOn ? legacyFraction : 0
    }

    /// 拖滑块：存新数值，老开关跟着写。返回存下的数值（夹在 0…maximum）。
    @discardableResult
    static func set(_ value: Double, in defaults: UserDefaults = .standard) -> Double {
        let clamped = clamp(value)
        defaults.set(clamped, forKey: defaultsKey)
        defaults.set(clamped > 0.001, forKey: legacyDefaultsKey)
        return clamped
    }

    /// 窗口的不透明度（alphaValue）。
    static func opacity(in defaults: UserDefaults = .standard) -> Double {
        1 - fraction(in: defaults)
    }

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(maximum, max(0, value))
    }
}
