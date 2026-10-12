import Cocoa
@MainActor enum WS2FocusSettings {
    /// 这一组设置属于“实时活动”那一栏；搬动由收尾包（R09）做，这里只暴露视图 WS2FocusSettingsRows。
    static let sectionTitle = "实时活动"
    static let tuckChatTitle = "专注时把聊天收进刘海"
    static let presetKey = "WS2.focus.preset"
    static let tuckChatKey = "WS2.focus.tuckChat"
    static var preset: FocusTimer.Preset {
        UserDefaults.standard.string(forKey: presetKey) == "50/10" ? .minutes50 : .minutes25
    }
    static var tuckChat: Bool { UserDefaults.standard.object(forKey: tuckChatKey) as? Bool ?? true }
    static func set(preset: FocusTimer.Preset) {
        UserDefaults.standard.set(preset == .minutes50 ? "50/10" : "25/5", forKey: presetKey)
    }
    static func set(tuckChat: Bool) { UserDefaults.standard.set(tuckChat, forKey: tuckChatKey) }
}
@MainActor final class WS2FocusSettingsRows: NSStackView {
    private weak var runtime: WS2AppRuntime?
    private let presets = NSPopUpButton(), tuck = NSButton(checkboxWithTitle: WS2FocusSettings.tuckChatTitle, target: nil, action: nil)
    init(runtime: WS2AppRuntime) {
        self.runtime = runtime; super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 10
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 12
        row.addArrangedSubview(NSTextField(labelWithString: "番茄钟"))
        presets.addItems(withTitles: ["25 分钟 / 5 分钟", "50 分钟 / 10 分钟"])
        presets.selectItem(at: WS2FocusSettings.preset == .minutes50 ? 1 : 0)
        presets.target = self; presets.action = #selector(changePreset); row.addArrangedSubview(presets)
        presets.toolTip = "新的时长从下一轮开始生效。正在进行的一轮保持原时长。"
        addArrangedSubview(row)
        tuck.state = WS2FocusSettings.tuckChat ? .on : .off; tuck.target = self; tuck.action = #selector(changeTuck)
        tuck.toolTip = "只收私人 App 名单里的窗口；名单为空或这项还没开放时不可用，也不会拿“收起全部窗口”顶替。"
        let listed = !PrivateAppList.shared.isEmpty
        tuck.isEnabled = listed && WS2FocusWindowPort.admitted
        addArrangedSubview(tuck)
        if !tuck.isEnabled {
            let note = NSTextField(wrappingLabelWithString: listed ? "现在只计时，还不会收起窗口。" : "名单里还没有 App")
            note.textColor = .secondaryLabelColor; note.font = .systemFont(ofSize:11); addArrangedSubview(note)
        }
    }
    required init?(coder: NSCoder) { nil }
    @objc private func changePreset() { WS2FocusSettings.set(preset: presets.indexOfSelectedItem == 1 ? .minutes50 : .minutes25); runtime?.refreshFocusSettings() }
    @objc private func changeTuck() { WS2FocusSettings.set(tuckChat: tuck.state == .on); runtime?.refreshFocusSettings() }
}
