// 设置窗口与引导页：设置窗口/引导页视图构建、权限引导状态刷新、
// 偏好开关动作。作为 AppDelegate 扩展实现。

import Cocoa
import Carbon.HIToolbox
import ServiceManagement

extension AppDelegate {
@objc func toggleTitlebarDoubleClick(_ sender: NSMenuItem) {
        titlebarDoubleClickEnabled.toggle()
        UserDefaults.standard.set(titlebarDoubleClickEnabled, forKey: shadeTitlebarDoubleClickDefaultsKey)
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
    }


@objc func togglePinnedPreviewAction() {
        pinnedPreviewController.pinCurrentTargetPreview()
    }

@objc func toggleCarryAction() {
        MainActor.assumeIsolated { carry.toggleCurrentWindow() }
    }

@objc func toggleLaunchpadAction() {
        MainActor.assumeIsolated { launchpad.toggle() }
    }

    @objc func magicTileAction() {
        MainActor.assumeIsolated { gestures.magicTile() }
    }

    @objc func tuckAllAction() {
        MainActor.assumeIsolated { _ = notch.tuckAll() }
    }

    @objc func tuckCurrentAction() {
        MainActor.assumeIsolated { _ = notch.tuckFocused() }
    }

    @objc func nextDisplayAction() {
        MainActor.assumeIsolated { _ = gestures.moveToNextDisplay() }
    }

    @objc func pictureInPictureAction() {
        MainActor.assumeIsolated { pip.toggleCurrentWindow() }
    }

    @objc func toggleSlideOverAction() {
        MainActor.assumeIsolated { slideOver.toggleCurrentWindow() }
    }

@objc func exitSlideOverAction() {
        MainActor.assumeIsolated { slideOver.exit(reason: "menu") }
    }

@objc func cancelPinnedPreviewMenuItem(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        pinnedPreviewController.stopPreviewFromMenu(id: CGWindowID(number.uint32Value))
        rebuildMenu()
    }

@objc func toggleSuspendPinnedPreviewsAction() {
        pinnedPreviewController.toggleSuspendAll()
        rebuildMenu()
    }

@objc func stopAllPinnedPreviewsAction() {
        pinnedPreviewController.stopAllPreviews(reason: "menu-stop-all")
        rebuildMenu()
    }

    func soundName(defaultsKey: String, fallback: String) -> String {
        let name = UserDefaults.standard.string(forKey: defaultsKey) ?? fallback
        return shadeSoundChoices.contains(where: { $0.name == name }) ? name : fallback
    }

    func playShadeSound(_ name: String) {
        guard soundEnabled else { return }
        shadeSounds.play(name)
    }

    /// 折叠/展开动画开始前叫醒音频设备（见 ShadeSoundPlayer 的说明）：这样音效落在动作上，不迟半秒。
    func prewarmShadeSound(_ name: String) {
        guard soundEnabled else { return }
        shadeSounds.prewarm(name)
    }

    func playFoldSound() {
        playShadeSound(soundName(defaultsKey: shadeFoldSoundDefaultsKey, fallback: shadeDefaultFoldSound))
    }

    func prewarmFoldSound() {
        prewarmShadeSound(soundName(defaultsKey: shadeFoldSoundDefaultsKey, fallback: shadeDefaultFoldSound))
    }

    func playUnfoldSound() {
        playShadeSound(soundName(defaultsKey: shadeUnfoldSoundDefaultsKey, fallback: shadeDefaultUnfoldSound))
    }

    func prewarmUnfoldSound() {
        prewarmShadeSound(soundName(defaultsKey: shadeUnfoldSoundDefaultsKey, fallback: shadeDefaultUnfoldSound))
    }

    func refreshPreferencesWindowIfOpen() {
        if let settingsWindow = duoController.settingsWindow,
           settingsWindow.window?.isVisible == true {
            settingsWindow.refreshSettings()
        }
    }

    func quietNotice(_ message: String, log: String? = nil) {
        wlog(log ?? "notice: \(message)")
        // 在刘海上说（灵动岛那样），人一眼看得到；刘海关着、正展开着时才退回菜单栏标题。
        let tone = Self.noticeTone(message)
        let needsPermission = message.contains("权限")
        let spoken = MainActor.assumeIsolated {
            notch.announce(message, detail: needsPermission ? "点一下打开设置" : "", tone: tone,
                           onClick: needsPermission ? { [weak self] in self?.showPermissionOnboardingIfNeeded(force: true) } : nil)
        }
        if spoken { return }
        statusNoticeWorkItem?.cancel()
        // 菜单栏标题保持短小（完整文案在 tooltip 与可访问性值里），
        // 否则一句长提示会把状态栏条挤得很宽，顶开旁边的菜单栏项目。
        statusItem.button?.title = " \(PaperSurfaceAccessibility.statusItemNoticeTitle(message))"
        statusItem.button?.toolTip = message
        statusItem.button?.setAccessibilityValue(message)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.statusNoticeWorkItem = nil
            self.rebuildMenu()
        }
        statusNoticeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

/// 提示的语气：“已……”是做成了；说做不了、缺什么的是出了问题；其余是说明。
static func noticeTone(_ message: String) -> NotchPanel.Tone {
    if message.hasPrefix("已") { return .done }
    let problems = ["不能", "没有", "没能", "失败", "未完成", "不支持", "需要", "暂时", "无法", "占用", "打不开", "关着",
                    "没跟上", "没有跟上", "被保留", "存不下", "取不到", "不可用", "只有"]
    return problems.contains(where: message.contains) ? .problem : .info
}

/// 系统标准“关于”面板 + 一句用途说明与许可信息（代理应用从状态栏菜单进入）。
@objc func showAboutPanel() {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String ?? ""
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    NSApp.orderFrontStandardAboutPanel(options: StandardMenu.aboutPanelOptions(
        version: version, build: build))
    NSApp.activate()
}

@objc func showPreferences() {
        showSettingsWindow()
    }

    private func makeSettingsPageRoot() -> (NSView, NSStackView) {
        // 背景由设置窗口的详情区统一铺满，页面保持透明。
        let root = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
        ])
        return (root, stack)
    }

    // 与效果页一致：页内不重复大标题，只留一行说明。
    private func makeSettingsHeader(title: String, subtitle: String, symbolName: String? = nil) -> NSView {
        let caption = NSTextField(wrappingLabelWithString: subtitle)
        caption.font = SystemAppearancePolicy.font(relativeToBody: -1)
        caption.textColor = .secondaryLabelColor
        caption.maximumNumberOfLines = 2
        return caption
    }

    func makeShadeSettingsPage() -> NSView {
        let (root, stack) = makeSettingsPageRoot()
        stack.addArrangedSubview(makeSettingsHeader(
            title: "卷帘", subtitle: "设置怎么收起窗口、收起后什么样、要不要提示音。", symbolName: "rectangle.compress.vertical"))

        let trigger = makeUnifiedSettingsCard([
            makeUnifiedToggleRow(name: "双击标题栏收起窗口", subtitle: titlebarDoubleClickPreferenceSubtitle(),
                                 isOn: titlebarDoubleClickEnabled, action: #selector(prefToggleTitlebarDoubleClick(_:))),
            makeUnifiedToggleRow(name: "看一眼", subtitle: "指针停在卷帘条上，窗口在原处出现，移开就收回",
                                 isOn: GlanceController.isEnabled, action: #selector(prefToggleGlance(_:))),
            makeUnifiedToggleRow(name: "标题栏手势", subtitle: trackpadGesturePreferenceSubtitle(),
                                 isOn: TrackpadGestureController.isEnabled,
                                 action: #selector(prefToggleTrackpadGestures(_:))),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("触发"))
        stack.addArrangedSubview(trigger)
        trigger.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: trigger)

        let notchCard = makeUnifiedSettingsCard([
            makeUnifiedToggleRow(name: "收进刘海", subtitle: "朝刘海甩一下标题栏，窗口就收进刘海；指针停在刘海上，点一下放回",
                                 isOn: NotchController.isEnabled, action: #selector(prefToggleNotch(_:))),
            makeUnifiedToggleRow(name: "有变化时提醒", subtitle: "收起的窗口标题变了，比如编译完成，刘海会短暂展开告诉你",
                                 isOn: NotchController.alertsEnabled, action: #selector(prefToggleNotchAlerts(_:))),
            makeUnifiedToggleRow(name: "实时活动", subtitle: "在刘海和启动台负一屏查看音乐、耳机、隔空投送与路线",
                                 isOn: NotchActivityController.isEnabled, action: #selector(prefToggleActivities(_:))),
            // 欢迎窗口第二步问的那一句，在这里能改；没答时一段都不选。
            makeUnifiedControlRow(name: "之前常用", subtitle: "卡住时，刘海按你原来的习惯提示 Mac 上怎么做",
                                  control: SwitcherOriginControl.make()),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("刘海"))
        stack.addArrangedSubview(notchCard)
        notchCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: notchCard)

        let gapSeg = NSSegmentedControl(labels: ["不留", "窄", "宽"], trackingMode: .selectOne,
                                        target: self, action: #selector(prefSelectArrangeGap(_:)))
        gapSeg.selectedSegment = ArrangeGap.choices.firstIndex(of: ArrangeGap.points) ?? 0
        let arrangeCard = makeUnifiedSettingsCard([
            makeUnifiedControlRow(name: "窗口之间留缝",
                                  subtitle: "半屏、四角、网格、魔法平铺、卷轴排好的窗口之间和屏幕边留一道缝",
                                  control: gapSeg),
            makeUnifiedToggleRow(name: "分屏把手",
                                 subtitle: "两扇窗口拼满一块屏时，中间出现一根小竖条：拖它两扇一起变，推到屏幕边那一扇进侧拉",
                                 isOn: SplitViewController.isEnabled, action: #selector(prefToggleSplitDivider(_:))),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("排布"))
        stack.addArrangedSubview(arrangeCard)
        arrangeCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: arrangeCard)

        stack.addArrangedSubview(makePrefGroupLabel("外观"))
        let collapseRows = makeCollapseAppearanceRows()   // [收起后的样子, 卷帘条/缩略图半透明]
        let appearance = makeUnifiedSettingsCard([
            collapseRows[0],
            makeUnifiedToggleRow(name: "浮在其他窗口上面", subtitle: "收起的窗口也不会被别的窗口挡住",
                                 isOn: floatingOnTop, action: #selector(prefToggleFloating(_:))),
            collapseRows[1],
        ])
        stack.addArrangedSubview(appearance)
        appearance.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)

        let ws2Pane = MainActor.assumeIsolated { WS2SupplementPane(owner: self) }
        stack.addArrangedSubview(ws2Pane)
        ws2Pane.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        stack.addArrangedSubview(makePrefGroupLabel("声音"))
        let sound = makeUnifiedSettingsCard([
            makeUnifiedToggleRow(name: "收起和展开时播放音效", subtitle: nil,
                                 isOn: soundEnabled, action: #selector(prefToggleSound(_:))),
            makeUnifiedControlRow(name: "收起音效", subtitle: nil,
                                  control: makeSoundPopup(selected: foldSoundName, action: #selector(prefSelectFoldSound(_:)))),
            makeUnifiedControlRow(name: "展开音效", subtitle: nil,
                                  control: makeSoundPopup(selected: unfoldSoundName, action: #selector(prefSelectUnfoldSound(_:)))),
        ])
        stack.addArrangedSubview(sound)
        sound.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return root
    }

    /// 隐私一栏（原「权限与启动」）：先摊开读到的每一样（内容从 tools/privacy/registry.json 生成），
    /// 再把两项系统授权、登录时启动和更新并进同一页——开关全都还是原来那一个，不复制。
    func makePermissionsSettingsPage() -> NSView {
        let (root, stack) = makeSettingsPageRoot()
        stack.addArrangedSubview(makeSettingsHeader(
            title: "隐私", subtitle: "WindowShade 读到的每一样都列在这里。", symbolName: "hand.raised"))
        let pane = MainActor.assumeIsolated { WS2PrivacyPane(owner: self) }
        stack.addArrangedSubview(pane)
        pane.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: pane)
        stack.addArrangedSubview(makePrefGroupLabel("权限"))
        let permissions = makeUnifiedSettingsCard([
            makeUnifiedPermissionRow(symbol: "accessibility", name: "辅助功能",
                                     subtitle: "找到、移动和恢复窗口",
                                     granted: hasAccessibilityPermission(), action: #selector(openAccessibilitySettingsAction)),
            makeUnifiedPermissionRow(symbol: "rectangle.inset.filled.and.person.filled",
                                     name: "屏幕录制", subtitle: "截取窗口画面做预览",
                                     granted: hasScreenRecordingPermission(), action: #selector(openScreenRecordingSettingsAction)),
        ], separatorInset: 46)
        stack.addArrangedSubview(permissions)
        permissions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(makePrefGroupLabel("启动"))
        let launch = makeUnifiedSettingsCard([
            makeUnifiedToggleRow(name: "登录时自动启动", subtitle: launchAtLoginSubtitle(),
                                 isOn: launchAtLoginEnabled(), action: #selector(prefToggleLaunchAtLogin(_:))),
        ])
        stack.addArrangedSubview(launch)
        launch.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: launch)
        stack.addArrangedSubview(makePrefGroupLabel(UpdateCopy.settingsGroup))
        let update = makeUnifiedSettingsCard(MainActor.assumeIsolated { UpdaterController.shared.makeSettingsRows() })
        stack.addArrangedSubview(update)
        update.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return root
    }

    func makePrefGroupLabel(_ text: String) -> NSView {
        // 分组标题只有文字，与「效果」「高级」两页保持一致。
        let field = NSTextField(labelWithString: text)
        field.font = SystemAppearancePolicy.font(relativeToBody: -1, weight: .semibold)
        field.textColor = .secondaryLabelColor
        return field
    }

    /// 设置里每一张卡片的外观；隐私页也从同一处拿，别再写第二套样式。
    func makeUnifiedSettingsCard(_ rows: [NSView], separatorInset: CGFloat = 16) -> NSView {
        let card = SettingsGroupBox()
        card.wantsLayer = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 0
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
        ])

        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                let line = NSView()
                separator.translatesAutoresizingMaskIntoConstraints = false
                line.addSubview(separator)
                inner.addArrangedSubview(line)
                NSLayoutConstraint.activate([
                    line.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -16),
                    line.heightAnchor.constraint(equalToConstant: 0.5),
                    separator.leadingAnchor.constraint(equalTo: line.leadingAnchor, constant: separatorInset - 16),
                    separator.trailingAnchor.constraint(equalTo: line.trailingAnchor),
                    separator.centerYAnchor.constraint(equalTo: line.centerYAnchor),
                ])
            }
            inner.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        }
        return card
    }

    func makePermissionDesignSample() -> NSView {
        makeUnifiedSettingsCard([
            makeUnifiedPermissionRow(symbol: "accessibility", name: "辅助功能",
                subtitle: "找到、移动和恢复窗口", granted: false,
                action: #selector(openAccessibilitySettingsAction)),
            makeUnifiedPermissionRow(symbol: "rectangle.inset.filled.and.person.filled", name: "屏幕录制",
                subtitle: "截取窗口画面做预览", granted: true,
                action: #selector(openScreenRecordingSettingsAction)),
        ], separatorInset: 46)
    }

    private func makeUnifiedLabels(name: String, subtitle: String?) -> NSStackView {
        // 设置页在主线程上搭；符号表与气泡按钮是 MainActor 上的东西，照本文件既有写法显式声明。
        let symbol = MainActor.assumeIsolated { WS2SettingsCopy.symbol(for: name) }
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(hierarchicalColor: .controlAccentColor)
        icon.wantsLayer = true
        icon.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        icon.layer?.cornerRadius = 7
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        let title = NSTextField(labelWithString: name)
        title.font = SystemAppearancePolicy.font(relativeToBody: 0)
        labels.addArrangedSubview(title)
        if let subtitle {
            let short = WS2SettingsCopy.short[subtitle] ?? String(subtitle.prefix(16))
            let detail = NSTextField(labelWithString: short)
            detail.font = SystemAppearancePolicy.font(relativeToBody: -2)
            detail.textColor = .secondaryLabelColor
            detail.lineBreakMode = .byTruncatingTail
            detail.maximumNumberOfLines = 1
            detail.toolTip = subtitle
            labels.addArrangedSubview(detail)
        }
        let content = NSStackView(views: [icon, labels])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 10
        if let subtitle {
            content.addArrangedSubview(MainActor.assumeIsolated { WS2SettingsInfoButton(text: subtitle, name: name) })
        }
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return content
    }

    private func makeUnifiedToggleRow(name: String, subtitle: String?, isOn: Bool,
                                      action: Selector) -> NSView {
        let toggle = NSSwitch()
        toggle.state = isOn ? .on : .off
        toggle.target = self
        toggle.action = action
        toggle.setAccessibilityLabel(name)
        toggle.controlSize = .regular
        let labels = makeUnifiedLabels(name: name, subtitle: subtitle)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [labels, toggle])
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labels.trailingAnchor.constraint(equalTo: toggle.leadingAnchor, constant: -14),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -8),
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: subtitle == nil ? 40 : 48).isActive = true
        return row
    }

    private func makeUnifiedControlRow(name: String, subtitle: String?, control: NSControl) -> NSView {
        control.sizeToFit()
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        let labels = makeUnifiedLabels(name: name, subtitle: subtitle)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [labels, control])
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labels.trailingAnchor.constraint(equalTo: control.leadingAnchor, constant: -14),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -8),
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: subtitle == nil ? 40 : 48).isActive = true
        return row
    }

    private func makeUnifiedPermissionRow(symbol: String, name: String, subtitle: String,
                                           granted: Bool, action: Selector) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: name) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let labels = makeUnifiedLabels(name: name, subtitle: subtitle)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let chip = NSButton(title: granted ? "✓ 已授权" : "● 去授权", target: self, action: action)
        chip.isBordered = false
        chip.font = SystemAppearancePolicy.font(relativeToBody: -1)
        chip.contentTintColor = granted ? .systemGreen : .systemOrange
        SystemCornerRadius.apply(to: chip, radius: SystemCornerRadius.control)
        chip.setAccessibilityLabel("\(name)，\(granted ? "已授权，打开设置" : "去授权")")
        chip.setContentHuggingPriority(.required, for: .horizontal)
        let trailing = chip
        let row = NSStackView(views: [icon, labels, trailing])
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -12),
            trailing.trailingAnchor.constraint(equalTo: row.trailingAnchor),
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        return row
    }

    func makeSoundPopup(selected: String, action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 170, height: 26), pullsDown: false)
        for sound in shadeSoundChoices {
            popup.addItem(withTitle: sound.label)
            popup.lastItem?.representedObject = sound.name
            if sound.name == selected {
                popup.select(popup.lastItem)
            }
        }
        popup.target = self
        popup.action = action
        return popup
    }

    func titlebarDoubleClickPreferenceSubtitle() -> String {
        // 标题已经说了“双击收起”，说明只补标题里没有的信息。
        systemTitlebarTripleClickDescription() ?? "在任意窗口的标题栏上双击"
    }

    func launchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func launchAtLoginSubtitle() -> String {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return "WindowShade 会在登录后自动运行"
            case .requiresApproval:
                return "需要在系统设置中批准登录项"
            case .notRegistered:
                return "开机后自动运行 WindowShade"
            case .notFound:
                return "当前 app bundle 不支持登录项"
            @unknown default:
                return "开机后自动运行 WindowShade"
            }
        }
        return "当前系统不支持"
    }

    @objc func prefToggleTitlebarDoubleClick(_ sender: NSSwitch) {
        titlebarDoubleClickEnabled = sender.state == .on
        UserDefaults.standard.set(titlebarDoubleClickEnabled, forKey: shadeTitlebarDoubleClickDefaultsKey)
        rebuildMenu()
    }

    func trackpadGesturePreferenceSubtitle() -> String {
        if TrackpadGestureController.conflictingApp() != nil {
            return "Swish 正在运行，标题栏上的手势交给它；在卷帘条上往下滑仍可展开"
        }
        return "在标题栏上两指滑动、滚动滚轮或拖着甩一下：往上收起，往下铺满"
    }

    @objc func prefToggleTrackpadGestures(_ sender: NSSwitch) {
        TrackpadGestureController.isEnabled = sender.state == .on
        MainActor.assumeIsolated { gestures.refreshMonitors() }
        rebuildMenu()
    }

    @objc func prefToggleNotch(_ sender: NSSwitch) {
        MainActor.assumeIsolated { notch.setEnabled(sender.state == .on) }
    }

    @objc func prefToggleActivities(_ sender: NSSwitch) {
        NotchActivityController.isEnabled = sender.state == .on
        MainActor.assumeIsolated { notch.activities.configure() }
    }
    @objc func prefToggleNotchAlerts(_ sender: NSSwitch) {
        MainActor.assumeIsolated { notch.setAlertsEnabled(sender.state == .on) }
    }

    @objc func prefToggleGlance(_ sender: NSSwitch) {
        GlanceController.isEnabled = sender.state == .on
        if !GlanceController.isEnabled {
            MainActor.assumeIsolated { glance.cancelAll(reason: "setting-off") }
        }
        rebuildMenu()
    }

    @objc func prefToggleFloating(_ sender: NSSwitch) {
        floatingOnTop = sender.state == .on
        UserDefaults.standard.set(floatingOnTop, forKey: shadeFloatingOnTopDefaultsKey)
        refreshOverlayPresentation(bringForward: floatingOnTop)
        rebuildMenu()
    }

    @objc func prefToggleSound(_ sender: NSSwitch) {
        soundEnabled = sender.state == .on
        UserDefaults.standard.set(soundEnabled, forKey: shadeSoundEnabledDefaultsKey)
    }

    @objc func prefToggleLaunchAtLogin(_ sender: NSSwitch) {
        guard #available(macOS 13.0, *) else {
            sender.state = .off
            quietNotice("系统不支持", log: "launch-at-login: unsupported macOS")
            return
        }
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
                wlog("launch-at-login: register status=\(SMAppService.mainApp.status)")
            } else {
                try SMAppService.mainApp.unregister()
                wlog("launch-at-login: unregister status=\(SMAppService.mainApp.status)")
            }
        } catch {
            sender.state = launchAtLoginEnabled() ? .on : .off
            quietNotice("无法修改开机自启", log: "launch-at-login: failed \(error.localizedDescription)")
        }
        refreshPreferencesWindowIfOpen()
    }

    @objc func prefSelectFoldSound(_ sender: NSPopUpButton) {
        foldSoundName = sender.selectedItem?.representedObject as? String ?? shadeDefaultFoldSound
        UserDefaults.standard.set(foldSoundName, forKey: shadeFoldSoundDefaultsKey)
        playFoldSound()
    }

    @objc func prefSelectUnfoldSound(_ sender: NSPopUpButton) {
        unfoldSoundName = sender.selectedItem?.representedObject as? String ?? shadeDefaultUnfoldSound
        UserDefaults.standard.set(unfoldSoundName, forKey: shadeUnfoldSoundDefaultsKey)
        playUnfoldSound()
    }

    @objc func openAccessibilitySettingsAction() {
        openAccessibilityPrivacySettings()
    }

    @objc func openScreenRecordingSettingsAction() {
        openScreenRecordingPrivacySettings()
    }

@objc func showWelcomeGuide() {
        // 菜单里的“欢迎使用 WindowShade…”：从第一页看起。
        showPermissionOnboarding()
    }

    func showPermissionOnboardingIfNeeded(force: Bool) {
        let missing = !hasAccessibilityPermission() || !hasScreenRecordingPermission()
        let shouldShowFirstRun = !UserDefaults.standard.bool(forKey: shadeOnboardingShownDefaultsKey)
        guard missing || shouldShowFirstRun || force else { return }
        if !force && UserDefaults.standard.bool(forKey: shadeOnboardingShownDefaultsKey) { return }
        // force 都是缺权限时的提醒（按快捷键没权限、刘海里点“需要权限”、换显示器时的恢复）：直接到授权页，
        // 和 1.0.15 一样一打开就看得到授权行。首次打开从第一页看起。
        showPermissionOnboarding(toPermissions: force)
    }

    /// 欢迎使用 WindowShade：三步，一句话说清它是什么、问“你之前常用哪个？”、授权（见 Welcome.swift）。
    /// toPermissions：缺权限时的提醒，直接翻到授权页；否则从第一步开始。
    func showPermissionOnboarding(toPermissions: Bool = false) {
        MainActor.assumeIsolated { showWelcome(startPage: toPermissions ? WelcomeView.permissionPage : 0) }
    }

    /// 欢迎窗口里那一页（窗口没建过或内容换过时是 nil）。
    @MainActor var onboardingWelcomeView: WelcomeView? {
        onboardingWindow?.contentView?.subviews.lazy.compactMap { $0 as? WelcomeView }.first
    }

    /// 装好新版本后辅助功能或屏幕录制没了（系统有时要重新打开）：翻到授权页，换成“再打开一次这两项”那组文案。
    func showPermissionsAgainAfterUpdate() {
        MainActor.assumeIsolated {
            showWelcome(startPage: WelcomeView.permissionPage)
            onboardingWelcomeView?.permissionsAgain = true
        }
    }

    @MainActor private func showWelcome(startPage: Int) {
        let permissionPage = WelcomeView.permissionPage
        // 已经开着：不重建、不挪回正中，看到哪一页还在哪一页，只拿到最前面；缺权限的提醒才翻到授权页。
        if let window = onboardingWindow, window.isVisible, let current = onboardingWelcomeView {
            if startPage == permissionPage, current.index != permissionPage || current.onMoveStep { current.show(permissionPage) }
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(current)
            NSApp.activate()
            updateOnboardingRefresh()
            return
        }
        let view = WelcomeView(frame: NSRect(origin: .zero, size: WelcomeView.size))
        view.permissionsGranted = { hasAccessibilityPermission() && hasScreenRecordingPermission() }
        view.onFinish = { [weak self] in self?.dismissOnboarding() }
        view.onLater = { [weak self] in self?.dismissOnboarding() }
        onboardingPermissionStack = view.permissionStack
        onboardingProgressLabel = view.progressLabel
        onboardingDoneButton = nil
        onboardingCaption = nil
        let window: NSWindow
        if let existing = onboardingWindow {
            window = existing
        } else {
            window = NSWindow(contentRect: NSRect(origin: .zero, size: WelcomeView.size),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "欢迎使用 WindowShade"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            // 引导页是独立工具窗口，不参与系统标签页合并。
            window.tabbingMode = .disallowed
            onboardingWindow = window
            // 点关闭按钮也算看过：否则下次启动它又会自己弹出来。缺权限时的再次提醒
            // 走的是“缺权限”这条判断，不受这个标记影响。
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                UserDefaults.standard.set(true, forKey: shadeOnboardingShownDefaultsKey)
                self?.onboardingRefreshTimer?.invalidate()
                self?.onboardingRefreshTimer = nil
            }
            // 整个被挡住、在别的桌面上时授权页不再每秒查；又看得见了马上刷新一次、接着查。
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateOnboardingRefresh() }
            }
        }
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: WelcomeView.size))
        let appearance = SystemAppearanceCapabilities.current
        background.material = SystemAppearancePolicy.usesOpaqueFallback(appearance) ? .contentBackground : .underPageBackground
        background.blendingMode = .withinWindow
        view.autoresizingMask = [.width, .height]
        background.addSubview(view)
        window.contentView = background
        window.setContentSize(WelcomeView.size)
        window.center()
        refreshOnboardingState()
        view.onPageChange = { [weak self] in self?.updateOnboardingRefresh() }
        // 从第一步打开、而 App 不在“应用程序”里：三步之前先问要不要放进去（UpdaterMove 决定要不要这一步）。
        // 开发版没有更新清单地址、不启动更新器，“放进去才能更新”对它不成立，不问。
        if startPage == 0, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
           let move = UpdaterMove.shared.welcomeStep() {
            view.showMove(move)
        } else if view.index != startPage { view.show(startPage) } else { view.refreshButtons() }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate()
        updateOnboardingRefresh()
    }

    /// 授权页的刷新：在系统设置里打开了，这里马上变成打勾。只在窗口看得见、停在授权页、还没全部授权时每秒查一次；
    /// 翻到别的页、两项都有了、窗口收起来或整个被挡住就停（1.0.15 起权限齐全时本来就不跑）。
    @MainActor func updateOnboardingRefresh() {
        guard let window = onboardingWindow, window.isVisible, window.occlusionState.contains(.visible),
              let view = onboardingWelcomeView, view.index == WelcomeView.permissionPage else {
            onboardingRefreshTimer?.invalidate()
            onboardingRefreshTimer = nil
            return
        }
        if refreshOnboardingState() { view.refreshButtons() }
        if view.shownGrants == [true, true] {
            onboardingRefreshTimer?.invalidate()
            onboardingRefreshTimer = nil
        } else if onboardingRefreshTimer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateOnboardingRefresh() }
            }
            timer.tolerance = 0.2
            onboardingRefreshTimer = timer
        }
    }

    /// 按现在的授权状态画授权行和进度字；和上次画的一样就什么都不动。返回画没画。
    @MainActor @discardableResult
    func refreshOnboardingState() -> Bool {
        guard let permissionStack = onboardingPermissionStack else { return false }
        let ax = hasAccessibilityPermission()
        let screen = hasScreenRecordingPermission()
        let welcome = onboardingWelcomeView
        if let welcome, welcome.shownGrants == [ax, screen] { return false }
        welcome?.shownGrants = [ax, screen]

        permissionStack.arrangedSubviews.forEach {
            permissionStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let card = makeUnifiedSettingsCard([
            makeUnifiedPermissionRow(symbol: "accessibility", name: "辅助功能",
                subtitle: "找到、移动和恢复窗口", granted: ax,
                action: #selector(openAccessibilitySettingsAction)),
            makeUnifiedPermissionRow(symbol: "rectangle.inset.filled.and.person.filled", name: "屏幕录制",
                subtitle: "截取窗口画面做预览", granted: screen,
                action: #selector(openScreenRecordingSettingsAction)),
        ], separatorInset: 46)
        permissionStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalToConstant: onboardingContentWidth).isActive = true

        let grantedCount = (ax ? 1 : 0) + (screen ? 1 : 0)
        let allGranted = grantedCount == 2
        if let progress = onboardingProgressLabel {
            if allGranted {
                progress.stringValue = "权限已就绪"
                progress.textColor = .systemGreen
            } else {
                progress.stringValue = "还差\(2 - grantedCount)步权限 · \(grantedCount) / 2 已完成"
                progress.textColor = .labelColor
            }
        }
        onboardingDoneButton?.isEnabled = allGranted
        onboardingCaption?.isHidden = allGranted
        return true
    }

    // MARK: 窗口浏览

    @objc func openActivitiesAction() {
        MainActor.assumeIsolated { launchpad.navigate(to: .today) }
    }

    @objc func verifyTouchIDAction() {
        MainActor.assumeIsolated { notch.authentication.selfCheck() }
    }

    @objc func toggleLockOverlayAction() {
        duoController.lockOverlay.setEnabled(!duoController.lockOverlay.enabled)
        duoController.settingsChanged()
        scheduleMenuRebuild()
    }

    @objc func observeFaceAction(_ sender: NSMenuItem) {
        guard let cameraID = sender.representedObject as? String else { return }
        MainActor.assumeIsolated { notch.faceObservations.start(cameraID: cameraID) }
    }

    @objc func openWindowBrowserPanel() {
        windowBrowserController?.openKeyboardPanel()
    }

    func makeShortcutsSettingsPage() -> NSView {
        let (root, stack) = makeSettingsPageRoot()
        stack.addArrangedSubview(makeSettingsHeader(
            title: "快捷键",
            subtitle: "在任何应用里都能用。点“录制…”再按下新的组合；“清除”会关掉这个快捷键。",
            symbolName: "command"))

        func recorderRow(_ shortcut: GlobalShortcut, subtitle: String?) -> NSView {
            let recorder = HotKeyRecorderView(accessibilityName: shortcut.title)
            recorder.configure(current: GlobalShortcutSettings.hotKey(for: shortcut))
            recorder.validate = { hotKey in
                GlobalShortcutSettings.conflictName(for: hotKey, excluding: shortcut)
                    .map { "已用于：\($0)" }
            }
            recorder.onCapture = { [weak self, weak recorder] hotKey in
                self?.applyShortcut(hotKey, for: shortcut)
                recorder?.configure(current: GlobalShortcutSettings.hotKey(for: shortcut))
            }
            return makeUnifiedControlRow(name: shortcut.title, subtitle: subtitle, control: recorder)
        }

        let window = makeUnifiedSettingsCard([
            recorderRow(.toggleShade, subtitle: nil),
            recorderRow(.pinPreview, subtitle: nil),
            recorderRow(.suspendPins, subtitle: "一下让开所有置顶的窗口，再按一下按原来的前后顺序放回"),
            recorderRow(.carry, subtitle: "窗口留在原处，在别的桌面上也能看一眼"),
            recorderRow(.slideOver, subtitle: "窗口靠到屏幕边、浮在前面；再按一次收到屏幕边，或拉出来"),
            recorderRow(.pictureInPicture, subtitle: "窗口缩成一张实时画面浮在屏幕角落，再按一次回到原处；把标题栏拖到屏幕角落停一下也行"),
            recorderRow(.launchpad, subtitle: "列出所有 App；把图标拖到屏幕边就侧拉，拖到一边就开在那一半"),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("当前窗口"))
        stack.addArrangedSubview(window)
        window.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: window)

        // 和标题栏手势同一架梯子：往上变小、往下变大，左右占半屏。每一次都能撤销。
        let arrange = makeUnifiedSettingsCard([
            recorderRow(.stepLarger, subtitle: "卷帘条展开；原来大小的窗口铺满屏幕"),
            recorderRow(.stepSmaller, subtitle: "铺满的窗口回到原来大小；原来大小的窗口收起"),
            recorderRow(.leftHalf, subtitle: nil),
            recorderRow(.rightHalf, subtitle: nil),
            recorderRow(.magicTile, subtitle: "把这块屏上的窗口一次排好：要地方多的占大头，聊天放侧拉；捏合整批撤回"),
            recorderRow(.nextDisplay, subtitle: "按原来的排法放到下一块屏幕上；上下摆的显示器也行"),
            recorderRow(.tuckAll, subtitle: "这块屏上的窗口全部收进刘海，再按一下放回来"),
            recorderRow(.tuckCurrent, subtitle: "只把当前窗口收进刘海"),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("排布当前窗口"))
        stack.addArrangedSubview(arrange)
        arrange.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: arrange)

        // Rectangle、Raycast 里有的那些排法：默认不占快捷键。一键换成 Rectangle 的那一套，用惯它的人手上不用改。
        let takeOver = NSButton(title: "换上", target: self, action: #selector(prefUseRectangleShortcuts))
        takeOver.bezelStyle = .rounded
        // Swish 的方向键位：排布当前窗口的四个方向一下换成 ⌃⌥ 加字母；键名按当前键盘布局显示（Dvorak 上是 ,AOE）。
        let directionSets = DirectionKeySet.allCases
        let directionKeys = NSSegmentedControl(labels: directionSets.map(DirectionKeyPresets.label(for:)),
                                               trackingMode: .selectOne, target: self,
                                               action: #selector(prefSelectDirectionKeys(_:)))
        directionKeys.selectedSegment = DirectionKeyPresets.currentSet.flatMap(directionSets.firstIndex(of:)) ?? -1
        directionKeys.setAccessibilityLabel("方向键换成字母")
        let more = makeUnifiedSettingsCard([
            makeUnifiedControlRow(
                name: "用 Rectangle 的快捷键",
                subtitle: "装过 Rectangle 的照它现在的设置，没装过的用它推荐的那一套（⌃⌥ 加方向键和字母）。下面的名字和 Raycast 的窗口命令一一对应",
                control: takeOver),
            makeUnifiedControlRow(
                name: "方向键换成字母",
                subtitle: "变小一级、变大一级、左半屏、右半屏改用 ⌃⌥ 加字母，和 Swish 一样。别的动作在用的组合不抢",
                control: directionKeys),
            recorderRow(.topHalf, subtitle: nil),
            recorderRow(.bottomHalf, subtitle: nil),
            recorderRow(.topLeft, subtitle: nil),
            recorderRow(.topRight, subtitle: nil),
            recorderRow(.bottomLeft, subtitle: nil),
            recorderRow(.bottomRight, subtitle: nil),
            recorderRow(.leftThird, subtitle: nil),
            recorderRow(.centerThird, subtitle: nil),
            recorderRow(.rightThird, subtitle: nil),
            recorderRow(.leftTwoThirds, subtitle: nil),
            recorderRow(.rightTwoThirds, subtitle: nil),
            recorderRow(.fill, subtitle: nil),
            recorderRow(.fullHeight, subtitle: "左右不动，上下占满"),
            recorderRow(.center, subtitle: "大小不变，放到正中"),
            recorderRow(.larger, subtitle: "四边各往外 30 点"),
            recorderRow(.smaller, subtitle: "四边各往里 30 点"),
            recorderRow(.undoPlacement, subtitle: "回到排之前的位置和大小"),
            recorderRow(.previousDisplay, subtitle: "和“移到另一块屏幕”反着转"),
            recorderRow(.focusTimer, subtitle: "开始、暂停或继续同一个番茄钟；默认不占用任何快捷键"),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("更多排法"))
        stack.addArrangedSubview(more)
        more.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: more)

        let strips = makeUnifiedSettingsCard([
            recorderRow(.arrangeOrFocus, subtitle: "外观选“统一标题栏”时，改为专注当前 App；选“缩略图”时，把缩略图排到屏幕下边，再按放回原位"),
            makeUnifiedToggleRow(
                name: "按编号展开已收起的窗口",
                subtitle: "\(GlobalShortcutSettings.numberedDisplayName) 对应菜单里的前 9 个窗口",
                isOn: GlobalShortcutSettings.numberedExpandEnabled,
                action: #selector(prefToggleNumberedShortcuts(_:))),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("已收起的窗口"))
        stack.addArrangedSubview(strips)
        strips.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: strips)

        let browser = makeUnifiedSettingsCard([
            recorderRow(.windowBrowser,
                        subtitle: "默认不设置。再按一次同一个组合会关掉面板。"),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("窗口浏览"))
        stack.addArrangedSubview(browser)
        browser.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(12, after: browser)

        let reset = NSButton(title: "恢复默认", target: self, action: #selector(prefResetShortcuts))
        reset.bezelStyle = .rounded
        reset.isEnabled = !GlobalShortcutSettings.isAllDefault
        reset.setContentHuggingPriority(.required, for: .horizontal)
        // 靠右的普通按钮，与分组卡片右边缘对齐；不随页面宽度拉伸。
        let resetRow = NSStackView()
        resetRow.orientation = .horizontal
        resetRow.addView(reset, in: .trailing)
        stack.addArrangedSubview(resetRow)
        resetRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return root
    }

    /// 改键后立刻生效：重新注册、刷新菜单；新组合注册失败时退回原来的组合。
    private func applyShortcut(_ hotKey: GlobalShortcutSettings.HotKey?, for shortcut: GlobalShortcut) {
        let previous = GlobalShortcutSettings.hotKey(for: shortcut)
        guard hotKey != previous else { return }
        GlobalShortcutSettings.setHotKey(hotKey, for: shortcut)
        registerGlobalShortcuts()
        if hotKey != nil, unavailableHotKeyIDs.contains(shortcut.hotKeyID) {
            GlobalShortcutSettings.setHotKey(previous, for: shortcut)
            registerGlobalShortcuts()
        }
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
    }

    @objc func prefToggleNumberedShortcuts(_ sender: NSSwitch) {
        GlobalShortcutSettings.numberedExpandEnabled = sender.state == .on
        registerGlobalShortcuts()
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
    }

    @objc func prefResetShortcuts() {
        GlobalShortcutSettings.resetAll()
        registerGlobalShortcuts()
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
    }

    func makeWindowBrowserSettingsPage() -> NSView {
        let (root, stack) = makeSettingsPageRoot()
        stack.addArrangedSubview(makeSettingsHeader(
            title: "窗口浏览",
            subtitle: "在 Dock 图标上看这个应用的全部窗口，也可以用菜单或快捷键打开。",
            symbolName: "rectangle.on.rectangle"))

        let triggers = makeUnifiedSettingsCard([
            makeUnifiedToggleRow(
                name: "Dock 悬停查看窗口",
                subtitle: "鼠标停在 Dock 图标上时显示窗口面板。不会启动没在运行的应用。",
                isOn: WindowBrowserSettings.dockEnabled,
                action: #selector(prefToggleWindowBrowserDock(_:))),
            makeUnifiedToggleRow(
                name: "再点一下 Dock 图标，让开这个 App",
                subtitle: "它已经在最前、窗口露着时才这样（和 Windows 任务栏一样）；再点一下回来",
                isOn: DockClickHide.isEnabled,
                action: #selector(prefToggleDockClickHide(_:))),
            makeUnifiedToggleRow(
                name: "在 Dock 图标上两指上下滑",
                subtitle: "往上滑看这个 App 的所有窗口，往下滑让开这个 App",
                isOn: DockSwipeController.isEnabled,
                action: #selector(prefToggleDockSwipe(_:))),
            makeUnifiedToggleRow(
                name: "Dock 留在现在这块屏上",
                subtitle: "指针碰到别的屏的底边时 Dock 不跟过去（只管放在底部的 Dock）；打开时记下 Dock 现在在哪",
                isOn: DockLock.isEnabled,
                action: #selector(prefToggleDockLock(_:))),
            makeUnifiedToggleRow(
                name: "调度中心里按 ⌘W 关窗",
                subtitle: "指针指着哪扇就关哪扇，⌘Q 退出它的 App；只在调度中心开着时这样，平时不动你的 ⌘W",
                isOn: MissionControlKeys.isEnabled,
                action: #selector(prefToggleMissionControlKeys(_:))),
            makeUnifiedToggleRow(
                name: "在菜单里显示“选择窗口…”",
                subtitle: "默认不占用快捷键，可以在“快捷键”里设置",
                isOn: WindowBrowserSettings.keyboardPanelEnabled,
                action: #selector(prefToggleWindowBrowserKeyboard(_:))),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("触发"))
        stack.addArrangedSubview(triggers)
        triggers.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: triggers)

        let triggerSeg = NSSegmentedControl(labels: ["关", "⌥Tab", "⌘Tab"], trackingMode: .selectOne,
                                            target: self, action: #selector(prefSelectSwitcherTrigger(_:)))
        switch WindowSwitcherKeys.trigger {
        case .off: triggerSeg.selectedSegment = 0
        case .option: triggerSeg.selectedSegment = 1
        case .command: triggerSeg.selectedSegment = 2
        }
        let switcherCard = makeUnifiedSettingsCard([
            makeUnifiedControlRow(name: "按窗口切换",
                                  subtitle: "按住连按 Tab 一扇一扇地挑，松手切过去；收着的窗口也在里面。选 ⌘Tab 会换掉系统的 App 切换",
                                  control: triggerSeg),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("切换"))
        stack.addArrangedSubview(switcherCard)
        switcherCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: switcherCard)

        let preview = makeUnifiedSettingsCard([
            makeUnifiedToggleRow(
                name: "普通窗口实时预览（实验）",
                subtitle: "选中窗口 0.4 秒后开始播放实时画面",
                isOn: WindowBrowserSettings.livePreviewEnabled,
                action: #selector(prefToggleWindowBrowserLive(_:))),
            makeUnifiedControlRow(
                name: "打开窗口浏览",
                subtitle: nil,
                control: {
                    let button = NSButton(title: "打开面板…", target: self,
                                          action: #selector(openWindowBrowserPanel))
                    button.bezelStyle = .rounded
                    return button
                }()),
            makeUnifiedControlRow(
                name: "按应用排除",
                subtitle: excludedAppsSubtitle(),
                control: {
                    let button = NSButton(title: "编辑排除清单…", target: self,
                                          action: #selector(prefEditWindowBrowserExclusions))
                    button.bezelStyle = .rounded
                    return button
                }()),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("面板"))
        stack.addArrangedSubview(preview)
        preview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: preview)

        // 外观：跟随系统（可用的系统玻璃 / 原生材质）或明确的不透明背景。
        let appearanceControl = NSSegmentedControl(
            labels: WindowBrowserAppearanceStyle.allCases.map(\.displayName),
            trackingMode: .selectOne, target: self,
            action: #selector(prefChangeWindowBrowserAppearance(_:)))
        appearanceControl.selectedSegment =
            WindowBrowserAppearanceStyle.current == .paper ? 1 : 0
        let styleControl = NSSegmentedControl(
            labels: WindowBrowserSettings.PreferredStyle.allCases.map(\.displayName),
            trackingMode: .selectOne, target: self,
            action: #selector(prefChangeWindowBrowserStyle(_:)))
        styleControl.selectedSegment = WindowBrowserSettings.PreferredStyle.allCases
            .firstIndex(of: WindowBrowserSettings.preferredStyle) ?? 0
        let appearance = makeUnifiedSettingsCard([
            makeUnifiedControlRow(
                name: "面板背景",
                subtitle: "开启系统的“减少透明度”时，自动使用不透明背景。",
                control: appearanceControl),
            makeUnifiedControlRow(
                name: "默认显示方式",
                subtitle: "自动：窗口多的时候用列表，少的时候用缩略图。面板里的切换只影响这一次。",
                control: styleControl),
            makeUnifiedControlRow(
                name: "排布与撤销",
                subtitle: "在窗口右键菜单里选“排布”：左半、右半、四角、居中、铺满屏幕、"
                    + "移到另一块屏幕。可以先看效果，移好之后还能撤销。",
                control: NSTextField(labelWithString: "")),
        ])
        stack.addArrangedSubview(makePrefGroupLabel("外观"))
        stack.addArrangedSubview(appearance)
        appearance.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: appearance)

        let permissions = makeUnifiedSettingsCard([
            makeUnifiedPermissionRow(symbol: "accessibility", name: "辅助功能",
                subtitle: "识别 Dock 图标，切换、收起、展开和关闭窗口",
                granted: hasAccessibilityPermission(),
                action: #selector(openAccessibilitySettingsAction)),
            makeUnifiedPermissionRow(symbol: "rectangle.inset.filled.and.person.filled", name: "屏幕录制",
                subtitle: "窗口缩略图与实时预览；缺失时显示图标和文字列表",
                granted: hasScreenRecordingPermission(),
                action: #selector(openScreenRecordingSettingsAction)),
        ], separatorInset: 46)
        stack.addArrangedSubview(makePrefGroupLabel("权限"))
        stack.addArrangedSubview(permissions)
        permissions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let note = NSTextField(wrappingLabelWithString:
            "窗口浏览是临时面板：不会替换系统 Dock，不接管原生 Command-Tab，"
            + "不跨 Space 搬运窗口。关闭功能或退出时会释放新增的观察器、截图与预览流；"
            + "原有卷帘、恢复日志与置顶预览不受影响。")
        note.font = SystemAppearancePolicy.font(relativeToBody: -2)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 4
        stack.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return root
    }

    private func excludedAppsSubtitle() -> String {
        let ids = WindowBrowserSettings.excludedBundleIDs
        if ids.isEmpty { return "尚未排除任何应用" }
        return "已排除 \(ids.count) 个应用：\(ids.sorted().prefix(2).joined(separator: "、"))"
            + (ids.count > 2 ? " 等" : "")
    }

    @objc func prefToggleWindowBrowserDock(_ sender: NSSwitch) {
        WindowBrowserSettings.dockEnabled = sender.state == .on
        notifyWindowBrowserSettingsChanged()
    }

    @objc func prefSelectArrangeGap(_ sender: NSSegmentedControl) {
        let value = ArrangeGap.choices[max(0, min(ArrangeGap.choices.count - 1, sender.selectedSegment))]
        ArrangeGap.points = value
        UserDefaults.standard.set(Double(value), forKey: ArrangeGap.defaultsKey)
    }

    @objc func prefSelectSwitcherTrigger(_ sender: NSSegmentedControl) {
        let choices: [WindowSwitcherKeys.Trigger] = [.off, .option, .command]
        WindowSwitcherKeys.trigger = choices[max(0, min(2, sender.selectedSegment))]
        MainActor.assumeIsolated { switcher.applySetting() }
    }

    @objc func prefToggleDockLock(_ sender: NSSwitch) {
        DockLock.isEnabled = sender.state == .on
        MainActor.assumeIsolated { DockLock.isEnabled ? dockLock.relock() : dockLock.apply() }
    }

    @objc func prefToggleSplitDivider(_ sender: NSSwitch) {
        SplitViewController.isEnabled = sender.state == .on
        MainActor.assumeIsolated { splitView.refresh() }
    }

    @objc func prefToggleDockClickHide(_ sender: NSSwitch) {
        DockClickHide.isEnabled = sender.state == .on
    }

    @objc func prefToggleDockSwipe(_ sender: NSSwitch) {
        DockSwipeController.isEnabled = sender.state == .on
        MainActor.assumeIsolated { DockSwipeController.shared.apply(owner: self) }
    }

    @objc func prefToggleMissionControlKeys(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state == .on, forKey: MissionControlKeys.defaultsKey)
        MainActor.assumeIsolated { missionControlKeys.applySetting() }
    }

    @objc func prefToggleWindowBrowserKeyboard(_ sender: NSSwitch) {
        WindowBrowserSettings.keyboardPanelEnabled = sender.state == .on
        notifyWindowBrowserSettingsChanged()
    }

    @objc func prefToggleWindowBrowserLive(_ sender: NSSwitch) {
        WindowBrowserSettings.livePreviewEnabled = sender.state == .on
        notifyWindowBrowserSettingsChanged()
    }

    @objc func prefChangeWindowBrowserAppearance(_ sender: NSSegmentedControl) {
        WindowBrowserAppearanceStyle.current = sender.selectedSegment == 1 ? .paper : .system
        notifyWindowBrowserSettingsChanged()
    }

    @objc func prefChangeWindowBrowserStyle(_ sender: NSSegmentedControl) {
        let styles = WindowBrowserSettings.PreferredStyle.allCases
        guard sender.selectedSegment >= 0, sender.selectedSegment < styles.count else { return }
        WindowBrowserSettings.preferredStyle = styles[sender.selectedSegment]
        notifyWindowBrowserSettingsChanged()
    }

    @objc func prefEditWindowBrowserExclusions() {
        let alert = NSAlert()
        alert.messageText = "按应用排除"
        alert.informativeText = "一行一个应用标识。这里列出的应用不会出现在窗口浏览面板里。"
        // 多行编辑必须用 NSTextView：单行 NSTextField 放不下“每行一个 bundle ID”。
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 340, height: 140))
        textView.isEditable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = WindowBrowserSettings.excludedBundleIDs.sorted().joined(separator: "\n")
        scroll.documentView = textView
        alert.accessoryView = scroll
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let ids = Set(textView.string
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        WindowBrowserSettings.excludedBundleIDs = ids
        notifyWindowBrowserSettingsChanged()
        refreshPreferencesWindowIfOpen()
    }

    private func notifyWindowBrowserSettingsChanged() {
        NotificationCenter.default.post(name: WindowBrowserNotification.didChangeSettings, object: nil)
    }

}

/// 设置里的“之前常用”：Windows / iPad / 一直用 Mac 三段，名字和欢迎窗口第二步一样；没答时一段都不选。
/// 自己盯着 SwitcherOrigin 的变化（欢迎窗口里点了、刘海问过之后他点了），设置页开着也跟着变。
final class SwitcherOriginControl: NSSegmentedControl {
    static func make() -> SwitcherOriginControl {
        let control = SwitcherOriginControl(labels: SwitcherOrigin.answers.compactMap(\.title),
                                            trackingMode: .selectOne, target: nil, action: nil)
        control.target = control
        control.action = #selector(picked)
        control.setAccessibilityLabel("之前常用")
        control.showCurrent()
        NotificationCenter.default.addObserver(control, selector: #selector(showCurrent),
                                               name: SwitcherOrigin.didChangeNotification, object: nil)
        return control
    }

    @objc private func picked() {
        guard SwitcherOrigin.answers.indices.contains(selectedSegment) else { return }
        SwitcherOrigin.current = SwitcherOrigin.answers[selectedSegment]
    }

    @objc private func showCurrent() {
        if let at = SwitcherOrigin.answers.firstIndex(of: SwitcherOrigin.current) {
            selectedSegment = at
        } else {
            for segment in 0..<segmentCount { setSelected(false, forSegment: segment) }
        }
    }
}

/// 快捷键记录器：只在设置页明确聚焦时读取键盘事件，不安装任何全局监听。
final class HotKeyRecorderView: NSControl {
    typealias HotKey = WindowBrowserSettings.HotKey
    var onCapture: ((HotKey?) -> Void)?
    /// 录到的组合不能用时返回原因（显示在标签里）；能用返回 nil。
    var validate: ((HotKey) -> String?)?
    private let label = NSTextField(labelWithString: "未设置")
    private let recordButton = NSButton(title: "录制…", target: nil, action: nil)
    private let clearButton = NSButton(title: "清除", target: nil, action: nil)
    private var current: HotKey?
    private var recording = false
    private var messageWork: DispatchWorkItem?

    init(accessibilityName: String) {
        super.init(frame: .zero)
        label.font = WindowBrowserTypography.monospacedDigits
        label.lineBreakMode = .byTruncatingTail
        for button in [recordButton, clearButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
        }
        recordButton.target = self
        recordButton.action = #selector(beginRecording)
        clearButton.target = self
        clearButton.action = #selector(clearHotKey)
        for view in [label, recordButton, clearButton] { addSubview(view) }
        widthAnchor.constraint(equalToConstant: 280).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(accessibilityName)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    func configure(current: HotKey?) {
        self.current = current
        messageWork?.cancel()
        showText(current.map { WindowBrowserSettings.displayName(for: $0) } ?? "未设置")
        clearButton.isEnabled = current != nil
    }

    private func showText(_ text: String) {
        label.stringValue = text
        label.toolTip = text
        setAccessibilityValue(text)
        needsLayout = true
    }

    /// 录到不能用的组合：提示音 + 标签里说明原因，1.8 秒后回到当前组合。
    private func reject(_ message: String) {
        shadeSounds.beep()
        showText(message)
        messageWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.configure(current: self.current)
        }
        messageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    override func layout() {
        super.layout()
        clearButton.frame = NSRect(x: bounds.width - 56, y: (bounds.height - 24) / 2,
                                   width: 56, height: 24)
        recordButton.frame = NSRect(x: bounds.width - 56 - 6 - 64,
                                    y: (bounds.height - 24) / 2, width: 64, height: 24)
        label.frame = NSRect(x: 0, y: (bounds.height - 16) / 2,
                             width: max(60, recordButton.frame.minX - 8), height: 16)
    }

    @objc private func beginRecording() {
        recording = true
        messageWork?.cancel()
        showText("请按快捷键…")
        window?.makeFirstResponder(self)
    }

    @objc private func clearHotKey() {
        recording = false
        onCapture?(nil)
    }

    override func resignFirstResponder() -> Bool {
        if recording {
            recording = false
            configure(current: current)
        }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            recording = false
            configure(current: current)
            return
        }
        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        capture(event)
        return true
    }

    private func capture(_ event: NSEvent) {
        // 只按修饰键不构成快捷键：保持录制状态，等真正的键。
        guard !WindowBrowserSettings.isModifierOnlyKeyCode(event.keyCode) else { return }
        recording = false
        let hotKey = HotKey(keyCode: UInt32(event.keyCode),
                            modifiers: Self.carbonModifiers(from: event.modifierFlags))
        if WindowBrowserSettings.isReserved(hotKey) {
            let hasControlOrOption = hotKey.modifiers & UInt32(controlKey | optionKey) != 0
            reject(hasControlOrOption ? "系统在用这个组合" : "组合里要有 ⌃ 或 ⌥")
            return
        }
        if let message = validate?(hotKey) {
            reject(message)
            return
        }
        onCapture?(hotKey)
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}
