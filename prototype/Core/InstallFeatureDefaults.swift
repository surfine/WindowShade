// 首次升级到带功能开关的版本时，把 8 个模块的总闸写一遍。
//
// 新装：按 FeatureCatalog 的内部默认（成熟开、未成熟关）。
// 升级：不改变现有行为——模块总闸 = 该模块现在是否至少有一项开着；
// 没有子项的模块（启动台、画中画）保留开，免得升级后菜单项突然消失。
// 只写一次，标记 FeatureDefaults.Seeded；之后用户怎么改都照用户的。

import Foundation

enum InstallFeatureDefaults {
    static let seededKey = "FeatureDefaults.Seeded"
    /// 新装第一次引导结束后，是否已经给过“挑功能”的机会。
    static let pickerShownKey = "FeaturePickerShown"

    static func seedIfNeeded(freshInstall: Bool, in defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: seededKey) else { return }
        let fresh = freshInstall
        for definition in FeatureCatalog.all {
            if defaults.object(forKey: definition.masterKey) != nil { continue }
            let enabled: Bool
            if fresh {
                enabled = definition.defaultOnForFreshInstall
            } else if definition.subfeatures.isEmpty {
                enabled = true
            } else {
                // 这个构建不带的子项（Intel 上的刷脸、合盖效果）不参与：偏好里存的值不读。
                enabled = definition.availableSubfeatures().contains { subfeature in
                    if let value = defaults.object(forKey: subfeature.key) as? Bool { return value }
                    return subfeature.defaultWhenUnset
                }
            }
            defaults.set(enabled, forKey: definition.masterKey)
        }
        defaults.set(true, forKey: seededKey)
    }
}
