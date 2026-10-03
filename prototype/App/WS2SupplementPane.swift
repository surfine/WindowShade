import Cocoa
/// 插入既有卷帘设置页。新硬件能力未取得准入证明时，不能让开关伪装成可用。
@MainActor final class WS2SupplementPane: NSStackView {
    private weak var owner: AppDelegate?
    init(owner: AppDelegate) {
        self.owner = owner; super.init(frame:.zero)
        orientation = .vertical; alignment = .leading; spacing = 12
        let heading = NSTextField(labelWithString:"专注与输入")
        heading.font = .systemFont(ofSize:13,weight:.semibold); addArrangedSubview(heading)
        let focus = NSButton(title:"开始番茄钟",target:owner,action:#selector(AppDelegate.ws2OpenFocus))
        focus.bezelStyle = .rounded; focus.isEnabled = NotchController.isEnabled && NotchActivityController.isEnabled
        focus.toolTip = "打开番茄钟。快捷键可在快捷键设置中录制。"
        addArrangedSubview(focus)
        addArrangedSubview(WS2FocusSettingsRows(runtime: owner.ws2Runtime))
        for (title,reason) in [("指挥模式","需要已核准的输入设备和助手连接"),("平滑滚动","需要确认每条事件的设备来源"),
                                ("Apple TV 遥控器","需要通过当前设备的按钮与触点探针"),("游戏手柄","需要完成当前连接的映射与阻力归零检查"),
                                ("在场检测","需要已绑定身份的蓝牙读回来源")] {
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 10
            let toggle = NSButton(checkboxWithTitle:title,target:nil,action:nil)
            toggle.state = .off; toggle.isEnabled = false; toggle.toolTip = reason; toggle.setAccessibilityHelp(reason)
            let note = NSTextField(wrappingLabelWithString:reason); note.font = .systemFont(ofSize:11); note.textColor = .secondaryLabelColor
            row.addArrangedSubview(toggle); row.addArrangedSubview(note); addArrangedSubview(row)
        }
        let activity = NSButton(title:"打开实时活动",target:owner,action:#selector(AppDelegate.openActivitiesAction))
        activity.bezelStyle = .rounded; addArrangedSubview(activity)
        let overlay = NSButton(checkboxWithTitle:"锁屏开合效果",target:owner,action:#selector(AppDelegate.toggleLockOverlayAction))
        overlay.state = owner.duoController.lockOverlay.enabled ? .on : .off; addArrangedSubview(overlay)
        let welcome = NSButton(title:"欢迎使用 WindowShade…",target:owner,action:#selector(AppDelegate.showWelcomeGuide))
        welcome.bezelStyle = .rounded; addArrangedSubview(welcome)
        // owned Codex：本地选项目、按票据启动、查看会话、停止。没有真模型列表就不显示“已连接”。
        let codexHeading = NSTextField(labelWithString:"编程助手（本机 Codex）")
        codexHeading.font = .systemFont(ofSize:13,weight:.semibold); addArrangedSubview(codexHeading)
        let project = NSTextField(labelWithString: owner.ws2Runtime.launch.projectURL?.path ?? "尚未选择项目")
        project.font = .systemFont(ofSize:11); project.textColor = .secondaryLabelColor
        project.lineBreakMode = .byTruncatingMiddle; project.toolTip = project.stringValue
        addArrangedSubview(project)
        let status = NSTextField(labelWithString: owner.ws2Runtime.launch.statusText)
        status.font = .systemFont(ofSize:11); status.textColor = .secondaryLabelColor
        addArrangedSubview(status)
        let codexButtons = NSStackView(); codexButtons.orientation = .horizontal; codexButtons.spacing = 8
        for (title, action) in [("选择项目…", #selector(AppDelegate.ws2ChooseProject)),
                                ("启动 Codex", #selector(AppDelegate.ws2OwnedStart)),
                                ("打开会话", #selector(AppDelegate.ws2OwnedOpenSessions)),
                                ("停止会话", #selector(AppDelegate.ws2OwnedStop))] {
            let button = NSButton(title: title, target: owner, action: action)
            button.bezelStyle = .rounded
            codexButtons.addArrangedSubview(button)
        }
        addArrangedSubview(codexButtons)
        let codexNote = NSTextField(wrappingLabelWithString:
            "允许一次普通命令仍然要过完整审阅和 Touch ID；文件、网络和长期规则不在这里批准。")
        codexNote.font = .systemFont(ofSize:11); codexNote.textColor = .secondaryLabelColor
        codexNote.maximumNumberOfLines = 2
        addArrangedSubview(codexNote)
    }
    required init?(coder:NSCoder) { nil }
}
