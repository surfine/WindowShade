import Cocoa

/// 「手势」页的行装饰（规格 R16）：每一行多一行「手指」，标题栏手势下带一张只读对照表。
/// 行本身（名字、说明、开关、动作）仍由原来的行构造器建，这里只往行的文字列里续两样东西。
enum GestureRows {
    /// 手指一行的两种写法：原语是一个动作（双击、两指滑）；组合是动作加落点（甩到刘海、拖到另一扇窗口上）。
    enum Kind { case primitive, combination }

    /// 把「手指」一行（和可选的对照表）接在一行的文字列末尾。
    /// 找不到文字列时原样返回——不改行为，也不崩。explainer：指到这一行时讲解带演哪一段（见 SettingsExplainerHost）。
    @MainActor
    static func decorate(_ row: NSView, fingers: SettingsText, kind: Kind,
                         table: GestureTableDisclosure? = nil, explainer: ExplainerRow? = nil) -> NSView {
        SettingsExplainerHost.tag(row, explainer)
        // 有了上面的讲解，行尾的 ⓘ 全拿掉（稿：手势页的行不留 ⓘ）。
        if let content = (row as? NSStackView)?.arrangedSubviews.first as? NSStackView {
            content.arrangedSubviews.filter { $0 is WS2SettingsInfoButton }.forEach { $0.removeFromSuperview() }
        }
        guard let labels = labelsColumn(of: row) else { return row }
        labels.addArrangedSubview(fingerLine(fingers, kind: kind))
        if let table { labels.addArrangedSubview(table) }
        // 多了一行之后，文字列上下都要留出 8pt（输入页的行构造器没有这两条，其余行已有，重复无害）。
        NSLayoutConstraint.activate([
            labels.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -8),
        ])
        return row
    }

    /// 行 = [内容, 控件]；内容 = [图标?, 文字列, ⓘ?]。文字列是内容里那一个竖向的栈。
    @MainActor
    private static func labelsColumn(of row: NSView) -> NSStackView? {
        guard let rowStack = row as? NSStackView,
              let content = rowStack.arrangedSubviews.first as? NSStackView else { return nil }
        return content.arrangedSubviews.compactMap { $0 as? NSStackView }.first { $0.orientation == .vertical }
    }

    @MainActor
    private static func fingerLine(_ fingers: SettingsText, kind: Kind) -> NSView {
        let caption = NSTextField(labelWithString: WSL10n.text("settings.gesture.fingers", zh: "手指"))
        caption.font = SystemAppearancePolicy.font(relativeToBody: -3)
        caption.textColor = .tertiaryLabelColor
        caption.setContentHuggingPriority(.required, for: .horizontal)
        let chip = GestureChip(text: fingers.shown, kind: kind)
        let line = NSStackView(views: [caption, chip])
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 6
        line.setAccessibilityLabel(WSL10n.text("settings.gesture.fingers", zh: "手指") + ": " + fingers.shown)
        return line
    }
}

/// 手势页的分段：四个分组各是一段，一次只露一段的卡片；换段时讲解带换成这一段的页默认。
/// 选的是哪一段记在进程里，开关一拨整页重建时不会跳回第一段。
@MainActor
final class GestureSegments: NSObject {
    static var selected = 0
    private static let keepAlive = NSMapTable<NSSegmentedControl, GestureSegments>.weakToStrongObjects()

    private let cards: [NSView]
    private weak var band: SettingsExplainerBand?

    private init(cards: [NSView], band: SettingsExplainerBand?) {
        self.cards = cards
        self.band = band
    }

    /// 把分段控件和各段的卡片接到页的栈里（接在讲解带下面）。
    static func install(_ groups: [(title: String, card: NSView)], in stack: NSStackView, band: SettingsExplainerBand?) {
        guard !groups.isEmpty else { return }
        selected = min(max(selected, 0), groups.count - 1)
        let control = NSSegmentedControl(labels: groups.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
        control.segmentDistribution = .fillEqually
        control.selectedSegment = selected
        control.translatesAutoresizingMaskIntoConstraints = false
        let owner = GestureSegments(cards: groups.map(\.card), band: band)
        control.target = owner
        control.action = #selector(changed(_:))
        keepAlive.setObject(owner, forKey: control)
        stack.addArrangedSubview(control)
        control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        control.heightAnchor.constraint(equalToConstant: 28).isActive = true
        stack.setCustomSpacing(14, after: control)
        for (index, group) in groups.enumerated() {
            stack.addArrangedSubview(group.card)
            group.card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            group.card.isHidden = index != selected
        }
    }

    @objc private func changed(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard index >= 0, index < cards.count else { return }
        Self.selected = index
        for (i, card) in cards.enumerated() { card.isHidden = i != index }
        band?.switchPage(.gestures(segment: index))
    }
}

/// 手指那一行里的小标签：原语用强调色底，组合用次要文字色的细边（橙色在设计系统里是“出了问题”），
/// 浅深色各自跟着外观解析。
final class GestureChip: NSView {
    private let label: NSTextField
    private let kind: GestureRows.Kind

    init(text: String, kind: GestureRows.Kind) {
        self.kind = kind
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        label.font = NSFont.monospacedSystemFont(ofSize: SystemAppearancePolicy.font(relativeToBody: -3).pointSize, weight: .regular)
        label.textColor = kind == .primitive ? .controlAccentColor : .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setAccessibilityElement(false)
        applyColors()
    }
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        guard let layer else { return }
        layer.cornerRadius = 5
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch kind {
            case .primitive:
                layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
                layer.borderWidth = 0
            case .combination:
                layer.backgroundColor = NSColor.clear.cgColor
                layer.borderWidth = 1
                layer.borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.5).cgColor
            }
        }
    }
}

/// 标题栏手势下的对照表：每个方向做什么，每一行能指（讲解带跟着演）。内容取自 `GestureMap.titleBar` / `GestureMap.strip`，
/// 不是新开关。展开与否记在进程里，开关一拨整页重建时不会自己合上。
final class GestureTableDisclosure: NSStackView {
    nonisolated(unsafe) private static var expanded = false

    private let toggle: NSButton
    private let body: NSStackView

    /// explainer：指到对照表这一行时讲解带演哪一段（nil 跟着它所在的那一行）。
    struct Line { let gesture: SettingsText; let effect: SettingsText; var explainer: ExplainerRow? = nil }

    @MainActor
    init(title: SettingsText, gestureColumn: SettingsText, effectColumn: SettingsText,
         lines: [Line], note: SettingsText? = nil) {
        toggle = NSButton(title: title.shown, target: nil, action: nil)
        body = NSStackView()
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 6

        toggle.isBordered = false
        toggle.font = SystemAppearancePolicy.font(relativeToBody: -2)
        toggle.contentTintColor = .controlAccentColor
        toggle.imagePosition = .imageLeading
        toggle.alignment = .left
        toggle.target = self
        toggle.action = #selector(flip)
        toggle.setAccessibilityLabel(title.shown)

        let grid = NSGridView(views: [[Self.cell(gestureColumn.shown, header: true), Self.cell(effectColumn.shown, header: true)]]
            + lines.map { line in
                let cells = [Self.cell(line.gesture.shown, header: false), Self.cell(line.effect.shown, header: false)]
                cells.forEach { SettingsExplainerHost.tag($0, line.explainer) }
                return cells
            })
        grid.rowSpacing = 4
        grid.columnSpacing = 14
        grid.column(at: 0).width = 128
        grid.column(at: 1).width = 300
        for column in 0..<2 { grid.column(at: column).xPlacement = .leading }
        grid.rowAlignment = .firstBaseline
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 6
        body.addArrangedSubview(grid)
        if let note {
            let noteLabel = NSTextField(wrappingLabelWithString: note.shown)
            noteLabel.font = SystemAppearancePolicy.font(relativeToBody: -3)
            noteLabel.textColor = .tertiaryLabelColor
            noteLabel.preferredMaxLayoutWidth = 442
            body.addArrangedSubview(noteLabel)
        }

        addArrangedSubview(toggle)
        addArrangedSubview(body)
        apply(animated: false)
    }
    required init?(coder: NSCoder) { nil }

    private static func cell(_ text: String, header: Bool) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = SystemAppearancePolicy.font(relativeToBody: header ? -3 : -2)
        field.textColor = header ? .tertiaryLabelColor : .secondaryLabelColor
        field.preferredMaxLayoutWidth = 300
        return field
    }

    @objc private func flip() {
        Self.expanded.toggle()
        apply(animated: true)
    }

    private func apply(animated: Bool) {
        let open = Self.expanded
        toggle.image = NSImage(systemSymbolName: open ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        body.isHidden = !open
        // 行高随之变化；整页的滚动区靠约束自己跟，这里只要求窗口重排一次。
        window?.layoutIfNeeded()
    }

    /// 测试与截图用：直接设成展开或合上。
    @MainActor
    static func setExpandedForDiagnostics(_ value: Bool) { expanded = value }
}
