import Cocoa
import UniformTypeIdentifiers

/// 设置里的「隐私」一栏：WindowShade 读到的每一样，读什么、为什么、去了哪里。
///
/// 内容来自 tools/privacy/registry.json 生成的 WS2PrivacyData；值和开关都引用原设置，
/// 不新造开关，也不为填一个值去启动摄像头、蓝牙或网络。
///
/// 读取：页面出现时读一次，页头写下读的时间；“再读一次”再读一次；页面关了或离开就不再读。
/// 这里没有定时器，也不轮询（tests/PrivacyPaneTests.swift 会检查这一点）。
/// 能读到的写原值（“妙控鼠标 82%”），读不到写「没读到」，不编。
/// planned 的行默认不显示，对应功能打开后才出现。
@MainActor
final class WS2PrivacyPane: NSStackView {
    private weak var owner: AppDelegate?
    private let session = WS2PrivacyReadSession()
    private var snapshot = WS2PrivacySnapshot()
    private var showDetails = false
    private var expanded: Set<String> = []
    private let readAtLabel = NSTextField(labelWithString: "")
    private let body = NSStackView()

    /// 这一页已经读过几次。测试用。
    var readCount: Int { session.readCount }

    init(owner: AppDelegate) {
        self.owner = owner
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 12
        session.onRead = { [weak self] date in self?.didRead(at: date) }
        build()
    }
    required init?(coder: NSCoder) { nil }

    private func build() {
        readAtLabel.font = SystemAppearancePolicy.font(relativeToBody: -2)
        readAtLabel.textColor = .secondaryLabelColor
        readAtLabel.lineBreakMode = .byTruncatingTail
        let reread = NSButton(title: WS2PrivacyCopy.rereadTitle, target: self, action: #selector(rereadPressed(_:)))
        reread.bezelStyle = .rounded
        reread.controlSize = .small
        reread.toolTip = WSL10n.text("settings.privacy.rereadTooltip", zh: "再读一次现在的值。")
        let details = NSButton(checkboxWithTitle: WS2PrivacyCopy.showDetailsTitle, target: self,
                               action: #selector(toggleDetails(_:)))
        details.state = showDetails ? .on : .off
        details.controlSize = .small
        details.font = SystemAppearancePolicy.font(relativeToBody: -1)
        details.toolTip = WSL10n.text("settings.privacy.detailsTooltip", zh: "每行多一条登记表里的接口名。")
        let export = NSButton(title: WS2PrivacyCopy.exportTitle, target: self, action: #selector(exportJSON(_:)))
        export.bezelStyle = .rounded
        export.controlSize = .small
        export.toolTip = WSL10n.text("settings.privacy.exportTooltip", zh: "存成一个文件。不会上传。")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let toolbar = NSStackView(views: [readAtLabel, reread, spacer, details, export])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 12
        toolbar.setCustomSpacing(8, after: readAtLabel)
        toolbar.distribution = .fill
        readAtLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addArrangedSubview(toolbar)
        toolbar.widthAnchor.constraint(equalTo: widthAnchor).isActive = true

        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 16
        addArrangedSubview(body)
        body.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    // MARK: 读取

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        center.removeObserver(self)
        if let window {
            center.addObserver(self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window)
            center.addObserver(self, selector: #selector(windowBecameKey), name: NSWindow.didBecomeKeyNotification, object: window)
            session.open()
        } else {
            session.close()
        }
    }

    @objc private func windowWillClose() { session.close() }
    /// 设置窗口关了又打开：同一页再次出现，读一次。已经打开着就什么也不做。
    @objc private func windowBecameKey() { session.open() }

    @objc private func rereadPressed(_ sender: NSButton) { session.reread() }

    private func didRead(at date: Date) {
        snapshot = WS2PrivacyValues.read(owner: owner, window: window)
        readAtLabel.stringValue = WS2PrivacyCopy.readAtText(date)
        rebuild()
    }

    // MARK: 摆放

    private func rebuild() {
        body.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let owner else { return }
        let rows = WS2PrivacyVisibility.visibleRows(WS2PrivacyData.rows, enabledFeatures: snapshot.features)
        for group in WS2PrivacyData.groups {
            let groupRows = rows.filter { $0.group == group.title }
            let isDestination = group.title == WS2PrivacyCopy.destinationGroupTitle
            guard !groupRows.isEmpty || isDestination else { continue }
            let header = groupHeader(group, owner: owner)
            body.addArrangedSubview(header)
            body.setCustomSpacing(8, after: header)
            var cards: [NSView] = []
            if isDestination { cards += destinationCards(owner: owner) }
            if !groupRows.isEmpty {
                cards.append(owner.makeUnifiedSettingsCard(groupRows.map { rowView($0) }, separatorInset: 16))
            }
            for card in cards {
                body.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
                if card !== cards.last { body.setCustomSpacing(10, after: card) }
            }
        }
    }

    private func groupHeader(_ group: WS2PrivacyGroup, owner: AppDelegate) -> NSView {
        let title = owner.makePrefGroupLabel(group.title)
        guard !group.subtitle.isEmpty else { return title }
        let subtitle = NSTextField(labelWithString: group.subtitle)
        subtitle.font = SystemAppearancePolicy.font(relativeToBody: -2)
        subtitle.textColor = .tertiaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 8
        return stack
    }

    private func rowView(_ row: WS2PrivacyRow) -> NSView {
        let permissionGranted = row.permission.flatMap { snapshot.permissions[$0] }
        let presentation = WS2PrivacyRowPresentation.make(
            row: row, value: snapshot.values[row.id],
            hasValueSource: WS2PrivacyValues.hasValueSource(row.id), permissionGranted: permissionGranted)
        let switchSpec = row.switchID.flatMap { self.switchSpec($0) }
        return PrivacyRowView(
            row: row, presentation: presentation, expanded: expanded.contains(row.id),
            showDetails: showDetails, switchSpec: switchSpec, grantTarget: owner,
            grantAction: Self.grantAction(for: row.permission)) { [weak self] in
                guard let self else { return }
                if self.expanded.contains(row.id) { self.expanded.remove(row.id) } else { self.expanded.insert(row.id) }
                self.rebuild()
            }
    }

    /// “去授权”点下去要跳到的系统设置；没有对应页面的授权不给这个按钮。
    private static func grantAction(for permission: String?) -> Selector? {
        switch permission {
        case "辅助功能": return #selector(AppDelegate.openAccessibilitySettingsAction)
        case "屏幕录制": return #selector(AppDelegate.openScreenRecordingSettingsAction)
        default: return nil
        }
    }

    /// 展开后放的开关：全部是原设置自己的那一个，同一个处理函数、同一个存储，不另存第二份。
    private func switchSpec(_ id: String) -> PrivacySwitchSpec? {
        guard let owner else { return nil }
        switch id {
        case "activities":
            return PrivacySwitchSpec(title: WSL10n.text("settings.privacy.switch.activities", zh: "实时活动"), isOn: NotchActivityController.isEnabled,
                                     target: owner, action: #selector(AppDelegate.prefToggleActivities(_:)))
        case "calendar":
            return PrivacySwitchSpec(title: WSL10n.text("settings.privacy.switch.calendar", zh: "日程"), isOn: CalendarSettings.enabled && CalendarSource.access().canRead,
                                     target: owner, action: #selector(AppDelegate.prefToggleCalendar(_:)))
        case "downloads":
            return PrivacySwitchSpec(title: WSL10n.text("settings.privacy.switch.downloads", zh: "浏览器下载"), isOn: DownloadActivitySource.isEnabled,
                                     target: owner, action: #selector(AppDelegate.prefToggleDownloads(_:)))
        case "login":
            return PrivacySwitchSpec(title: WSL10n.text("settings.privacy.launchAtLogin.name", zh: "登录时自动启动"), isOn: owner.launchAtLoginEnabled(),
                                     target: owner, action: #selector(AppDelegate.prefToggleLaunchAtLogin(_:)))
        case "autoUpdate":
            return PrivacySwitchSpec(title: UpdateCopy.autoCheck, isOn: UpdaterController.shared.automaticallyChecks,
                                     target: UpdaterController.shared,
                                     action: #selector(UpdaterController.settingsToggleAutomaticChecks(_:)))
        case "desktop":
            return PrivacySwitchSpec(title: WSL10n.text("settings.privacy.switch.desktop", zh: "桌面开合"), isOn: owner.duoController.settings.desktopEnabled,
                                     target: self, action: #selector(toggleDesktop(_:)))
        case "focusQuiet":
            return PrivacySwitchSpec(title: WSL10n.text("settings.privacy.switch.focusQuiet", zh: "专注模式时更安静"), isOn: SystemQuietState.focusQuietEnabled,
                                     target: self, action: #selector(toggleFocusQuiet(_:)))
        default:
            return nil
        }
    }

    /// 打开才会请求系统的专注模式授权；默认关。
    @objc private func toggleFocusQuiet(_ sender: NSSwitch) {
        SystemQuietState.shared.setFocusQuiet(sender.state == .on)
    }

    /// 和效果设置页里“桌面开合”是同一个设置：改同一份、走同一个刷新。
    @objc private func toggleDesktop(_ sender: NSSwitch) {
        guard let owner else { return }
        let controller = owner.duoController
        var settings = controller.settings
        settings.desktopEnabled = sender.state == .on
        controller.settings = settings
        controller.settingsChanged()
        owner.rebuildMenu()
    }

    // MARK: 去了哪里

    private func destinationCards(owner: AppDelegate) -> [NSView] {
        let primary = UpdateLinks.downloadPage.host ?? ""
        let fallback = URL(string: UpdateLinks.fallbackFeed)?.host ?? ""
        let network = WS2PrivacyCopy.networkCard(primaryHost: primary, fallbackHost: fallback)
        let storage = WS2PrivacyCopy.storageCard
        let networkCard = owner.makeUnifiedSettingsCard([PrivacyNoteView(lead: network.lead, text: network.body)])
        let showButton = NSButton(title: WS2PrivacyCopy.showInFinder, target: self, action: #selector(showInFinder(_:)))
        showButton.bezelStyle = .rounded
        showButton.controlSize = .small
        let storageCard = owner.makeUnifiedSettingsCard([PrivacyNoteView(lead: storage.lead, text: storage.body, button: showButton)])
        return [networkCard, storageCard]
    }

    /// 打开运行记录文件夹，并在访达里选中设置文件。文件夹还没有时只显示设置文件。
    @objc private func showInFinder(_ sender: NSButton) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let logs = WS2PrivacyPlaces.logsDirectory(home: home)
        let bundleID = Bundle.main.bundleIdentifier ?? "WindowShade"
        let preferences = WS2PrivacyPlaces.preferencesFile(home: home, bundleID: bundleID)
        let manager = FileManager.default
        if manager.fileExists(atPath: logs.path) { NSWorkspace.shared.open(logs) }
        if manager.fileExists(atPath: preferences.path) {
            NSWorkspace.shared.activateFileViewerSelecting([preferences])
        } else if !manager.fileExists(atPath: logs.path) {
            NSWorkspace.shared.open(preferences.deletingLastPathComponent())
        }
    }

    @objc private func toggleDetails(_ sender: NSButton) {
        showDetails = sender.state == .on
        rebuild()
    }

    // MARK: 导出

    @objc private func exportJSON(_ sender: NSButton) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = WSL10n.text("settings.privacy.exportName", zh: "WindowShade 读到的.json")
        panel.canCreateDirectories = true
        let save: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard response == .OK, let url = panel?.url else { return }
            MainActor.assumeIsolated { self?.writeExport(to: url) }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: save)
        } else {
            save(panel.runModal())
        }
    }

    /// 导出页面上这一次读到的样子：private 行不带原值，还没读的行值为空。
    private func writeExport(to url: URL) {
        let values = snapshot.exportValues(rows: WS2PrivacyData.rows)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? WSL10n.text("settings.privacy.permission.unknown", zh: "未知")
        do {
            let data = try WS2PrivacyExport.jsonData(
                rows: WS2PrivacyData.rows, values: values, exportedAt: Date(), appVersion: version)
            try data.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = WSL10n.text("settings.privacy.exportFailedTitle", zh: "没能导出")
            alert.informativeText = WSL10n.text("settings.privacy.exportFailedBody", zh: "文件没有存进你选的位置。换一个位置再试一次。")
            alert.addButton(withTitle: UpdateCopy.ok)
            alert.runModal()
        }
    }
}

/// 展开区里的开关：名字、现在开不开，以及原设置自己的处理函数。
struct PrivacySwitchSpec {
    let title: String
    let isOn: Bool
    let target: AnyObject
    let action: Selector
}

/// “去了哪里”里的说明卡：一句粗体开头，后面接说明，可以带一个按钮。
@MainActor
private final class PrivacyNoteView: NSView {
    init(lead: String, text: String, button: NSButton? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let leadLabel = NSTextField(labelWithString: lead)
        leadLabel.font = SystemAppearancePolicy.font(relativeToBody: 0, weight: .semibold)
        let textLabel = NSTextField(wrappingLabelWithString: text)
        textLabel.font = SystemAppearancePolicy.font(relativeToBody: -2)
        textLabel.textColor = .secondaryLabelColor
        textLabel.maximumNumberOfLines = 0
        var views: [NSView] = [leadLabel, textLabel]
        if let button { views.append(button) }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
        ])
    }
    required init?(coder: NSCoder) { nil }
}

/// 一行的头：点哪里都能展开；里面的按钮（去授权、展开箭头）各管各的。
@MainActor
private final class PrivacyHeaderStack: NSStackView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// 一次点击展开的行：名字 + 一行原因 + 右边的值，展开后是读到的、为什么、去了哪里，和能关的开关。
@MainActor
final class PrivacyRowView: NSView {
    private var onToggle: (() -> Void)?

    init(row: WS2PrivacyRow, presentation: WS2PrivacyRowPresentation, expanded: Bool, showDetails: Bool,
         switchSpec: PrivacySwitchSpec?, grantTarget: AnyObject?, grantAction: Selector?,
         onToggle: @escaping () -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.onToggle = onToggle

        let title = NSTextField(labelWithString: row.label)
        title.font = SystemAppearancePolicy.font(relativeToBody: 0)
        title.lineBreakMode = .byTruncatingTail
        title.toolTip = row.label
        let subtitle = NSTextField(labelWithString: presentation.subtitleLine)
        subtitle.font = SystemAppearancePolicy.font(relativeToBody: -2)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.toolTip = presentation.subtitleLine
        let labels = NSStackView(views: [title, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.widthAnchor.constraint(lessThanOrEqualTo: labels.widthAnchor).isActive = true
        subtitle.widthAnchor.constraint(lessThanOrEqualTo: labels.widthAnchor).isActive = true

        let chevron = NSButton(image: NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right",
                                              accessibilityDescription: expanded ? WSL10n.text("settings.effects.roll", zh: "收起") : WSL10n.text("settings.effects.unroll", zh: "展开")) ?? NSImage(),
                               target: nil, action: nil)
        chevron.bezelStyle = .inline
        chevron.isBordered = false
        chevron.target = self
        chevron.action = #selector(toggle)
        chevron.setAccessibilityLabel(WSL10n.text("settings.privacy.rowDetail", zh: "%@的详情", row.label))
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let header = PrivacyHeaderStack()
        header.onClick = { [weak self] in self?.onToggle?() }
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false
        // 登记行只有纯文字（原稿“WindowShade 读到的”画面）；不再按标题关键词挂图标——
        // 偶发映射让个别行凭空多出 28+10 的缩进，登记表不再有统一的说明列。
        header.addArrangedSubview(labels)
        if let value = valueView(presentation.display, grantTarget: grantTarget, grantAction: grantAction) {
            header.addArrangedSubview(value)
            value.widthAnchor.constraint(lessThanOrEqualTo: header.widthAnchor, multiplier: 0.4).isActive = true
        }
        header.addArrangedSubview(chevron)
        addSubview(header)

        var constraints = [
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 9),
        ]
        if expanded {
            var lines: [NSView] = [
                detailLine(WSL10n.text("settings.privacy.detail.reads", zh: "读到的"), row.reads),
                detailLine(WSL10n.text("settings.privacy.detail.purpose", zh: "为什么"), row.purpose),
                detailLine(WSL10n.text("settings.privacy.detail.destination", zh: "去了哪里"), row.destination),
                detailLine(WSL10n.text("settings.privacy.detail.activation", zh: "什么时候读"), row.activation),
            ]
            // 有真的开关就放开关，不再重复写一遍“开关：”。
            if switchSpec == nil { lines.append(detailLine(WSL10n.text("settings.privacy.detail.toggle", zh: "开关"), row.toggle)) }
            if let combined = row.combined { lines.append(detailLine(WSL10n.text("settings.privacy.detail.combined", zh: "合起来能看出什么"), combined)) }
            if showDetails, !row.interfaces.isEmpty {
                lines.append(detailLine(WSL10n.text("settings.privacy.detail.interfaces", zh: "接口"), row.interfaces.joined(separator: "、")))
            }
            if let switchSpec { lines.append(switchRow(switchSpec)) }
            let detail = NSStackView(views: lines)
            detail.orientation = .vertical
            detail.alignment = .leading
            detail.spacing = 4
            detail.translatesAutoresizingMaskIntoConstraints = false
            for line in lines { line.widthAnchor.constraint(equalTo: detail.widthAnchor).isActive = true }
            addSubview(detail)
            constraints += [
                detail.leadingAnchor.constraint(equalTo: labels.leadingAnchor),
                detail.trailingAnchor.constraint(equalTo: trailingAnchor),
                detail.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
                detail.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            ]
        } else {
            constraints.append(header.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9))
        }
        NSLayoutConstraint.activate(constraints)
    }
    required init?(coder: NSCoder) { nil }

    @objc private func toggle() { onToggle?() }

    /// 右边那一格：值的文字、已授权，或者可点的去授权（点了跳到系统设置）。
    private func valueView(_ display: WS2PrivacyValueDisplay, grantTarget: AnyObject?, grantAction: Selector?) -> NSView? {
        switch display {
        case .text(let text):
            guard !text.isEmpty else { return nil }
            let label = NSTextField(labelWithString: text)
            label.font = SystemAppearancePolicy.font(relativeToBody: -1)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.lineBreakMode = .byTruncatingMiddle
            label.toolTip = text
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            return label
        case .granted:
            let label = NSTextField(labelWithString: WS2PrivacyCopy.granted)
            label.font = SystemAppearancePolicy.font(relativeToBody: -1)
            label.textColor = .secondaryLabelColor
            label.setContentHuggingPriority(.required, for: .horizontal)
            return label
        case .needsGrant:
            guard let grantAction else {
                let label = NSTextField(labelWithString: WS2PrivacyCopy.needsGrant)
                label.font = SystemAppearancePolicy.font(relativeToBody: -1)
                label.textColor = .systemOrange
                return label
            }
            let button = NSButton(title: WS2PrivacyCopy.needsGrant, target: grantTarget, action: grantAction)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.setContentHuggingPriority(.required, for: .horizontal)
            return button
        }
    }

    private func switchRow(_ spec: PrivacySwitchSpec) -> NSView {
        let label = NSTextField(labelWithString: spec.title)
        label.font = SystemAppearancePolicy.font(relativeToBody: -1)
        let toggle = NSSwitch()
        toggle.state = spec.isOn ? .on : .off
        toggle.target = spec.target
        toggle.action = spec.action
        toggle.controlSize = .small
        toggle.setAccessibilityLabel(spec.title)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [label, spacer, toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func detailLine(_ title: String, _ text: String) -> NSView {
        let font = SystemAppearancePolicy.font(relativeToBody: -1)
        let columnWidth = font.pointSize * 4.4
        // 按身份（中文源句）取短标题；显示走目录，不把中文串当显示。
        let caption = title == WSL10n.text("settings.privacy.detail.activation", zh: "什么时候读")
            ? WSL10n.text("settings.privacy.caption.when", zh: "什么时候")
            : (title == WSL10n.text("settings.privacy.detail.combined", zh: "合起来能看出什么")
                ? WSL10n.text("settings.privacy.caption.combined", zh: "合起来看")
                : title)
        let label = NSTextField(wrappingLabelWithString: caption)
        label.font = font
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = columnWidth
        label.toolTip = title
        label.identifier = NSUserInterfaceItemIdentifier("privacy-detail-label")
        label.widthAnchor.constraint(equalToConstant: columnWidth).isActive = true
        let value = NSTextField(wrappingLabelWithString: text)
        value.font = font
        value.textColor = .labelColor
        value.maximumNumberOfLines = 0
        value.toolTip = text
        value.identifier = NSUserInterfaceItemIdentifier("privacy-detail-body")
        for field in [label, value] {
            field.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, value])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10
        value.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -columnWidth - 10).isActive = true
        return row
    }
}

/// 页面上的值只取现有只读快照，不为填值去启动任何东西；取不到就是没读到。
@MainActor
enum WS2PrivacyValues {
    /// 这一行有没有能现读的值。没有来源的行右边什么也不写；有来源却没读到的写「没读到」。
    static func hasValueSource(_ id: String) -> Bool {
        valueSourceIDs.contains(id)
    }

    private static let valueSourceIDs: Set<String> = [
        "screen-shape", "lock-state", "battery", "recording-app", "camera-frame", "music",
        "hinge", "tilt", "update", "settings", "diagnostics", "login-item", "download-files", "copy-progress",
    ]

    /// 打开这一页（或按“再读一次”）时整页读一次。planned 的行不读。
    static func read(owner: AppDelegate?, window: NSWindow?) -> WS2PrivacySnapshot {
        var snapshot = WS2PrivacySnapshot()
        if UserDefaults.standard.bool(forKey: FaceScanExperiment.enabledKey) {
            snapshot.features.insert(WS2PrivacyCopy.faceUnlockFeature)
        }
        snapshot.permissions[WSL10n.text("settings.common.accessibility", zh: "辅助功能")] = hasAccessibilityPermission()
        snapshot.permissions[WSL10n.text("settings.common.screenRecording", zh: "屏幕录制")] = hasScreenRecordingPermission()
        for row in WS2PrivacyData.rows where row.status != "planned" {
            if let value = value(for: row.id, owner: owner, window: window) { snapshot.values[row.id] = value }
        }
        return snapshot
    }

    private static func value(for id: String, owner: AppDelegate?, window: NSWindow?) -> String? {
        switch id {
        case "screen-shape":
            let screen = window?.screen ?? NSScreen.main
            return WS2PrivacyFormat.screen(count: NSScreen.screens.count,
                                           thisScreenHasNotch: screen.map { $0.safeAreaInsets.top > 0 })
        case "lock-state":
            switch EffectSecurityBoundary.lockState {
            case .unlocked: return WSL10n.text("settings.privacy.value.unlocked", zh: "未锁屏")
            case .locked: return WSL10n.text("settings.privacy.value.locked", zh: "已锁屏")
            case .unknown: return nil
            }
        case "battery":
            guard DeviceBatteryController.isEnabled else { return WS2PrivacyFormat.onOff(false) }
            guard let owner else { return nil }
            return WS2PrivacyFormat.battery(book: owner.deviceBattery.book, now: ProcessInfo.processInfo.systemUptime)
        case "recording-app":
            return WS2PrivacyFormat.recording(activitiesEnabled: NotchActivityController.isEnabled,
                                              title: activity(owner, kind: .recording)?.title)
        case "camera-frame":
            return WS2PrivacyFormat.camera(bystanderEnabled: BystanderCameraPick.isEnabled)
        case "music":
            return WS2PrivacyFormat.music(activitiesEnabled: NotchActivityController.isEnabled,
                                          paused: activity(owner, kind: .music)?.isPaused)
        case "hinge":
            guard let owner else { return nil }
            let controller = owner.duoController
            return WS2PrivacyFormat.hinge(desktopEnabled: controller.settings.desktopEnabled, angle: controller.angle)
        case "tilt":
            guard let owner else { return nil }
            return WS2PrivacyFormat.onOff(owner.duoController.settings.desktopEnabled)
        case "update":
            return UpdaterController.shared.automaticallyChecks ? WSL10n.text("settings.privacy.value.autoCheckOn", zh: "自动检查更新开着") : WSL10n.text("settings.privacy.value.autoCheckOff", zh: "自动检查更新关着")
        case "settings":
            return WSL10n.text("settings.privacy.value.onDisk", zh: "存在这台 Mac 上")
        case "diagnostics":
            return "~/Library/Logs/WindowShade"
        case "login-item":
            return owner?.launchAtLoginEnabled() == true ? WSL10n.text("settings.privacy.value.on", zh: "已开启") : WSL10n.text("settings.privacy.value.off", zh: "未开启")
        case "download-files":
            return WS2PrivacyFormat.onOff(DownloadActivitySource.isEnabled)
        case "copy-progress":
            return WS2PrivacyFormat.onOff(CopyProgressSource.isEnabled)
        default:
            return nil
        }
    }

    private static func activity(_ owner: AppDelegate?, kind: NotchActivityKind) -> NotchActivity? {
        owner?.notch.activities.store.activities.first { $0.kind == kind }
    }
}
