import Cocoa

/// 设置里的「隐私」一栏：WindowShade 读到的每一样，读什么、为什么、去了哪里。
///
/// 内容来自 tools/privacy/registry.json 生成的 WS2PrivacyData；值和开关都引用原设置，
/// 不新造开关，也不为填一个值去启动摄像头、蓝牙或网络。没读到的写「未读取」。
@MainActor
final class WS2PrivacyPane: NSStackView {
    private weak var owner: AppDelegate?
    private var showDetails = false
    private var expanded: Set<String> = []
    private let body = NSStackView()

    init(owner: AppDelegate) {
        self.owner = owner
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 12
        build()
    }
    required init?(coder: NSCoder) { nil }

    private func build() {
        let leadText = "这里列出 WindowShade 读到的每一样，以及为什么读、去了哪里。值和开关都来自原来的设置。"
        addArrangedSubview(WS2SettingsCopy.content(name: nil, subtitle: leadText, symbol: "lock.shield").view)

        let details = NSButton(checkboxWithTitle: "显示技术细节", target: self, action: #selector(toggleDetails(_:)))
        details.state = showDetails ? .on : .off
        details.toolTip = "每行多一条登记表里的接口名。"
        addArrangedSubview(details)

        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 16
        addArrangedSubview(body)
        rebuild()
    }

    private func rebuild() {
        body.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let owner else { return }
        for group in WS2PrivacyData.groupOrder {
            let rows = WS2PrivacyData.rows.filter { $0.group == group }
            guard !rows.isEmpty else { continue }
            body.addArrangedSubview(owner.makePrefGroupLabel(group))
            let card = owner.makeUnifiedSettingsCard(rows.map { rowView($0) }, separatorInset: 16)
            body.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
    }

    private func rowView(_ row: WS2PrivacyRow) -> NSView {
        PrivacyRowView(
            row: row,
            value: WS2PrivacyValues.value(for: row.id, owner: owner),
            expanded: expanded.contains(row.id),
            showDetails: showDetails) { [weak self] in
                guard let self else { return }
                if self.expanded.contains(row.id) { self.expanded.remove(row.id) } else { self.expanded.insert(row.id) }
                self.rebuild()
            }
    }

    @objc private func toggleDetails(_ sender: NSButton) {
        showDetails = sender.state == .on
        rebuild()
    }
}

/// 一次点击展开的行：标题、现在的值（private 默认藏起来）、以及三件事的原文。
@MainActor
private final class PrivacyRowView: NSView {
    init(row: WS2PrivacyRow, value: String?, expanded: Bool, showDetails: Bool, onToggle: @escaping () -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.onToggle = onToggle

        let symbolName = WS2SettingsCopy.symbol(for: row.label)
        let symbolView: NSView? = {
            guard let symbolName,
                  let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: row.label) else { return nil }
            let symbol = NSImageView(image: image)
            symbol.symbolConfiguration = NSImage.SymbolConfiguration(hierarchicalColor: .controlAccentColor)
            symbol.wantsLayer = true
            symbol.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
            symbol.layer?.cornerRadius = 7
            symbol.widthAnchor.constraint(equalToConstant: 28).isActive = true
            symbol.heightAnchor.constraint(equalToConstant: 28).isActive = true
            return symbol
        }()

        let title = NSTextField(labelWithString: row.label)
        title.font = SystemAppearancePolicy.font(relativeToBody: 0)
        let shown = shownValue(row: row, value: value, expanded: expanded)
        let valueLabel = NSTextField(labelWithString: shown)
        valueLabel.font = SystemAppearancePolicy.font(relativeToBody: -2)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.lineBreakMode = .byTruncatingTail

        let chevron = NSButton(image: NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right",
                                              accessibilityDescription: expanded ? "收起" : "展开") ?? NSImage(),
                               target: nil, action: nil)
        chevron.bezelStyle = .inline
        chevron.isBordered = false
        chevron.target = self
        chevron.action = #selector(toggle)
        chevron.setAccessibilityLabel("\(row.label)的详情")

        let labels = NSStackView(views: [title, valueLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        var headerViews: [NSView] = []
        if let symbolView { headerViews.append(symbolView) }
        headerViews.append(contentsOf: [labels, chevron])
        let header = NSStackView(views: headerViews)
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var constraints = [
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 9),
        ]
        if expanded {
            let detail = NSStackView(views: [
                detailLine("读到的", row.reads),
                detailLine("为什么", row.purpose),
                detailLine("去了哪里", row.destination),
                detailLine("什么时候读", row.activation),
                detailLine("开关", row.toggle),
            ] + (showDetails && !row.interfaces.isEmpty ? [detailLine("接口", row.interfaces.joined(separator: "、"))] : []))
            detail.orientation = .vertical
            detail.alignment = .leading
            detail.spacing = 4
            detail.translatesAutoresizingMaskIntoConstraints = false
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

    private var onToggle: (() -> Void)?
    @objc private func toggle() { onToggle?() }

    /// private 的值默认不展开；没读到的照实写「未读取」。
    private func shownValue(row: WS2PrivacyRow, value: String?, expanded: Bool) -> String {
        if row.sensitivity == "private", !expanded { return "已隐藏" }
        return value ?? "未读取"
    }

    private func detailLine(_ title: String, _ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: "\(title)：\(text)")
        label.font = SystemAppearancePolicy.font(relativeToBody: -2)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 3
        return label
    }
}

/// 页面上的值只取现有只读快照，不为填值去启动任何东西；取不到就是未读取。
@MainActor
enum WS2PrivacyValues {
    static func value(for id: String, owner: AppDelegate?) -> String? {
        switch id {
        case "screen-shape":
            return "\(NSScreen.screens.count) 块屏"
        case "lock-state":
            switch EffectSecurityBoundary.lockState {
            case .unlocked: return "未锁屏"
            case .locked: return "已锁屏"
            case .unknown: return "未读取"
            }
        case "battery":
            return activity(owner, kind: .airPods).map { "\($0.title) \($0.subtitle)" }
        case "recording-app":
            return activity(owner, kind: .recording).map(\.title) ?? "没有 App 在录音"
        case "window-ax":
            return hasAccessibilityPermission() ? "已授权" : "未授权"
        case "window-image":
            return hasScreenRecordingPermission() ? "已授权" : "未授权"
        case "music":
            return activity(owner, kind: .music).map { "\($0.title) · \($0.subtitle)" } ?? "没有在放"
        case "update":
            return UpdaterController.shared.automaticallyChecks ? "自动检查更新开着" : "自动检查更新关着"
        case "settings":
            return "本机偏好"
        case "diagnostics":
            return "~/Library/Logs/WindowShade/windowshade.log"
        case "login-item":
            return owner?.launchAtLoginEnabled() == true ? "已开启" : "未开启"
        default:
            return nil
        }
    }

    private static func activity(_ owner: AppDelegate?, kind: NotchActivityKind) -> NotchActivity? {
        owner?.notch.activities.store.activities.first { $0.kind == kind }
    }
}
