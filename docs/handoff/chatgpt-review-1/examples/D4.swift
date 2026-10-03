// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
struct ConductorPreferences {
    let defaults: UserDefaults
    var enabled: Bool {
        get { defaults.bool(forKey: "conductor.enabled") }
        nonmutating set { defaults.set(newValue, forKey: "conductor.enabled") }
    }
    // 保存设置不产生配对或审批权限；由上层显式事务开启监听。
}
