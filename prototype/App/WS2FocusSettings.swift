import Cocoa
@MainActor enum WS2FocusSettings {
    /// 这一组设置属于"实时活动"那一栏；搬动由收尾包（R09）做，这里只暴露视图 WS2FocusSettingsRows。
    static let sectionTitle = "实时活动"
    static let tuckChatTitle = "专注时收起聊天窗口"
    static let presetKey = "WS2.focus.preset"
    static let tuckChatKey = FocusTimer.tuckChatKey
    static var preset: FocusTimer.Preset {
        UserDefaults.standard.string(forKey: presetKey) == "50/10" ? .minutes50 : .minutes25
    }
    static var tuckChat: Bool { FocusTimer.tuckChatPreference(object: UserDefaults.standard.object(forKey:)) }
    static func set(preset: FocusTimer.Preset) {
        UserDefaults.standard.set(preset == .minutes50 ? "50/10" : "25/5", forKey: presetKey)
    }
    static func set(tuckChat: Bool) { UserDefaults.standard.set(tuckChat, forKey: tuckChatKey) }
}
@MainActor final class WS2FocusSettingsRows: NSStackView {
    private weak var runtime: WS2AppRuntime?
    private let presets = NSPopUpButton()
    private let tuck = NSButton(checkboxWithTitle: WSL10n.text("settings.shade.focus.tuck", zh: WS2FocusSettings.tuckChatTitle),
                                target: nil, action: nil)
    /// 提示音（拍板 2026-10-29 第 1 条）：等你、完成、番茄钟、计时器到点、指挥拍子共用的唯一一行。
    private let chime = NSButton(checkboxWithTitle: WSL10n.text("settings.shade.alertSound.name", zh: "提示音"),
                                 target: nil, action: nil)
    init(runtime: WS2AppRuntime) {
        self.runtime = runtime; super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 10
        edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 10, right: 0)  // 和其它行一样的上下留白，不贴分隔线
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 12
        row.addArrangedSubview(NSTextField(labelWithString: WSL10n.text("settings.shade.focus.name", zh: "番茄钟")))
        presets.addItems(withTitles: [WSL10n.text("settings.shade.focus.preset25", zh: "25 分钟 / 5 分钟"),
                                      WSL10n.text("settings.shade.focus.preset50", zh: "50 分钟 / 10 分钟")])
        presets.selectItem(at: WS2FocusSettings.preset == .minutes50 ? 1 : 0)
        presets.target = self; presets.action = #selector(changePreset); row.addArrangedSubview(presets)
        // 行被撑宽时多出来的宽度不给下拉（否则它会被拉成整行宽，渲染时好时坏）。
        presets.setContentHuggingPriority(.required, for: .horizontal)
        presets.toolTip = WSL10n.text("settings.shade.focus.presetTooltip", zh: "新的时长从下一轮开始生效。正在进行的一轮保持原时长。")
        addArrangedSubview(row)
        chime.state = AlertSoundPreference.isEnabled(in: .standard) ? .on : .off; chime.target = self; chime.action = #selector(changeChime)
        chime.toolTip = WSL10n.text("settings.shade.alertSound.sub", zh: "等你、完成、番茄钟休息、计时器到点和指挥拍子都响一声")
        chime.setAccessibilityHelp(chime.toolTip)
        // 设置搜索找得到「提示音」：指挥页那一行拿掉后，这是它唯一的入口。
        SettingsSearchRegistry.register(chime, name: WSL10n.setting("settings.shade.alertSound.name", zh: "提示音"),
                                        subtitle: WSL10n.setting("settings.shade.alertSound.sub", zh: "等你、完成、番茄钟休息、计时器到点和指挥拍子都响一声"))
        addArrangedSubview(chime)
        // 专注时收私人 App 是 WindowShade 2 的一部分：预览旗标打开才摆出来。
        guard WS2Preview.isOn else { return }
        tuck.state = WS2FocusSettings.tuckChat ? .on : .off; tuck.target = self; tuck.action = #selector(changeTuck)
        tuck.toolTip = WSL10n.text("settings.shade.focus.tuckTooltip", zh: "只收私人 App 名单里的窗口；名单为空时不可用，也不会拿“收起全部窗口”顶替。")
        let listed = !PrivateAppList.shared.isEmpty
        tuck.isEnabled = listed
        addArrangedSubview(tuck)
        if !tuck.isEnabled {
            let note = NSTextField(wrappingLabelWithString: WSL10n.text("settings.shade.focus.noteNoApps", zh: "名单里还没有 App"))
            note.textColor = .secondaryLabelColor; note.font = .systemFont(ofSize:11); addArrangedSubview(note)
        }
    }
    required init?(coder: NSCoder) { nil }
    @objc private func changePreset() { WS2FocusSettings.set(preset: presets.indexOfSelectedItem == 1 ? .minutes50 : .minutes25); runtime?.refreshFocusSettings() }
    @objc private func changeChime() { AlertSoundPreference.set(chime.state == .on, in: .standard) }
    @objc private func changeTuck() { WS2FocusSettings.set(tuckChat: tuck.state == .on); runtime?.refreshFocusSettings() }
}
