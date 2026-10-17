// 设置窗口侧栏顶上的搜索（1.0.18 新表面稿第 2 节）。规则在 Core/SettingsSearch.swift，索引从哪来见
// App/SettingsSearchIndex.swift；这里是搜索框、结果行的样子、键盘、读屏，以及“跳到那一行”的滚动和亮一下。
//
// 交互（稿第 2 节 1–6 条）：⌘F 把焦点放进搜索框并全选；打一个字就出结果，结果替换侧栏的页列表；
// 焦点一直在搜索框里，↑↓ 在结果里走，Return 打开，Esc 第一次清空、第二次离开搜索框回到侧栏。
// 选中之后：侧栏不变（结果还在），右边换到那一页，那一行滚到内容区上三分之一处（calm，减少动态效果时
// 直接到），亮一下（强调色 18%，停 0.6 s 再 1.1 s 淡掉；减少动态效果时停 1.2 s 直接去掉），讲解带像点住
// 那一行一样演它。命中分段控件的某一段：那一段描一圈，讲解带演那一段。
// 读屏：搜索框叫“搜索设置”；结果变了，停止打字 0.5 s 后念一次“3 个结果”；结果行念“行名，页名页”。

import Cocoa

@MainActor
final class SettingsSearchSidebar: NSObject, NSSearchFieldDelegate {
    let field = NSSearchField()
    private(set) var collection = SettingsSearchCollection.empty
    private(set) var visiblePages: Set<String> = []
    /// nil：没在搜（侧栏放页列表）。
    private(set) var results: [SettingsSearchResult]?
    private(set) var query = ""
    /// 结果里选中的是第几条。
    var selected = 0
    /// 结果变了（要重读侧栏）；选中变了（只挪选中行）。
    var onResultsChanged: (() -> Void)?
    var onSelectionMoved: (() -> Void)?
    /// Return 或点了某条。
    var onCommit: ((SettingsSearchResult) -> Void)?
    /// 第二次 Esc：离开搜索框。
    var onLeave: (() -> Void)?
    private var announceWork: DispatchWorkItem?

    override init() {
        super.init()
        field.placeholderString = WSL10n.text("settings.search.placeholder", zh: "搜索")
        field.setAccessibilityLabel(WSL10n.text("settings.search.label", zh: "搜索设置"))
        field.controlSize = .large
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.recentsAutosaveName = nil
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    var isActive: Bool { results != nil }

    /// 语言切换后：占位字和读屏名重新取。
    func refreshCopy() {
        field.placeholderString = WSL10n.text("settings.search.placeholder", zh: "搜索")
        field.setAccessibilityLabel(WSL10n.text("settings.search.label", zh: "搜索设置"))
    }

    /// 页建好（或重建）之后重收索引；正在搜就按新索引重搜，选中尽量留在同一条。
    func reindex(pages: [(section: WindowShadeSettingsSection, root: NSView)], visible: [WindowShadeSettingsSection]) {
        collection = SettingsSearchCollection.collect(pages: pages)
        visiblePages = Set(visible.map { "\($0)" })
        guard isActive else { return }
        let previous = results?[safe: selected]?.entry.id
        results = collection.index.search(query, visiblePages: visiblePages)
        selected = results?.firstIndex { $0.entry.id == previous } ?? 0
        onResultsChanged?()
    }

    func view(for entry: SettingsSearchEntry) -> SettingsSearchCollection.Row? { collection.rows[entry.id] }

    func focusField(in window: NSWindow?) {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    // MARK: 打字与键盘

    func controlTextDidChange(_ obj: Notification) { update(field.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): move(1); return true
        case #selector(NSResponder.moveUp(_:)): move(-1); return true
        case #selector(NSResponder.insertNewline(_:)):
            if let result = results?[safe: selected] { onCommit?(result) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if field.stringValue.isEmpty { onLeave?() } else { clear() }
            return true
        default:
            return false
        }
    }

    func clear() {
        field.stringValue = ""
        update("")
    }

    private func update(_ text: String) {
        query = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        results = trimmed.isEmpty ? nil : collection.index.search(text, visiblePages: visiblePages)
        selected = 0
        onResultsChanged?()
        scheduleAnnouncement()
    }

    private func move(_ delta: Int) {
        guard let results, !results.isEmpty else { return }
        selected = (selected + delta + results.count) % results.count
        onSelectionMoved?()
    }

    /// 停止打字 0.5 s 后念一次结果数。
    private func scheduleAnnouncement() {
        announceWork?.cancel()
        guard let results else { return }
        let text = results.isEmpty ? WSL10n.text("settings.search.none", zh: "没有找到“%@”", query) : Self.countLine(results.count)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAccessibility.post(element: self.field, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        announceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    static func countLine(_ count: Int) -> String {
        count == 1 ? WSL10n.text("settings.search.countOne", zh: "1 个结果")
            : WSL10n.text("settings.search.count", zh: "%@ 个结果", String(count))
    }

    // MARK: 侧栏表格（结果态）

    /// 结果态时侧栏有几行：没结果是一行“没有找到”，有结果是一行结果数 + 每条一行。
    var tableRowCount: Int? {
        guard let results else { return nil }
        return results.isEmpty ? 1 : results.count + 1
    }

    func result(atRow row: Int) -> SettingsSearchResult? {
        guard let results, row >= 1 else { return nil }
        return results[safe: row - 1]
    }

    var selectedTableRow: Int? {
        guard let results, !results.isEmpty else { return nil }
        return selected + 1
    }

    func height(ofRow row: Int) -> CGFloat {
        guard let results else { return 30 }
        if results.isEmpty { return 56 }
        return row == 0 ? 24 : 40
    }

    func cell(forRow row: Int) -> NSView? {
        guard let results else { return nil }
        if results.isEmpty { return emptyCell() }
        if row == 0 { return headerCell(Self.countLine(results.count)) }
        guard let result = results[safe: row - 1] else { return nil }
        return resultCell(result)
    }

    private func headerCell(_ text: String) -> NSView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: text)
        label.font = SystemAppearancePolicy.font(relativeToBody: -2, weight: .semibold)
        label.textColor = .secondaryLabelColor
        place(label, in: cell, top: nil)
        return cell
    }

    private func emptyCell() -> NSView {
        let cell = NSTableCellView()
        let title = NSTextField(wrappingLabelWithString: WSL10n.text("settings.search.none", zh: "没有找到“%@”", query))
        title.font = SystemAppearancePolicy.font(relativeToBody: -1, weight: .semibold)
        title.maximumNumberOfLines = 1
        title.lineBreakMode = .byTruncatingMiddle
        let hint = NSTextField(wrappingLabelWithString: WSL10n.text("settings.search.tryAnother", zh: "换个说法试试，比如“收起”“刘海”"))
        hint.font = SystemAppearancePolicy.font(relativeToBody: -2)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        let stack = NSStackView(views: [title, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        place(stack, in: cell, top: 6)
        return cell
    }

    private func resultCell(_ result: SettingsSearchResult) -> NSView {
        let cell = NSTableCellView()
        let name = NSTextField(labelWithString: "")
        name.attributedStringValue = Self.highlighted(result.entry.name.shown, range: result.highlight)
        name.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: Self.detailLine(result))
        detail.font = SystemAppearancePolicy.font(relativeToBody: -3)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [name, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        place(stack, in: cell, top: nil)
        cell.textField = name
        cell.setAccessibilityLabel(WSL10n.text("settings.search.resultA11y", zh: "%@，%@页",
                                               result.entry.name.shown, result.entry.pageName.shown))
        return cell
    }

    /// 结果第二行：“页 › 命中的选项”；靠同义词找到的写“页 · 就是你说的“隐藏””。
    static func detailLine(_ result: SettingsSearchResult) -> String {
        let page = result.entry.pageName.shown
        if let option = result.option, let text = result.entry.options[safe: option] {
            return page + " › " + text.shown
        }
        if case .synonym(let word) = result.reason {
            return page + " · " + WSL10n.text("settings.search.sameAs", zh: "就是你说的“%@”", word)
        }
        return page
    }

    /// 命中的字：强调色底；增强对比度时再加下划线（不只靠底色）。
    static func highlighted(_ text: String, range: NSRange?) -> NSAttributedString {
        let font = SystemAppearancePolicy.font(relativeToBody: -1)
        let string = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        if let range, NSMaxRange(range) <= (text as NSString).length {
            var marked: [NSAttributedString.Key: Any] = [
                .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.25),
                .font: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask),
            ]
            if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
                marked[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            string.addAttributes(marked, range: range)
        }
        return string
    }

    private func place(_ view: NSView, in cell: NSView, top: CGFloat?) {
        view.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(view)
        var constraints = [
            view.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            view.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6),
        ]
        if let top { constraints.append(view.topAnchor.constraint(equalTo: cell.topAnchor, constant: top)) }
        else { constraints.append(view.centerYAnchor.constraint(equalTo: cell.centerYAnchor)) }
        NSLayoutConstraint.activate(constraints)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}

/// 跳到那一行：滚到内容区上三分之一处、亮一下、分段描一圈。
@MainActor
enum SettingsSearchReveal {
    /// 滚动：calm 弹簧；减少动态效果时直接到。
    static func scroll(_ scroll: NSScrollView, toShow row: NSView) {
        guard let document = scroll.documentView else { return }
        document.layoutSubtreeIfNeeded()
        let frame = row.convert(row.bounds, to: document)
        let visible = scroll.contentView.bounds.height
        let top = document.isFlipped ? frame.minY : document.bounds.height - frame.maxY
        let maxOffset = max(0, document.bounds.height - visible)
        var targetTop = min(max(0, top - visible / 3), maxOffset)
        if !document.isFlipped { targetTop = maxOffset - targetTop }
        let target = NSPoint(x: scroll.contentView.bounds.origin.x, y: targetTop)
        if Motion.reduced {
            scroll.contentView.scroll(to: target)
            scroll.reflectScrolledClipView(scroll.contentView)
        } else {
            SettingsSearchScroller.shared.animate(scroll, to: target)
        }
    }

    /// 亮一下：强调色 18% 的底，停 0.6 s 再 1.1 s 淡掉；减少动态效果时停 1.2 s 直接去掉。
    static func flash(_ row: NSView, option: (control: NSControl, item: Int)?) {
        let fill = SettingsSearchFlash(frame: row.bounds.insetBy(dx: -8, dy: 0))
        fill.autoresizingMask = [.width, .height]
        fill.fill = true
        row.addSubview(fill, positioned: .above, relativeTo: nil)
        var views: [NSView] = [fill]
        if let option {
            let ring = SettingsSearchFlash(frame: rect(of: option.item, in: option.control).insetBy(dx: -2, dy: -2))
            ring.fill = false
            option.control.superview?.addSubview(ring, positioned: .above, relativeTo: option.control)
            views.append(ring)
        }
        let reduced = Motion.reduced
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduced ? 1.2 : 0.6)) {
            guard !reduced else { views.forEach { $0.removeFromSuperview() }; return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 1.1
                views.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: {
                MainActor.assumeIsolated { views.forEach { $0.removeFromSuperview() } }
            })
        }
    }

    /// 分段控件某一段（或整个弹出菜单）在它父视图里的位置。
    private static func rect(of item: Int, in control: NSControl) -> NSRect {
        guard let segmented = control as? NSSegmentedControl, segmented.segmentCount > 0 else { return control.frame }
        let count = segmented.segmentCount
        let fixed = (0..<count).map { segmented.width(forSegment: $0) }
        let free = fixed.filter { $0 <= 0 }.count
        let remaining = max(0, segmented.bounds.width - fixed.filter { $0 > 0 }.reduce(0, +))
        var x: CGFloat = 0
        var width: CGFloat = 0
        for i in 0..<count {
            width = fixed[i] > 0 ? fixed[i] : remaining / CGFloat(max(free, 1))
            if i == item { break }
            x += width
        }
        let local = NSRect(x: x, y: 0, width: width, height: segmented.bounds.height)
        return segmented.convert(local, to: segmented.superview)
    }
}

/// 亮一下用的底 / 描边：不接鼠标。
final class SettingsSearchFlash: NSView {
    var fill = true
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        if fill {
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            path.fill()
        } else {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
}

/// 按 calm 弹簧把内容区滚到目标处（屏幕刷新驱动；新目标接着当前位置走，不跳）。
@MainActor
final class SettingsSearchScroller: NSObject {
    static let shared = SettingsSearchScroller()
    private weak var scroll: NSScrollView?
    private var link: CADisplayLink?
    private var start = 0.0
    private var from = NSPoint.zero
    private var target = NSPoint.zero
    private let spring = FlickSpring(dampingRatio: MotionSpring.calm.dampingRatio, response: MotionSpring.calm.response)
    private let duration = ExplainerTiming.settlingTime(of: .calm)

    func animate(_ scroll: NSScrollView, to target: NSPoint) {
        link?.invalidate()
        self.scroll = scroll
        from = scroll.contentView.bounds.origin
        self.target = target
        start = CACurrentMediaTime()
        let link = scroll.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let scroll else { link.invalidate(); return }
        let t = CACurrentMediaTime() - start
        let done = t >= duration
        let offset = done ? 0 : spring.state(displacement: 1, velocity: 0, at: t).x
        let point = NSPoint(x: target.x + (from.x - target.x) * offset, y: target.y + (from.y - target.y) * offset)
        scroll.contentView.scroll(to: point)
        scroll.reflectScrolledClipView(scroll.contentView)
        if done {
            link.invalidate()
            self.link = nil
        }
    }
}
