import Cocoa
/// 插入既有卷帘设置页。新硬件能力未取得准入证明时，不能让开关伪装成可用。
@MainActor final class WS2SupplementPane: NSStackView {
    private weak var owner: AppDelegate?
    init(owner: AppDelegate) {
        self.owner = owner; super.init(frame:.zero)
        orientation = .vertical; alignment = .leading; spacing = 12
        let heading = NSTextField(labelWithString: WSL10n.text("settings.shade.supplement.heading", zh: "专注与输入"))
        heading.font = .systemFont(ofSize:13,weight:.semibold); addArrangedSubview(heading)
        let focus = NSButton(title: WSL10n.text("settings.shade.supplement.focus", zh: "开始番茄钟"),
                             target: owner, action: #selector(AppDelegate.ws2OpenFocus))
        focus.bezelStyle = .rounded; focus.isEnabled = NotchController.isEnabled && NotchActivityController.isEnabled
        focus.toolTip = WSL10n.text("settings.shade.supplement.focusTip", zh: "打开番茄钟。快捷键可在快捷键设置中录制。")
        addArrangedSubview(focus)
        let coding = NSButton(title: WSL10n.text("settings.shade.supplement.coding", zh: "编程会话…"),
                              target: owner, action: #selector(AppDelegate.ws2OpenOwned))
        coding.bezelStyle = .rounded; coding.isEnabled = NotchController.isEnabled
        coding.toolTip = WSL10n.text("settings.shade.supplement.codingTip", zh: "本地选择项目和 Codex，登录后进行只读查询。打开页面不会启动程序。")
        addArrangedSubview(coding)
        let silent = NSButton(title: WSL10n.text("settings.shade.supplement.silent", zh: "静音操作…"),
                              target: owner, action: #selector(AppDelegate.ws2OpenSilent))
        silent.bezelStyle = .rounded
        silent.isEnabled = NotchController.isEnabled
        silent.toolTip = WSL10n.text("settings.shade.supplement.silentTip", zh: "在刘海里看清再确认。采用草稿不会发送。")
        addArrangedSubview(silent)
        let conductor = NSButton(title: WSL10n.text("settings.shade.supplement.conductor", zh: "指挥…"),
                                 target: owner, action: #selector(AppDelegate.ws2OpenConductor))
        conductor.bezelStyle = .rounded
        conductor.isEnabled = NotchController.isEnabled
        conductor.toolTip = WSL10n.text("settings.shade.supplement.conductorTip", zh: "看当前会话、模型和草稿。不会发送，也不会连接遥控器。")
        addArrangedSubview(conductor)
        for (title, reason) in [
            (WSL10n.text("settings.shade.supplement.gateConductor", zh: "指挥模式"),
             WSL10n.text("settings.shade.supplement.gateConductorWhy", zh: "需要已核准的输入设备和助手连接")),
            (WSL10n.text("settings.shade.supplement.gateScroll", zh: "平滑滚动"),
             WSL10n.text("settings.shade.supplement.gateScrollWhy", zh: "需要确认每条事件的设备来源")),
            (WSL10n.text("settings.shade.supplement.gateRemote", zh: "Siri 遥控器"),
             WSL10n.text("settings.shade.supplement.gateRemoteWhy", zh: "需要通过当前设备的按钮与触点探针")),
            (WSL10n.text("settings.shade.supplement.gatePresence", zh: "在场检测"),
             WSL10n.text("settings.shade.supplement.gatePresenceWhy", zh: "需要已绑定身份的蓝牙读回来源")),
        ] {
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 10
            let toggle = NSButton(checkboxWithTitle:title,target:nil,action:nil)
            toggle.state = .off; toggle.isEnabled = false; toggle.toolTip = reason; toggle.setAccessibilityHelp(reason)
            let note = NSTextField(wrappingLabelWithString:reason); note.font = .systemFont(ofSize:11); note.textColor = .secondaryLabelColor
            row.addArrangedSubview(toggle); row.addArrangedSubview(note); addArrangedSubview(row)
        }
        let activity = NSButton(title: WSL10n.text("settings.shade.supplement.activities", zh: "打开实时活动"),
                                target: owner, action: #selector(AppDelegate.openActivitiesAction))
        activity.bezelStyle = .rounded; addArrangedSubview(activity)
        let overlay = NSButton(checkboxWithTitle: WSL10n.text("settings.shade.supplement.lockOverlay", zh: "锁屏开合效果"),
                               target: owner, action: #selector(AppDelegate.toggleLockOverlayAction))
        overlay.state = owner.duoController.lockOverlay.enabled ? .on : .off; addArrangedSubview(overlay)
        let welcome = NSButton(title: WSL10n.text("settings.shade.supplement.welcome", zh: "欢迎使用 WindowShade…"),
                               target: owner, action: #selector(AppDelegate.showWelcomeGuide))
        welcome.bezelStyle = .rounded; addArrangedSubview(welcome)
    }
    required init?(coder:NSCoder) { nil }
}
