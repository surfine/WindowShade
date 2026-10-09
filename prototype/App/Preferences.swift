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
        MainActor.assumeIsolated { _ = gestures.magicTile() }
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
        statusItem?.button?.title = " \(PaperSurfaceAccessibility.statusItemNoticeTitle(message))"
        statusItem?.button?.toolTip = message
        statusItem?.button?.setAccessibilityValue(message)
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
        _ = title
        return WS2SettingsCopy.content(name: nil, subtitle: subtitle, symbol: WS2SettingsCopy.tableSymbol(symbolName)).view
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
            makeUnifiedToggleRow(name: "回来时说一下离开期间的事", subtitle: "锁屏或睡眠时有变化才说",
                                 isOn: AwaySummaryController.isEnabled, action: #selector(prefToggleAwaySummary(_:))),
            makeUnifiedToggleRow(name: "实时活动", subtitle: "在刘海和启动台负一屏查看音乐、耳机、隔空投送与路线",
                                 isOn: NotchActivityController.isEnabled, action: #selector(prefToggleActivities(_:))),
            // 正在播放默认开（NP-4）：关了，刘海上不再显示歌，也不再长出大卡。
            makeUnifiedToggleRow(name: "正在播放", subtitle: "歌名和封面显示在刘海上",
                                 isOn: NotchNowPlayingDefaults.musicEnabled(in: .standard), action: #selector(prefToggleNowPlaying(_:))),
            // 跟着声音跳（NP-6）：默认关；打开时系统才问“系统音频录制”。拒绝过的，副标题写原因，再打开带去系统设置。
            makeUnifiedToggleRow(name: "跟着声音跳", subtitle: followSoundSubtitle(),
                                 isOn: AudioLevelController.isEnabled, action: #selector(prefToggleFollowSound(_:))),
            // 番茄钟的设置属于“实时活动”这一栏（R09：从「专注与输入」挪过来）。
            MainActor.assumeIsolated { WS2FocusSettingsRows(runtime: ws2Runtime) },
            makeUnifiedToggleRow(name: "计时器到时间响一声", subtitle: "响一次系统提示音，不循环；系统静音时不响",
                                 isOn: CountdownTimerSettings.chimeEnabled, action: #selector(prefToggleTimerChime(_:))),
            // 日程：开关加提前量（CAL-4）。没有权限时副标题这么写，点一下去系统设置。
            makeCalendarSettingsRow(),
            makeUnifiedToggleRow(name: "浏览器下载", subtitle: "读取「下载」文件夹，看有没有没下完的文件",
                                 isOn: DownloadActivitySource.isEnabled, action: #selector(prefToggleDownloads(_:))),
            // 音量和亮度：开关默认开；没允许辅助功能时副标题改说系统的提示也会出现，并带“允许…”。
            LevelRowHost { [weak self] in self?.makeLevelKeysRow() ?? NSView() },
            makeUnifiedToggleRow(name: "合成一排", subtitle: "窗口和正在进行的事排在同一排",
                                 isOn: NotchController.mergedRowEnabled, action: #selector(prefToggleMergedRow(_:))),
            makeUnifiedToggleRow(name: WSL10n.text("settings.hoverGuard.name", zh: "悬停不误触"),
                                 subtitle: WSL10n.text("settings.hoverGuard.sub", zh: "指针在刘海上停一下才展开，路过不展开"),
                                 isOn: NotchController.hoverGuardEnabled, action: #selector(prefToggleHoverGuard(_:))),
            makeUnifiedToggleRow(name: "文件架", subtitle: "拖到刘海暂存的文件放在这里；关掉后清空",
                                 isOn: FileShelf.enabled, action: #selector(prefToggleFileShelf(_:))),
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
        let centeringPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        centeringPopup.addItems(withTitles: Self.centeringTitles)
        centeringPopup.selectItem(at: ScrollStrip.Centering.allCases.firstIndex(of: ScrollStrip.storedCentering().mode) ?? 0)
        centeringPopup.target = self
        centeringPopup.action = #selector(prefSelectCentering(_:))
        let arrangeCard = makeUnifiedSettingsCard([
            makeUnifiedControlRow(name: "窗口之间留缝",
                                  subtitle: "半屏、四角、网格、魔法平铺、卷轴排好的窗口之间和屏幕边留一道缝",
                                  control: gapSeg),
            makeUnifiedToggleRow(name: "分屏把手",
                                 subtitle: "两扇窗口拼满一块屏时，中间出现一根小竖条：拖它两扇一起变，推到屏幕边那一扇进侧拉",
                                 isOn: SplitViewController.isEnabled, action: #selector(prefToggleSplitDivider(_:))),
            makeUnifiedToggleRow(name: "拖到窗口上并排", subtitle: "把窗口拖到另一扇上，两扇并排",
                                 isOn: TrackpadGestureController.dropSplitEnabled, action: #selector(prefToggleDropSplit(_:))),
            makeUnifiedControlRow(name: "走到一列时", subtitle: "贴边：挪得最少。居中：永远在正中",
                                  control: centeringPopup),
            makeUnifiedToggleRow(name: "放得下就居中", subtitle: "列加起来不到一屏时，整组放在正中",
                                 isOn: ScrollStrip.storedCentering().whenFits, action: #selector(prefToggleCenterWhenFits(_:))),
            makeUnifiedToggleRow(name: WSL10n.text("settings.stripWidths.name", zh: "记住每个 App 的列宽"),
                                 subtitle: WSL10n.text("settings.stripWidths.sub", zh: "改过宽度的 App，下次开在卷轴里还是那个宽度"),
                                 isOn: StripWidthMemory.isEnabled(), action: #selector(prefToggleStripWidths(_:))),
            makeUnifiedToggleRow(name: WSL10n.text("settings.stripTitleDrag.name", zh: "拖标题栏换位置"),
                                 subtitle: WSL10n.text("settings.stripTitleDrag.sub", zh: "在卷轴里拖标题栏换列；拉远一点才离开卷轴"),
                                 isOn: StripTitleDrag.isEnabled(), action: #selector(prefToggleStripTitleDrag(_:))),
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
        stack.setCustomSpacing(18, after: sound)

        // 实验：两项都默认关，开关只管自己那一个键。
        stack.addArrangedSubview(makePrefGroupLabel("实验"))
        let experiments = makeUnifiedSettingsCard([
            makeUnifiedToggleRow(name: "拷贝进度", subtitle: "Finder 拷贝时在刘海上显示拷到哪了",
                                 isOn: CopyProgressSource.isEnabled, action: #selector(prefToggleCopyProgress(_:))),
            makeUnifiedToggleRow(name: "猜你从哪来", subtitle: "按出别的系统的习惯时问一次",
                                 isOn: OriginGuess.isEnabled(in: .standard), action: #selector(prefToggleOriginGuess(_:))),
        ])
        stack.addArrangedSubview(experiments)
        experiments.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return root
    }

    /// 隐私一栏（原「权限与启动」）：先摊开读到的每一样（内容从 tools/privacy/registry.json 生成），
    /// 再把两项系统授权、登录时启动和更新并进同一页——开关全都还是原来那一个，不复制。
    /// 页头只保留第一句；“除了检查更新，都不离开这台 Mac”要等联网实测核过再开（WS2PrivacyCopy.showsNetworkPromise）。
    func makePermissionsSettingsPage() -> NSView {
        let (root, stack) = makeSettingsPageRoot()
        stack.addArrangedSubview(makeSettingsHeader(
            title: "隐私", subtitle: WS2PrivacyCopy.headerSubtitle(), symbolName: "lock.shield"))
        let pane = MainActor.assumeIsolated { WS2PrivacyPane(owner: self) }
        stack.addArrangedSubview(pane)
        pane.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: pane)
        stack.addArrangedSubview(makePrefGroupLabel("私人窗口"))
        let bystanderRow = BystanderRowHost { [weak self] in self?.makeBystanderToggleRow() ?? NSView() }
        let cover = makeUnifiedSettingsCard([
            bystanderRow,
            makeUnifiedControlRow(name: PrivateAppListPanel.rowTitle, subtitle: PrivateAppListPanel.rowSubtitle,
                                  control: NSButton(title: "管理…", target: self, action: #selector(prefOpenPrivateApps(_:)))),
        ])
        stack.addArrangedSubview(cover)
        cover.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: cover)
        stack.addArrangedSubview(makePrefGroupLabel("权限"))
        let permissions = makeUnifiedSettingsCard([
            makeUnifiedPermissionRow(symbol: "accessibility", name: "辅助功能",
                                     subtitle: "找到、移动和恢复窗口",
                                     granted: hasAccessibilityPermission(), action: #selector(openAccessibilitySettingsAction)),
            makeUnifiedPermissionRow(symbol: "rectangle.inset.filled.and.person.filled",
                                     name: "屏幕录制", subtitle: "截取窗口画面做预览",
                                     granted: hasScreenRecordingPermission(), action: #selector(openScreenRecordingSettingsAction)),
        ])
        stack.addArrangedSubview(permissions)
        permissions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(makePrefGroupLabel("锁屏"))
        let presence = makeUnifiedSettingsCard([makePresenceLockRow()])
        stack.addArrangedSubview(presence)
        presence.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: presence)
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

    /// 离开就锁（默认关）。还认不出手机时开关灰着；已经打开的仍能关掉。
    private func makePresenceLockRow() -> NSView {
        let on = PresenceLockDriver.isEnabled
        let usable = PresenceLockDriver.sourceAvailable
        let row = makeUnifiedToggleRow(name: "离开就锁",
                                       subtitle: usable ? "手机走远了，倒数 10 秒后锁屏" : "还认不出你的手机，先不能用",
                                       isOn: on, action: #selector(prefTogglePresenceLock(_:)))
        (row as? NSStackView)?.arrangedSubviews.compactMap { $0 as? NSSwitch }.first?.isEnabled = usable || on
        return row
    }

    @objc func prefOpenPrivateApps(_ sender: NSButton) {
        MainActor.assumeIsolated { PrivateAppListPanel.present(from: sender.window) }
    }

    /// 关掉直接关；打开前先看一页风险说明（PresenceLockRiskSheet），按「打开」才打开。
    @objc func prefTogglePresenceLock(_ sender: NSSwitch) {
        guard sender.state == .on, !PresenceLockDriver.isEnabled else {
            PresenceLockDriver.isEnabled = sender.state == .on
            return
        }
        sender.state = .off
        MainActor.assumeIsolated {
            PresenceLockRiskSheet.present(from: sender.window) { [weak sender] accepted in
                guard accepted else { return }
                PresenceLockDriver.isEnabled = true
                sender?.state = .on
            }
        }
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
        ])
    }

    private func makeUnifiedLabels(name: String, subtitle: String?, symbol: String? = nil) -> NSStackView {
        WS2SettingsCopy.content(name: name, subtitle: subtitle, symbol: symbol ?? WS2SettingsCopy.symbol(for: name)).view
    }

    /// “有人在看时收起私人窗口”：名单变了由 BystanderRowHost 重画这一行。
    fileprivate func makeBystanderToggleRow() -> NSView {
        let isOn = BystanderCameraPick.isEnabled
        let shown = BystanderTuckRow.presentation(isOn: isOn, listEmpty: PrivateAppList.shared.isEmpty)
        let row = makeUnifiedToggleRow(name: BystanderTuckRow.title, subtitle: shown.subtitle, isOn: isOn,
                                       enabled: shown.enabled, action: #selector(prefToggleBystanderCover(_:)))
        row.toolTip = shown.toolTip
        return row
    }

    /// “音量和亮度”这一行：符号、名字、副标题、ⓘ；没允许辅助功能时多一个“允许…”；右边是开关（默认开）。
    /// 副标题与按钮的写法归 NotchLevelSettingRow；辅助功能或开关变了由 LevelRowHost 重画。
    fileprivate func makeLevelKeysRow() -> NSView {
        let shown = NotchLevelSettingRow.make(accessibilityTrusted: hasAccessibilityPermission(),
                                              versionVerified: MainActor.assumeIsolated { NotchLevelObserver.currentVersionVerified() })
        let toggle = NSSwitch()
        toggle.state = NotchLevelSetting.isEnabled() ? .on : .off
        toggle.target = self
        toggle.action = #selector(prefToggleLevelKeys(_:))
        toggle.setAccessibilityLabel(NotchLevelSettingRow.title)
        toggle.controlSize = .regular
        let labels = WS2SettingsCopy.content(name: NotchLevelSettingRow.title, subtitle: shown.subtitle,
                                             symbol: NotchLevelSettingRow.symbol).view
        labels.addArrangedSubview(WS2SettingsInfoButton(text: shown.info, name: NotchLevelSettingRow.title))
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var trailing: [NSView] = []
        if let title = shown.allowButton {
            let allow = NSButton(title: title, target: self, action: #selector(prefAllowLevelKeys(_:)))
            allow.bezelStyle = .rounded
            allow.controlSize = .small
            allow.setAccessibilityLabel("允许辅助功能，让\(NotchLevelSettingRow.title)生效")
            allow.setContentHuggingPriority(.required, for: .horizontal)
            trailing.append(allow)
        }
        trailing.append(toggle)
        let row = NSStackView(views: [labels] + trailing)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        return row
    }

    @objc func prefToggleLevelKeys(_ sender: NSSwitch) {
        NotchLevelSetting.setEnabled(sender.state == .on)
        NotificationCenter.default.post(name: NotchLevelSetting.didChange, object: nil)
    }

    /// 调系统的辅助功能询问并打开“隐私与安全性 › 辅助功能”；之后设置窗口在前台时每 1 秒看一次，允许了就装监听。
    @objc func prefAllowLevelKeys(_ sender: NSButton) {
        _ = ensureAccessibility()
        openAccessibilityPrivacySettings()
        MainActor.assumeIsolated { LevelAllowWatcher.shared.start(window: sender.window) }
    }

    private func makeUnifiedToggleRow(name: String, subtitle: String?, isOn: Bool,
                                      enabled: Bool = true, action: Selector) -> NSView {
        let toggle = NSSwitch()
        toggle.state = isOn ? .on : .off
        toggle.isEnabled = enabled
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

    private func makeUnifiedControlRow(name: String, subtitle: String?, control: NSView) -> NSView {
        (control as? NSControl)?.sizeToFit()
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
        let labels = makeUnifiedLabels(name: name, subtitle: subtitle, symbol: symbol)
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
        let row = NSStackView(views: [labels, trailing])
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: row.leadingAnchor),
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
    @objc func prefToggleNowPlaying(_ sender: NSSwitch) {
        MainActor.assumeIsolated { notch.activities.setMusicEnabled(sender.state == .on) }
    }
    @objc func prefToggleFollowSound(_ sender: NSSwitch) {
        MainActor.assumeIsolated { notch.setFollowSound(sender.state == .on) }
    }
    /// “跟着声音跳”的副标题：开着但系统拒绝过时说原因；其余说它做什么。
    fileprivate func followSoundSubtitle() -> String {
        AudioLevelController.isEnabled && AudioCaptureAccess.current() == .denied
            ? "没有允许系统音频录制" : "刘海右边的小点随歌起伏"
    }
    @objc func prefToggleTimerChime(_ sender: NSSwitch) {
        CountdownTimerSettings.chimeEnabled = sender.state == .on
    }

    // MARK: 日程（CAL-3、CAL-4）

    /// 设置里“日程”一行：符号 + 名字 + 一行副标题，右边提前量和开关。没有权限时开关关着，副标题写原因，点一下去系统设置。
    fileprivate func makeCalendarSettingsRow() -> NSView {
        let access = CalendarSource.access()
        let toggle = NSSwitch()
        toggle.state = CalendarSettingsPolicy.sourceShouldRun(switchOn: CalendarSettings.enabled, access: access) ? .on : .off
        toggle.target = self
        toggle.action = #selector(prefToggleCalendar(_:))
        toggle.setAccessibilityLabel(CalendarWords.name)
        toggle.controlSize = .regular
        let lead = NSPopUpButton(frame: .zero, pullsDown: false)
        for choice in CalendarSettingsPolicy.leadChoices {
            lead.addItem(withTitle: CalendarSettingsPolicy.leadTitle(choice))
            lead.lastItem?.tag = choice.rawValue
        }
        lead.selectItem(withTag: CalendarSettings.lead.rawValue)
        lead.controlSize = .small
        lead.target = self
        lead.action = #selector(prefSelectCalendarLead(_:))
        lead.isEnabled = access.canRead
        lead.setAccessibilityLabel("日程提前量")
        let controls = NSStackView(views: [lead, toggle])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 10
        controls.setContentHuggingPriority(.required, for: .horizontal)
        controls.setContentCompressionResistancePriority(.required, for: .horizontal)
        let labels = makeUnifiedLabels(name: CalendarWords.name, subtitle: CalendarSettingsPolicy.subtitle(access: access),
                                       symbol: "calendar")
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if access == .denied {
            labels.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openCalendarSettingsAction)))
            labels.toolTip = "打开系统设置"
        }
        let row = NSStackView(views: [labels, controls])
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labels.trailingAnchor.constraint(equalTo: controls.leadingAnchor, constant: -14),
            controls.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -8),
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        return row
    }

    @objc func prefToggleCalendar(_ sender: NSSwitch) {
        let access = CalendarSource.access()
        switch CalendarSettingsPolicy.toggle(on: sender.state == .on, access: access) {
        case .disable:
            CalendarSettings.enabled = false
            MainActor.assumeIsolated { notch.activities.calendarSettingsChanged() }
        case .enable:
            CalendarSettings.enabled = true
            MainActor.assumeIsolated { notch.activities.calendarSettingsChanged() }
        case .requestThenEnable:
            // 点了才问一次；给了再打开，不给就维持关，什么都不出。
            sender.state = .off
            MainActor.assumeIsolated {
                notch.activities.requestCalendarAccess { [weak self, weak sender] granted in
                    CalendarSettings.enabled = granted
                    sender?.state = granted ? .on : .off
                    self?.notch.activities.calendarSettingsChanged()
                }
            }
        case .openSystemSettings:
            sender.state = .off
            openCalendarSettingsAction()
        }
    }

    @objc func prefSelectCalendarLead(_ sender: NSPopUpButton) {
        CalendarSettings.lead = CalendarActivity.LeadTime(clamping: sender.selectedItem?.tag ?? 0)
        MainActor.assumeIsolated { notch.activities.calendarSettingsChanged() }
    }

    @objc func openCalendarSettingsAction() {
        if let url = URL(string: CalendarSettings.systemSettingsURL) { NSWorkspace.shared.open(url) }
    }

    /// 欢迎窗口第三步“允许”：点了才问系统；给了就顺手打开设置里的“日程”，不给就整行收起，之后不追问。
    @objc func allowCalendarFromWelcome(_ sender: Any?) {
        MainActor.assumeIsolated {
            notch.activities.requestCalendarAccess { [weak self] granted in
                if granted {
                    CalendarSettings.enabled = true
                    self?.notch.activities.calendarSettingsChanged()
                }
                self?.refreshOnboardingState()
            }
        }
    }
    @objc func prefToggleDownloads(_ sender: NSSwitch) {
        MainActor.assumeIsolated { notch.activities.setDownloadsEnabled(sender.state == .on) }
    }
    @objc func prefToggleFileShelf(_ sender: NSSwitch) {
        MainActor.assumeIsolated {
            notch.fileShelf.setEnabled(sender.state == .on)
            notch.configureFileDrag()
        }
    }
    @objc func prefToggleMergedRow(_ sender: NSSwitch) {
        NotchController.mergedRowEnabled = sender.state == .on
        MainActor.assumeIsolated { notch.mergedRowSettingChanged() }
    }
    @objc func prefToggleCopyProgress(_ sender: NSSwitch) {
        MainActor.assumeIsolated { notch.activities.setCopyProgressEnabled(sender.state == .on) }
    }
    @objc func prefToggleOriginGuess(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state == .on, forKey: OriginGuess.enabledKey)
    }
    @objc func prefToggleBystanderCover(_ sender: NSSwitch) {
        MainActor.assumeIsolated { silentPrivacyCover.setBystanderEnabled(sender.state == .on) }
    }
    @objc func prefToggleNotchAlerts(_ sender: NSSwitch) {
        MainActor.assumeIsolated { notch.setAlertsEnabled(sender.state == .on) }
    }

    @objc func prefToggleAwaySummary(_ sender: NSSwitch) {
        AwaySummaryController.isEnabled = sender.state == .on
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
                // 观察者指定了主队列，回调在主线程。
                MainActor.assumeIsolated {
                    UserDefaults.standard.set(true, forKey: shadeOnboardingShownDefaultsKey)
                    self?.onboardingRefreshTimer?.invalidate()
                    self?.onboardingRefreshTimer = nil
                }
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
        let calendarAccess = CalendarSource.access()
        if let welcome, welcome.shownGrants == [ax, screen], welcome.shownCalendar == calendarAccess { return false }
        welcome?.shownGrants = [ax, screen]
        welcome?.shownCalendar = calendarAccess

        permissionStack.arrangedSubviews.forEach {
            permissionStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        var rows = [
            makeUnifiedPermissionRow(symbol: "accessibility", name: "辅助功能",
                subtitle: "找到、移动和恢复窗口", granted: ax,
                action: #selector(openAccessibilitySettingsAction)),
            makeUnifiedPermissionRow(symbol: "rectangle.inset.filled.and.person.filled", name: "屏幕录制",
                subtitle: "截取窗口画面做预览", granted: screen,
                action: #selector(openScreenRecordingSettingsAction)),
        ]
        // 第三行：日程（CAL-4）。可有可无，不算进“还差几步”；点了“允许”才问系统，拒绝之后整行不出。
        if let calendarRow = makeWelcomeCalendarRow(calendarAccess) { rows.append(calendarRow) }
        let card = makeUnifiedSettingsCard(rows)
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

    /// 欢迎窗口第三步的日程一行：没问过是“允许”，给了是“✓ 已允许”，不给就没有这一行。
    private func makeWelcomeCalendarRow(_ access: CalendarAccess) -> NSView? {
        let trailing: NSView
        switch access.welcomeRow {
        case .hidden:
            return nil
        case .allowButton:
            let button = NSButton(title: "允许", target: self, action: #selector(allowCalendarFromWelcome(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.setAccessibilityLabel("日程，快开会时提醒你，允许")
            trailing = button
        case .allowed:
            let chip = NSTextField(labelWithString: "✓ 已允许")
            chip.font = SystemAppearancePolicy.font(relativeToBody: -1)
            chip.textColor = .systemGreen
            chip.setAccessibilityLabel("日程，已允许")
            trailing = chip
        }
        let labels = makeUnifiedLabels(name: CalendarWords.name, subtitle: "快开会时提醒你", symbol: "calendar")
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [labels, trailing])
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labels.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -12),
            trailing.trailingAnchor.constraint(equalTo: row.trailingAnchor),
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        return row
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

        func recorderRow(_ shortcut: GlobalShortcut, subtitle: String?, quickEnable: Bool = false) -> NSView {
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
            guard quickEnable else {
                return makeUnifiedControlRow(name: shortcut.title, subtitle: subtitle, control: recorder)
            }
            // 计时器出厂不占键：这一个按钮一下用 ⌃⌥T 开上，已经是 ⌃⌥T 就不可按。
            let enable = NSButton(title: "用 ⌃⌥T 开计时器", target: self, action: #selector(prefEnableCountdownShortcut))
            enable.bezelStyle = .rounded
            enable.isEnabled = GlobalShortcutSettings.hotKey(for: shortcut) != GlobalShortcutSettings.countdownHotKey
            let control = NSStackView(views: [enable, recorder])
            control.orientation = .horizontal
            control.spacing = 8
            return makeUnifiedControlRow(name: shortcut.title, subtitle: subtitle, control: control)
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
            recorderRow(.notchShelf, subtitle: "展开后用方向键选、Return 打开、Esc 退出；默认不占用任何快捷键"),
            recorderRow(.joinColumnLeft, subtitle: "卷轴里用；已经在一列里就拆成一列。默认不占用任何快捷键"),
            recorderRow(.joinColumnRight, subtitle: "卷轴里用；已经在一列里就拆成一列。默认不占用任何快捷键"),
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
            recorderRow(.countdownTimer, subtitle: "刘海里选分钟，回车开始；默认不占用任何快捷键", quickEnable: true),
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

    /// 计时器的一键启用：把它录成 ⌃⌥T，照常注册、刷新菜单。
    @objc func prefEnableCountdownShortcut() {
        applyShortcut(GlobalShortcutSettings.countdownHotKey, for: .countdownTimer)
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
        ])
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

    /// “走到一列时”的三个选项，顺序同 ScrollStrip.Centering.allCases（edge、always、overflow）。
    static let centeringTitles = ["贴边", "居中", "放不下才居中"]

    @objc func prefSelectCentering(_ sender: NSPopUpButton) {
        let modes = ScrollStrip.Centering.allCases
        ScrollStrip.store(mode: modes[max(0, min(modes.count - 1, sender.indexOfSelectedItem))])
        MainActor.assumeIsolated { gestures.strips.refreshCentering() }
    }

    @objc func prefToggleCenterWhenFits(_ sender: NSSwitch) {
        ScrollStrip.store(whenFits: sender.state == .on)
        MainActor.assumeIsolated { gestures.strips.refreshCentering() }
    }

    @objc func prefToggleHoverGuard(_ sender: NSSwitch) {
        NotchHoverPolicy.setEnabled(sender.state == .on)
    }

    @objc func prefToggleStripWidths(_ sender: NSSwitch) {
        StripWidthMemory.setEnabled(sender.state == .on)
    }

    @objc func prefToggleStripTitleDrag(_ sender: NSSwitch) {
        StripTitleDrag.setEnabled(sender.state == .on)
    }

    @objc func prefToggleDropSplit(_ sender: NSSwitch) {
        TrackpadGestureController.dropSplitEnabled = sender.state == .on
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


/// 装着“有人在看时收起私人窗口”那一行；私人 App 名单一变就按最新名单重画，不用重进页面。
@MainActor private final class BystanderRowHost: NSStackView {
    private let build: () -> NSView
    init(build: @escaping () -> NSView) {
        self.build = build
        super.init(frame: .zero)
        orientation = .vertical; spacing = 0; alignment = .leading
        place(build())
        // 视图没了就把自己的监听摘掉；摘的时机是下一次名单变化。
        let token = ObserverToken()
        token.value = NotificationCenter.default.addObserver(
            forName: PrivateAppList.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else {
                    if let value = token.value { NotificationCenter.default.removeObserver(value) }
                    return
                }
                self.reload()
            }
        }
    }
    private final class ObserverToken: @unchecked Sendable { var value: NSObjectProtocol? }
    private func place(_ row: NSView) {
        addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }
    required init?(coder: NSCoder) { nil }
    private func reload() {
        for view in arrangedSubviews { removeArrangedSubview(view); view.removeFromSuperview() }
        place(build())
    }
}


/// 装着“音量和亮度”那一行；设置开关、辅助功能授权变了（NotchLevelSetting.didChange）就按最新状态重画，不用重进页面。
@MainActor private final class LevelRowHost: NSStackView {
    private let build: () -> NSView
    init(build: @escaping () -> NSView) {
        self.build = build
        super.init(frame: .zero)
        orientation = .vertical; spacing = 0; alignment = .leading
        place(build())
        // 视图没了就把自己的监听摘掉；摘的时机是下一次通知。
        let token = ObserverToken()
        token.value = NotificationCenter.default.addObserver(
            forName: NotchLevelSetting.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else {
                    if let value = token.value { NotificationCenter.default.removeObserver(value) }
                    return
                }
                self.reload()
            }
        }
    }
    private final class ObserverToken: @unchecked Sendable { var value: NSObjectProtocol? }
    private func place(_ row: NSView) {
        addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }
    required init?(coder: NSCoder) { nil }
    private func reload() {
        for view in arrangedSubviews { removeArrangedSubview(view); view.removeFromSuperview() }
        place(build())
    }
}

/// 点“允许…”之后等你在系统设置里打开辅助功能：设置窗口在前台时每 1 秒看一次，最多 2 分钟；
/// 窗口不在前台就停，回到前台再看一次、接着数；不在后台轮询。允许了就马上装监听，不用重开。
@MainActor private final class LevelAllowWatcher {
    static let shared = LevelAllowWatcher()
    private var watch: NotchLevelAllowWatch?
    private var timer: Timer?
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start(window: NSWindow?) {
        finish()
        self.window = window
        watch = NotchLevelAllowWatch(startedAt: now)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        })
        if let window {
            observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            })
        }
        evaluate()
    }

    private func evaluate() {
        guard let watch else { return }
        let inFront = window.map { $0.isVisible && $0.isKeyWindow && NSApp.isActive } ?? false
        switch watch.step(now: now, trusted: hasAccessibilityPermission(), windowInFront: inFront) {
        case .allowed:
            finish()
            (NSApp.delegate as? AppDelegate)?.notch.installLevelTapIfAllowed()
            NotificationCenter.default.post(name: NotchLevelSetting.didChange, object: nil)
        case .expired:
            finish()
        case .paused:
            stopTimer()
        case .waiting:
            guard timer == nil else { return }
            let next = Timer.scheduledTimer(withTimeInterval: NotchLevelAllowWatch.interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            next.tolerance = NotchLevelAllowWatch.interval / 4
            RunLoop.main.add(next, forMode: .common)
            timer = next
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func finish() {
        stopTimer()
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
        watch = nil
        window = nil
    }
}
