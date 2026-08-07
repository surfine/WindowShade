// 偏好设置与引导页：设置窗口/引导页视图构建、权限引导状态刷新、
// 偏好开关动作。作为 AppDelegate 扩展实现。

import Cocoa
import ServiceManagement

private let prefCardWidth: CGFloat = 416
private let prefRowInset: CGFloat = 14
private let prefTrailingControlColumnWidth: CGFloat = 152

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

@objc func cancelPinnedPreviewMenuItem(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        pinnedPreviewController.stopPreviewFromMenu(id: CGWindowID(number.uint32Value))
        rebuildMenu()
    }

@objc func stopAllPinnedPreviewsAction() {
        pinnedPreviewController.stopAllPreviews(reason: "menu-stop-all")
        rebuildMenu()
    }

@objc func toggleSuspendPinnedPreviewsAction() {
        pinnedPreviewController.toggleSuspendAll()
        rebuildMenu()
    }

    func soundName(defaultsKey: String, fallback: String) -> String {
        let name = UserDefaults.standard.string(forKey: defaultsKey) ?? fallback
        return shadeSoundChoices.contains(where: { $0.name == name }) ? name : fallback
    }

    func playShadeSound(_ name: String) {
        guard soundEnabled else { return }
        let sound = NSSound(named: NSSound.Name(name))
        guard let sound else { return }
        sound.play()
    }

    func playFoldSound() {
        playShadeSound(soundName(defaultsKey: shadeFoldSoundDefaultsKey, fallback: shadeDefaultFoldSound))
    }

    func playUnfoldSound() {
        playShadeSound(soundName(defaultsKey: shadeUnfoldSoundDefaultsKey, fallback: shadeDefaultUnfoldSound))
    }

    func refreshPreferencesWindowIfOpen() {
        guard let window = preferencesWindow, window.isVisible else { return }
        window.contentView = makePreferencesContentView()
    }

    func quietNotice(_ message: String, log: String? = nil) {
        wlog(log ?? "notice: \(message)")
        statusNoticeWorkItem?.cancel()
        statusItem.button?.title = " \(message)"
        statusItem.button?.toolTip = message
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.statusNoticeWorkItem = nil
            self.rebuildMenu()
        }
        statusNoticeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

@objc func showPreferences() {
        if let window = preferencesWindow {
            window.contentView = makePreferencesContentView()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 700),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "WindowShade 偏好设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = makePreferencesContentView()
        preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func makePreferencesContentView() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 700))
        let stack = NSStackView(frame: root.bounds.insetBy(dx: 22, dy: 20))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.autoresizingMask = [.width, .height]
        root.addSubview(stack)

        func addGroup(_ title: String, _ card: NSView) {
            stack.addArrangedSubview(makePrefGroupLabel(title))
            stack.addArrangedSubview(card)
            stack.setCustomSpacing(16, after: card)
        }

        let general = makePrefCard([
            makePrefToggleRow(name: "双击标题栏以折叠", subtitle: titlebarDoubleClickPreferenceSubtitle(),
                              isOn: titlebarDoubleClickEnabled, action: #selector(prefToggleTitlebarDoubleClick(_:))),
            makePrefToggleRow(name: "卷帘条浮动于上方", subtitle: "折叠后的标题栏保持在其他窗口之上",
                              isOn: floatingOnTop, action: #selector(prefToggleFloating(_:))),
            makePrefToggleRow(name: "卷帘条半透明", subtitle: "略微降低卷帘条不透明度",
                              isOn: translucent, action: #selector(prefToggleTranslucent(_:))),
            makePrefToggleRow(name: "登录时自动启动", subtitle: launchAtLoginSubtitle(),
                              isOn: launchAtLoginEnabled(), action: #selector(prefToggleLaunchAtLogin(_:))),
        ])
        addGroup("通用", general)

        let appearanceSeg = NSSegmentedControl(labels: ["原貌卷帘", "标准标题栏"],
                                               trackingMode: .selectOne,
                                               target: self,
                                               action: #selector(prefSelectAppearanceSegment(_:)))
        appearanceSeg.selectedSegment = appearanceMode == .proxyTitleBar ? 1 : 0
        appearanceSeg.sizeToFit()
        addGroup("外观", makePrefCard([
            makePrefControlRow(name: "卷帘样式", subtitle: "标准标题栏带原生红绿灯与材质", control: appearanceSeg),
        ]))

        addGroup("声音", makePrefCard([
            makePrefToggleRow(name: "启用折叠 / 展开音效", subtitle: nil,
                              isOn: soundEnabled, action: #selector(prefToggleSound(_:))),
            makePrefControlRow(name: "折叠音效", subtitle: nil,
                               control: makeSoundPopup(selected: foldSoundName, action: #selector(prefSelectFoldSound(_:)))),
            makePrefControlRow(name: "展开音效", subtitle: nil,
                               control: makeSoundPopup(selected: unfoldSoundName, action: #selector(prefSelectUnfoldSound(_:)))),
        ]))

        addGroup("权限", makePrefCard([
            makePermissionRow(kind: .preferences, width: prefCardWidth, symbol: "accessibility", name: "辅助功能", subtitle: "读取、移动与恢复窗口",
                              granted: hasAccessibilityPermission(), action: #selector(openAccessibilitySettingsAction)),
            makePermissionRow(kind: .preferences, width: prefCardWidth, symbol: "rectangle.inset.filled.and.person.filled", name: "屏幕录制", subtitle: "截取真实标题栏与窗口预览",
                              granted: hasScreenRecordingPermission(), action: #selector(openScreenRecordingSettingsAction)),
        ]))

        return root
    }

    func makePrefGroupLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.textColor = .tertiaryLabelColor
        return field
    }

    func makePrefCard(_ rows: [NSView]) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: prefCardWidth).isActive = true

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 0
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            inner.topAnchor.constraint(equalTo: card.topAnchor),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        for (i, row) in rows.enumerated() {
            if i > 0 {
                let sep = NSBox()
                sep.boxType = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                inner.addArrangedSubview(sep)
                sep.widthAnchor.constraint(equalToConstant: prefCardWidth).isActive = true
            }
            inner.addArrangedSubview(row)
        }
        return card
    }

    func makePrefRow(height: CGFloat) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: prefCardWidth, height: height))
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: prefCardWidth).isActive = true
        row.heightAnchor.constraint(equalToConstant: height).isActive = true
        return row
    }

    func makePrefName(_ text: String, y: CGFloat) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 13)
        let width = prefCardWidth - (prefRowInset * 2) - prefTrailingControlColumnWidth - 12
        field.frame = NSRect(x: prefRowInset, y: y, width: width, height: 18)
        return field
    }

    func makePrefSubtitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = .tertiaryLabelColor
        let width = prefCardWidth - (prefRowInset * 2) - prefTrailingControlColumnWidth - 12
        field.frame = NSRect(x: prefRowInset, y: 9, width: width, height: 15)
        return field
    }

    func makePrefToggleRow(name: String, subtitle: String?, isOn: Bool, action: Selector) -> NSView {
        let h: CGFloat = subtitle == nil ? 42 : 54
        let row = makePrefRow(height: h)
        row.addSubview(makePrefName(name, y: subtitle == nil ? (h - 18) / 2 : h - 14 - 18))
        if let subtitle = subtitle { row.addSubview(makePrefSubtitle(subtitle)) }
        let sw = NSSwitch()
        sw.state = isOn ? .on : .off
        sw.target = self
        sw.action = action
        sw.sizeToFit()
        let swW = sw.frame.width
        let swH = sw.frame.height
        sw.frame = NSRect(x: prefCardWidth - prefRowInset - swW, y: floor((h - swH) / 2), width: swW, height: swH)
        sw.autoresizingMask = [.minXMargin]
        row.addSubview(sw)
        return row
    }

    func makePrefControlRow(name: String, subtitle: String?, control: NSControl) -> NSView {
        let h: CGFloat = subtitle == nil ? 44 : 54
        let row = makePrefRow(height: h)
        row.addSubview(makePrefName(name, y: subtitle == nil ? (h - 18) / 2 : h - 14 - 18))
        if let subtitle = subtitle { row.addSubview(makePrefSubtitle(subtitle)) }
        control.sizeToFit()
        let cw = control.frame.width
        let ch = control.frame.height
        control.frame = NSRect(x: prefCardWidth - prefRowInset - cw, y: floor((h - ch) / 2), width: cw, height: ch)
        control.autoresizingMask = [.minXMargin]
        row.addSubview(control)
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
        if let triple = systemTitlebarTripleClickDescription() {
            return "双击标题栏卷起；\(triple)"
        }
        return "在任意窗口标题栏双击即可卷起"
    }

    func makePrefButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
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

    @objc func prefToggleFloating(_ sender: NSSwitch) {
        floatingOnTop = sender.state == .on
        UserDefaults.standard.set(floatingOnTop, forKey: shadeFloatingOnTopDefaultsKey)
        refreshOverlayPresentation(bringForward: floatingOnTop)
        rebuildMenu()
    }

    @objc func prefToggleTranslucent(_ sender: NSSwitch) {
        translucent = sender.state == .on
        UserDefaults.standard.set(translucent, forKey: shadeTranslucentDefaultsKey)
        refreshOverlayPresentation()
        rebuildMenu()
    }

    @objc func prefSelectAppearanceSegment(_ sender: NSSegmentedControl) {
        setAppearanceMode(sender.selectedSegment == 1 ? .proxyTitleBar : .nativeScreenshot)
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
        showPermissionOnboardingIfNeeded(force: true)
    }

    func showPermissionOnboardingIfNeeded(force: Bool) {
        let missing = !hasAccessibilityPermission() || !hasScreenRecordingPermission()
        let shouldShowFirstRun = !UserDefaults.standard.bool(forKey: shadeOnboardingShownDefaultsKey)
        guard missing || shouldShowFirstRun || force else { return }
        if !force && UserDefaults.standard.bool(forKey: shadeOnboardingShownDefaultsKey) { return }
        showPermissionOnboarding()
    }

    func showPermissionOnboarding() {
        if let window = onboardingWindow {
            window.contentView = makeOnboardingContentView()
            window.setContentSize(window.contentView?.frame.size ?? window.frame.size)
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let content = makeOnboardingContentView()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: content.frame.size),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "欢迎使用 WindowShade"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = content
        onboardingWindow = window
        refreshOnboardingState()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        onboardingRefreshTimer?.invalidate()
        if onboardingPermissionStack != nil {
            onboardingRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                guard let window = self.onboardingWindow, window.isVisible else {
                    timer.invalidate()
                    self.onboardingRefreshTimer = nil
                    return
                }
                self.refreshOnboardingState()
            }
        } else {
            onboardingRefreshTimer = nil
        }
    }

    func makeOnboardingContentView() -> NSView {
        onboardingPermissionStack = nil
        onboardingProgressLabel = nil
        onboardingDoneButton = nil
        onboardingCaption = nil

        let needsPermissions = !hasAccessibilityPermission() || !hasScreenRecordingPermission()
        let height: CGFloat = needsPermissions ? 615 : 595
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: height))
        let stack = NSStackView(frame: root.bounds.insetBy(dx: 24, dy: 22))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.autoresizingMask = [.width, .height]
        root.addSubview(stack)

        // Header: app icon + title
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        header.addArrangedSubview(makeOnboardingAppIconView(size: 40))
        let title = NSTextField(labelWithString: "把窗口原地卷起来")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        header.addArrangedSubview(title)
        stack.addArrangedSubview(header)

        let copy = NSTextField(labelWithString: "WindowShade 让窗口多两种临时状态：折叠——内容原地收起，只留标题栏入口，可从原地标题栏、菜单栏或专注 shelf 找回；置顶——让窗口的实时画面始终浮在最上方，边看边操作（如 iPhone 镜像）。都是可逆的，不影响原来的布局。")
        copy.font = .systemFont(ofSize: 13)
        copy.textColor = .secondaryLabelColor
        copy.lineBreakMode = .byWordWrapping
        copy.maximumNumberOfLines = 6
        copy.preferredMaxLayoutWidth = onboardingContentWidth
        stack.addArrangedSubview(copy)

        stack.addArrangedSubview(makeOnboardingUsageCard())
        if !needsPermissions {
            stack.addArrangedSubview(makeOnboardingFeatureCard())
        }

        if needsPermissions {
            let permissionCopy = NSTextField(labelWithString: "WindowShade 需要这些权限来读取、移动和恢复窗口，并截取真实标题栏与窗口预览。")
            permissionCopy.font = .systemFont(ofSize: 12)
            permissionCopy.textColor = .tertiaryLabelColor
            permissionCopy.lineBreakMode = .byWordWrapping
            permissionCopy.maximumNumberOfLines = 3
            permissionCopy.preferredMaxLayoutWidth = onboardingContentWidth
            stack.addArrangedSubview(permissionCopy)

            let progress = NSTextField(labelWithString: "")
            progress.font = .systemFont(ofSize: 13, weight: .medium)
            stack.addArrangedSubview(progress)
            onboardingProgressLabel = progress

            let permissionStack = NSStackView()
            permissionStack.orientation = .vertical
            permissionStack.alignment = .leading
            permissionStack.spacing = 10
            stack.addArrangedSubview(permissionStack)
            onboardingPermissionStack = permissionStack
        }

        if needsPermissions {
            let buttonRow = NSStackView()
            buttonRow.orientation = .horizontal
            buttonRow.spacing = 10
            let later = NSButton(title: "稍后再说", target: self, action: #selector(dismissOnboarding))
            later.bezelStyle = .rounded
            buttonRow.addArrangedSubview(later)
            let done = NSButton(title: "完成设置", target: self, action: #selector(finishOnboarding))
            done.bezelStyle = .rounded
            done.keyEquivalent = "\r"
            buttonRow.addArrangedSubview(done)
            buttonRow.widthAnchor.constraint(equalToConstant: onboardingContentWidth).isActive = true
            stack.addArrangedSubview(buttonRow)
            onboardingDoneButton = done

            let caption = NSTextField(labelWithString: "授权全部权限后即可完成设置")
            caption.font = .systemFont(ofSize: 11)
            caption.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(caption)
            onboardingCaption = caption
        }

        return root
    }

    func onboardingSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSImageView? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let view = NSImageView()
        view.image = image.withSymbolConfiguration(config)
        view.contentTintColor = color
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    func makeOnboardingAppIconView(size: CGFloat) -> NSImageView {
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        let baseImage = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: size, height: size))
        let image = baseImage.copy() as? NSImage ?? baseImage
        image.size = NSSize(width: size, height: size)
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        return view
    }

    func makeOnboardingUsageCard() -> NSView {
        var rows: [(String, String)] = [
            ("cursorarrow.click", "双击标题栏：折叠或展开当前窗口"),
            ("eye", "单击卷帘条：显示 / 收回窗口内容预览"),
            ("keyboard", "⌃⌘C：折叠 / 展开当前窗口（同一键来回切换）"),
            ("pin", "⌃⌘P：置顶 / 取消置顶当前窗口（同一键来回切换）"),
            ("number", "⌃⌘1…9：按菜单顺序快速展开已折叠窗口"),
            ("menubar.rectangle", "菜单栏：管理已折叠与已置顶窗口，可逐个或全部恢复"),
        ]
        if let triple = systemTitlebarTripleClickDescription() {
            rows.insert(("cursorarrow.rays", triple), at: 1)
        }
        return makeOnboardingInfoCard(title: "常用入口", rows: rows)
    }

    func makeOnboardingFeatureCard() -> NSView {
        let rows: [(String, String)] = [
            ("rectangle.on.rectangle", "置顶：把窗口的实时画面浮在最上方，鼠标移入即可操作真实窗口"),
            ("rectangle.stack", "专注模式会把其他 app 收进顶部 shelf"),
            ("arrow.down.forward.and.arrow.up.backward", "从 shelf 拉出窗口，双击可按当前位置展开"),
            ("paintpalette", "可在偏好设置切换原貌卷帘 / 标准标题栏"),
            ("power", "可开启登录时自动启动，让 WindowShade 常驻"),
        ]
        return makeOnboardingInfoCard(title: "工作方式", rows: rows)
    }

    func makeOnboardingInfoCard(title: String, rows: [(String, String)]) -> NSView {
        let titleH: CGFloat = 22
        let rowH: CGFloat = 24
        let height = 14 + titleH + CGFloat(rows.count) * rowH + 10
        let card = NSView(frame: NSRect(x: 0, y: 0, width: onboardingContentWidth, height: height))
        card.wantsLayer = true
        card.layer?.cornerRadius = 8
        card.layer?.backgroundColor = NSColor.unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.5).cgColor
        card.widthAnchor.constraint(equalToConstant: onboardingContentWidth).isActive = true
        card.heightAnchor.constraint(equalToConstant: height).isActive = true

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 12, weight: .medium)
        heading.textColor = .tertiaryLabelColor
        heading.frame = NSRect(x: 14, y: height - 14 - 16, width: 200, height: 16)
        card.addSubview(heading)

        var y = height - 14 - titleH - 18
        for (symbol, text) in rows {
            if let icon = onboardingSymbol(symbol, pointSize: 12, color: .tertiaryLabelColor) {
                icon.frame = NSRect(x: 14, y: y, width: 16, height: 16)
                card.addSubview(icon)
            }
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 38, y: y - 1, width: onboardingContentWidth - 52, height: 18)
            card.addSubview(label)
            y -= rowH
        }
        return card
    }

    enum PermissionRowKind { case onboarding, preferences }

    // Shared permission row. `.onboarding` draws an emphasized standalone card
    // (yellow tint + 去授权 button when pending); `.preferences` is a borderless
    // row inside a grouped card (status text + 打开设置 link).
    func makePermissionRow(kind: PermissionRowKind, width: CGFloat, symbol: String,
                                   name: String, subtitle: String, granted: Bool, action: Selector) -> NSView {
        let isOnboarding = kind == .onboarding
        let height: CGFloat = isOnboarding ? 58 : 56
        let row = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        row.heightAnchor.constraint(equalToConstant: height).isActive = true

        if isOnboarding {
            row.wantsLayer = true
            row.layer?.cornerRadius = 8
            row.layer?.borderWidth = granted ? 0.5 : 1
            if granted {
                row.layer?.backgroundColor = NSColor.clear.cgColor
                row.layer?.borderColor = NSColor.separatorColor.cgColor
            } else {
                row.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.12).cgColor
                row.layer?.borderColor = NSColor.systemYellow.withAlphaComponent(0.55).cgColor
            }
        }

        // Leading: icon + name + subtitle
        let iconColor: NSColor = (isOnboarding && !granted) ? .systemBrown : .secondaryLabelColor
        let iconBox: CGFloat = isOnboarding ? 22 : 20
        let iconX: CGFloat = isOnboarding ? 16 : 14
        let textX: CGFloat = isOnboarding ? 50 : 44
        if let icon = onboardingSymbol(symbol, pointSize: isOnboarding ? 18 : 17, color: iconColor) {
            icon.frame = NSRect(x: iconX, y: (height - iconBox) / 2, width: iconBox, height: iconBox)
            row.addSubview(icon)
        }
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 13, weight: isOnboarding ? .medium : .regular)
        nameLabel.frame = NSRect(x: textX, y: isOnboarding ? 30 : height - 13 - 18, width: 240, height: 18)
        row.addSubview(nameLabel)
        let sub = NSTextField(labelWithString: subtitle)
        sub.font = .systemFont(ofSize: isOnboarding ? 12 : 11)
        sub.textColor = isOnboarding ? .secondaryLabelColor : .tertiaryLabelColor
        sub.frame = NSRect(x: textX, y: 10, width: isOnboarding ? 240 : 230, height: isOnboarding ? 16 : 15)
        row.addSubview(sub)

        // Trailing
        switch kind {
        case .onboarding where granted:
            let status = NSTextField(labelWithString: "已授权")
            status.font = .systemFont(ofSize: 12, weight: .medium)
            status.textColor = .systemGreen
            status.alignment = .right
            status.frame = NSRect(x: width - 92, y: (height - 16) / 2, width: 60, height: 16)
            row.addSubview(status)
            if let check = onboardingSymbol("checkmark.circle.fill", pointSize: 13, color: .systemGreen) {
                check.frame = NSRect(x: width - 92 - 20, y: (height - 16) / 2, width: 16, height: 16)
                row.addSubview(check)
            }
        case .onboarding:
            let button = NSButton(title: "去授权", target: self, action: action)
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.bezelColor = .systemYellow
            button.sizeToFit()
            let bw = max(button.frame.width, 64)
            button.frame = NSRect(x: width - 16 - bw, y: (height - button.frame.height) / 2, width: bw, height: button.frame.height)
            row.addSubview(button)
        case .preferences:
            let link = NSButton(title: "打开设置", target: self, action: action)
            link.isBordered = false
            link.font = .systemFont(ofSize: 12)
            link.attributedTitle = NSAttributedString(string: "打开设置",
                attributes: [.foregroundColor: NSColor.controlAccentColor, .font: NSFont.systemFont(ofSize: 12)])
            link.sizeToFit()
            let lw = link.frame.width
            link.frame = NSRect(x: width - 14 - lw, y: (height - link.frame.height) / 2, width: lw, height: link.frame.height)
            link.autoresizingMask = [.minXMargin]
            row.addSubview(link)

            let statusColor: NSColor = granted ? .systemGreen : .systemOrange
            let status = NSTextField(labelWithString: granted ? "已授权" : "未授权")
            status.font = .systemFont(ofSize: 12, weight: .medium)
            status.textColor = statusColor
            status.sizeToFit()
            let sw = status.frame.width
            status.frame = NSRect(x: link.frame.minX - 12 - sw, y: (height - 16) / 2, width: sw, height: 16)
            status.autoresizingMask = [.minXMargin]
            row.addSubview(status)
            if let dot = onboardingSymbol(granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill", pointSize: 12, color: statusColor) {
                dot.frame = NSRect(x: status.frame.minX - 17, y: (height - 15) / 2, width: 15, height: 15)
                dot.autoresizingMask = [.minXMargin]
                row.addSubview(dot)
            }
        }
        return row
    }

    func refreshOnboardingState() {
        guard let permissionStack = onboardingPermissionStack else { return }
        let ax = hasAccessibilityPermission()
        let screen = hasScreenRecordingPermission()

        permissionStack.arrangedSubviews.forEach {
            permissionStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        permissionStack.addArrangedSubview(makePermissionRow(
            kind: .onboarding,
            width: onboardingContentWidth,
            symbol: "accessibility",
            name: "辅助功能",
            subtitle: "读取、移动与恢复窗口",
            granted: ax,
            action: #selector(openAccessibilitySettingsAction)))
        permissionStack.addArrangedSubview(makePermissionRow(
            kind: .onboarding,
            width: onboardingContentWidth,
            symbol: "rectangle.inset.filled.and.person.filled",
            name: "屏幕录制",
            subtitle: "截取真实标题栏与预览",
            granted: screen,
            action: #selector(openScreenRecordingSettingsAction)))

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
    }
    @objc func toggleFloatingOnTop(_ sender: NSMenuItem) {
        floatingOnTop.toggle()
        UserDefaults.standard.set(floatingOnTop, forKey: shadeFloatingOnTopDefaultsKey)
        refreshOverlayPresentation(bringForward: floatingOnTop)
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
    }

    @objc func toggleTranslucent(_ sender: NSMenuItem) {
        translucent.toggle()
        UserDefaults.standard.set(translucent, forKey: shadeTranslucentDefaultsKey)
        refreshOverlayPresentation()
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
    }

}
