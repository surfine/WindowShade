import Cocoa

/// 指挥模式的设置项（纯数据）：键、hook 配置预览。页面在 WS2ConductorSettings.swift。

/// 指挥模式的设置只记在这台 Mac 上。开关在“遥控模式”下面（总开关关着时跟着关），这一页只放它的细项。
enum WS2ConductorSettings {
    static let enabledKey = "WindowShade.Conductor.Enabled"
    static func slotKey(_ index: Int) -> String { "WindowShade.Conductor.ModelSlot.\(index)" }
    /// 编程会话：Claude Code 的 hook 报到本机 socket（WS2HookServer）。默认关，不依赖遥控模式。
    static let codingSessionsKey = "WindowShade.Conductor.CodingSessions"
    static var hookHelperPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/WindowShadeHook").path
    }
    /// 只生成给用户自己粘贴的配置，不写 ~/.claude（WS2HookConfigPreview.writesUserHome 永远是 false）。
    static func hookConfiguration(helper: String = hookHelperPath) -> String? {
        guard WS2HookConfigPreview.writesUserHome == false,
              let preview = try? WS2HookConfiguration.preview(original: Data("{}".utf8), executable: helper, connected: true)
        else { return nil }
        return String(data: preview.replacement, encoding: .utf8)
    }

    static func flag(_ key: String, in store: UserDefaults) -> Bool {
        store.object(forKey: key) as? Bool == true
    }
    static func setFlag(_ on: Bool, _ key: String, in store: UserDefaults) {
        if on { store.set(true, forKey: key) } else { store.removeObject(forKey: key) }
    }
    static func text(_ key: String, in store: UserDefaults) -> String {
        store.string(forKey: key) ?? ""
    }
    static func setText(_ value: String, _ key: String, in store: UserDefaults) {
        let trimmed = String(value.prefix(512))
        if trimmed.isEmpty { store.removeObject(forKey: key) } else { store.set(trimmed, forKey: key) }
    }
}
