// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
struct FocusPreferences {
    let defaults: UserDefaults
    var minutes: Int {
        get { defaults.integer(forKey: "focus.minutes") == 50 ? 50 : 25 }
        nonmutating set {
            guard newValue == 25 || newValue == 50 else { return }
            defaults.set(newValue, forKey: "focus.minutes")
        }
    }
    // 新键名只是示例；正式合并前先查仓库，不能替换已有键。
    var foldChat: Bool {
        get { defaults.object(forKey: "focus.foldChat") as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: "focus.foldChat") }
    }
}
