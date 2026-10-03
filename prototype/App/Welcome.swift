// 欢迎使用 WindowShade：首次打开时出现、菜单里随时能再打开（“欢迎使用 Macintosh”的现代版）。
// 三步：一句话说清它是什么（配一段短动画）；问“你之前常用哪个？”（存进 SwitcherOrigin，设置里能改）；授权。
// 其余的手势不在这里教，交给刘海在他卡住时教（docs/direction.md）。
// 动画全是 Core Animation 图层（渲染进程播，不占主线程），窗口看不见时停下、看不见时也不重建。“减少动态效果”打开时不动，摆出最能说明问题的那一帧。
// 没有刘海的屏（外接屏、没有刘海的 Mac、“避开刘海”模式）上舞台不画刘海，开口时是浮着的胶囊（design-system V1、§8 问题 2）。
// 最后一步是真实的授权行（沿用原来的刷新逻辑），关窗口也算看过，下次不再自动弹出。
// 从“下载”等地方直接打开时，三步之前多一步“放进‘应用程序’文件夹”（UpdaterMove，不算在三步里）：放进去以后才能在菜单里更新。

import Cocoa

/// 截图核对用（--settings-shots）：这一张摆成什么样，只画出来，不存、不循环播。平常不传。
struct WelcomePreview {
    /// 有动画的一步摆出一轮里的这一刻（和“减少动态效果”同一条路径）。
    var moment: Double? = nil
    /// 问来处的一步画成这个答案。
    var origin: SwitcherOrigin? = nil
    /// 舞台当作有刘海 / 没有刘海的屏来画；nil 是看窗口所在的那块屏。
    var notched: Bool? = nil
}

@MainActor
final class WelcomeView: NSView {
    struct Page {
        let title: String
        let lede: String
        /// 舞台上那段动画演的是什么（VoiceOver 读它）；没有动画的一步是 nil，舞台不出现。
        var picture: String? = nil
    }
    static let pages: [Page] = [
        // 一句话（direction.md）：先说熟悉的操作照样有，再说它替你做什么。候选见 docs/welcome.md，由 Aaron 挑。
        Page(title: "欢迎使用 WindowShade",
             lede: "你熟悉的操作 Mac 上照样有，卡住时刘海告诉你怎么做。",
             picture: "动画：按了 ⌃C 没有反应，刘海展开说“Mac 上拷贝按 ⌘C”；按了 ⌘C，刘海收回。"),
        Page(title: "你之前常用哪个？", lede: "刘海会按你原来的习惯来提示。设置里随时能改。"),
        Page(title: "最后一步：授权", lede: "辅助功能让 WindowShade 能移动窗口，屏幕录制让它能显示实时画面。两项都打开就能用了。"),
    ]
    /// 问来处的那一步。
    static let originPage = 1
    /// 授权那一步（缺权限的提醒直接打开到这里）。
    static var permissionPage: Int { pages.count - 1 }

    var onFinish: (() -> Void)?
    var onLater: (() -> Void)?
    /// 翻了一页：AppDelegate 据此决定授权页的每秒刷新开不开（只在停在授权页时开）。
    var onPageChange: (() -> Void)?
    /// 两项授权都有了没有：最后一页“开始使用”只在都有时能点，没有时旁边给“稍后再说”。
    var permissionsGranted: () -> Bool = { true }
    /// 最后一页的授权区：AppDelegate 往里填授权行、进度字（沿用原来的刷新逻辑）。
    let permissionStack = NSStackView()
    let progressLabel = NSTextField(labelWithString: "")
    /// 授权行现在画的是哪种状态（辅助功能、屏幕录制）；没变就不拆了重画。
    var shownGrants: [Bool]?
    /// 装好新版本后系统要他重新打开两项授权：授权页换成“再打开一次这两项”那组文案。
    var permissionsAgain = false { didSet { if index == Self.permissionPage && !onMoveStep { show(index) } } }

    private let stage = WelcomeStage()
    private let choices = WelcomeChoices()
    private let eyebrow = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let lede = NSTextField(wrappingLabelWithString: "")
    private let dots = WelcomeDots()
    private let skip = NSButton(title: "跳过", target: nil, action: nil)
    private let back = NSButton(title: "上一步", target: nil, action: nil)
    let next = NSButton(title: "继续", target: nil, action: nil)
    private let permissionBox = NSStackView()
    private(set) var index = 0
    /// 三步之前那一步：放进“应用程序”文件夹。AppDelegate 在从第一步打开时交进来；nil 就没有这一步。
    private var moveStep: UpdaterMoveStep?
    private(set) var onMoveStep = false
    private var moveFailed = false
    private let moveBox = NSStackView()
    private let moveIcon = NSImageView()
    /// 截图核对用：第二步画成这个答案（只画出来，不存）；平常是 nil，画的是存着的答案。
    private var previewOrigin: SwitcherOrigin?

    static let size = NSSize(width: 720, height: 596)

    override init(frame: NSRect) {
        super.init(frame: frame)
        let padding: CGFloat = 26
        let stageWidth = Self.size.width - padding * 2
        let stageHeight = (stageWidth * 9 / 16).rounded()
        stage.frame = NSRect(x: padding, y: Self.size.height - 40 - stageHeight, width: stageWidth, height: stageHeight)
        addSubview(stage)

        permissionBox.orientation = .vertical
        permissionBox.alignment = .centerX
        permissionBox.spacing = 12
        progressLabel.font = .systemFont(ofSize: 13, weight: .medium)
        permissionStack.orientation = .vertical
        permissionStack.alignment = .centerX
        permissionBox.addArrangedSubview(progressLabel)
        permissionBox.addArrangedSubview(permissionStack)
        permissionBox.isHidden = true
        permissionBox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(permissionBox)
        // 授权卡片、三个选项都放在舞台那块区域的正中（卡片宽度由 AppDelegate 定）。
        choices.isHidden = true
        choices.translatesAutoresizingMaskIntoConstraints = false
        choices.setAccessibilityLabel(Self.pages[Self.originPage].title)
        choices.onPick = { [weak self] origin in
            // 点了就存（关窗口、跳过都不丢）；和原来一样时 SwitcherOrigin 自己不发通知。
            self?.previewOrigin = nil
            SwitcherOrigin.current = origin
            self?.showOrigin()
        }
        addSubview(choices)
        // 放进“应用程序”那一步：这个 App 的图标 → “应用程序”文件夹的图标，都是系统给的图，不另画。
        moveIcon.image = NSApp.applicationIconImage
        moveIcon.wantsLayer = true
        let folder = NSImageView(image: NSWorkspace.shared.icon(forFile: "/Applications"))
        let arrow = NSImageView(image: NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil) ?? NSImage())
        arrow.symbolConfiguration = .init(pointSize: 22, weight: .medium)
        arrow.contentTintColor = .tertiaryLabelColor
        for icon in [moveIcon, folder] {
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.widthAnchor.constraint(equalToConstant: 112).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 112).isActive = true
        }
        moveBox.orientation = .horizontal
        moveBox.alignment = .centerY
        moveBox.spacing = 28
        [moveIcon, arrow, folder].forEach(moveBox.addArrangedSubview)
        moveBox.setAccessibilityElement(false)
        moveBox.isHidden = true
        moveBox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(moveBox)
        for box in [permissionBox, choices, moveBox] as [NSView] {
            NSLayoutConstraint.activate([
                box.centerXAnchor.constraint(equalTo: leadingAnchor, constant: stage.frame.midX),
                box.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -stage.frame.midY),
            ])
        }

        eyebrow.font = .systemFont(ofSize: 12)
        eyebrow.textColor = .tertiaryLabelColor
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        lede.font = .systemFont(ofSize: 14)
        lede.textColor = .secondaryLabelColor
        lede.maximumNumberOfLines = 3
        let top = stage.frame.minY - 20
        eyebrow.frame = NSRect(x: padding, y: top - 16, width: stageWidth, height: 16)
        titleLabel.frame = NSRect(x: padding, y: top - 50, width: stageWidth, height: 30)
        // 三行高（授权页在标准账户、更新后要重新授权时会到三行）；字从上往下排，一两行时位置不变。
        lede.frame = NSRect(x: padding, y: top - 114, width: stageWidth, height: 60)
        [eyebrow, titleLabel, lede].forEach(addSubview)

        dots.frame = NSRect(x: padding, y: 24, width: 200, height: 16)
        dots.count = Self.pages.count
        dots.onSelect = { [weak self] in self?.show($0) }
        addSubview(dots)

        for (button, action) in [(skip, #selector(skipPressed)), (back, #selector(backPressed)), (next, #selector(nextPressed))] {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
            button.controlSize = .large
            addSubview(button)
        }
        skip.isBordered = false
        skip.contentTintColor = .secondaryLabelColor
        next.keyEquivalent = "\r"
        // Tab 顺序：这一页 → 三个选项（只在第二步看得见）→ 上一步、跳过、继续（打开“键盘导航”时）→ 回到这一页。
        let loop: [NSView] = [self] + choices.items + [back, skip, next]
        let following: [NSView] = Array(loop.dropFirst()) + [self]
        for (view, after) in zip(loop, following) { view.nextKeyView = after }
        // 设置里改了、刘海问过之后他点了：第二步跟着变。
        NotificationCenter.default.addObserver(self, selector: #selector(originDidChange),
                                               name: SwitcherOrigin.didChangeNotification, object: nil)
        layoutButtons()
        show(0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func layoutButtons() {
        var x = Self.size.width - 26
        next.sizeToFit()
        // 无边框的“跳过”比有边框的按钮矮，按中线对齐，字才在同一条线上。
        let midY = 18 + next.frame.height / 2
        for button in [next, back, skip] where !button.isHidden {
            button.sizeToFit()
            let width = max(button.frame.width, button === next ? 96 : 72)
            x -= width
            button.frame = NSRect(x: x, y: (midY - button.frame.height / 2).rounded(), width: width, height: button.frame.height)
            x -= 8
        }
    }

    /// preview：截图核对用（--settings-shots），摆出静帧、画成某个答案、当作有没有刘海的屏；平常不传，照常循环播、画存着的答案。
    func show(_ page: Int, preview: WelcomePreview? = nil) {
        index = max(0, min(Self.pages.count - 1, page))
        onMoveStep = false
        moveBox.isHidden = true
        dots.isHidden = false
        [skip, next].forEach { $0.isEnabled = true }
        previewOrigin = preview?.origin
        let item = Self.pages[index]
        eyebrow.stringValue = "\(index + 1) / \(Self.pages.count)"
        titleLabel.stringValue = item.title
        lede.stringValue = item.lede
        if index == Self.permissionPage {
            if permissionsAgain {
                titleLabel.stringValue = UpdateCopy.permissionsAgainTitle
                lede.stringValue = UpdateCopy.permissionsAgainLead + UpdateCopy.permissionsStuckHint
            }
            // 标准账户打开这两项要管理员的名字和密码：先说一声，免得他以为自己点错了。
            if UpdaterMove.shared.isStandardAccount { lede.stringValue += "\n" + UpdateCopy.standardAccount }
        }
        dots.current = index
        let last = index == Self.permissionPage
        back.isHidden = index == 0
        next.title = last ? "开始使用" : "继续"
        // 舞台只给有动画的那一步；第二步是三个选项，最后一步是授权行，都摆在舞台那块区域。
        stage.isHidden = item.picture == nil
        // 焦点还在某个选项上就离开了第二步：交回这一页，← → 接着翻页，不会在看不见的选项之间换答案。
        if index != Self.originPage, let focused = window?.firstResponder as? NSView, focused.isDescendant(of: choices) {
            window?.makeFirstResponder(self)
        }
        choices.isHidden = index != Self.originPage
        permissionBox.isHidden = !last
        if item.picture != nil { stage.play(index, stillAt: preview?.moment, notched: preview?.notched) } else { stage.stop() }
        stage.setAccessibilityLabel(item.picture)
        showOrigin()
        NSAccessibility.post(element: self, notification: .layoutChanged)
        onPageChange?()
    }

    /// 三步之前那一步：放进“应用程序”文件夹。没有这一步（已经在里面、他跳过过）就直接从第一步开始。
    func showMove(_ step: UpdaterMoveStep?) {
        moveStep = step
        guard let step else { show(0); return }
        onMoveStep = true
        moveFailed = false
        eyebrow.stringValue = ""
        titleLabel.stringValue = step.title
        lede.stringValue = step.lead + (step.note ?? "")
        stage.stop()
        stage.isHidden = true
        choices.isHidden = true
        permissionBox.isHidden = true
        moveBox.isHidden = false
        dots.isHidden = true
        back.isHidden = true
        skip.isHidden = false
        skip.title = step.secondaryTitle
        next.title = step.primaryTitle
        [skip, next].forEach { $0.isEnabled = true }
        resetMoveIcon()
        layoutButtons()
        NSAccessibility.post(element: self, notification: .layoutChanged)
        onPageChange?()
    }

    private func pressMovePrimary() {
        if moveFailed {
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            return
        }
        [skip, next].forEach { $0.isEnabled = false }
        glideIconIntoFolder()
        UpdaterMove.shared.performPrimary { [weak self] result in
            // .relaunching：这个进程马上退出，新位置那一份接着从第一步走。
            guard let self, case .failed = result else { return }
            self.moveFailed = true
            self.resetMoveIcon()
            self.lede.stringValue = UpdateCopy.moveFailed
            self.next.title = UpdateCopy.showInFinder
            self.skip.title = "继续"
            [self.skip, self.next].forEach { $0.isEnabled = true }
            self.layoutButtons()
            NSAccessibility.post(element: self.lede, notification: .valueChanged)
        }
    }

    /// 按下去就给回应：图标朝文件夹滑过去、变小、变淡（移动要一两秒）。“减少动态效果”时只变淡。
    private func glideIconIntoFolder() {
        guard let layer = moveIcon.layer else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduce ? 0.2 : 0.45)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1))
        if !reduce {
            // 图层的锚点在左下角：缩小时补回一半的差，看起来是绕图标中心缩。
            let travel = moveBox.arrangedSubviews.last.map { $0.frame.midX - moveIcon.frame.midX } ?? 0
            let scale: CGFloat = 0.55
            let inset = moveIcon.bounds.width * (1 - scale) / 2
            var t = CATransform3DMakeTranslation(travel + inset, moveIcon.bounds.height * (1 - scale) / 2, 0)
            t = CATransform3DScale(t, scale, scale, 1)
            layer.transform = t
        }
        layer.opacity = 0.25
        CATransaction.commit()
    }

    private func resetMoveIcon() {
        guard let layer = moveIcon.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        layer.opacity = 1
        CATransaction.commit()
    }

    /// 第二步的选中状态和“继续”能不能点。
    private func showOrigin() {
        choices.selected = previewOrigin ?? SwitcherOrigin.current
        refreshButtons()
    }

    @objc private func originDidChange() {
        guard previewOrigin == nil else { return }
        showOrigin()
    }

    /// 第二步：选了才能“继续”，不想答就“跳过”（算没答）。最后一页：没授权时“跳过”的位置换成“稍后再说”，
    /// “开始使用”等授权后才能点。前几页用不着查授权。
    func refreshButtons() {
        guard !onMoveStep else { return }
        let last = index == Self.permissionPage
        let granted = last && permissionsGranted()
        skip.title = last ? "稍后再说" : "跳过"
        skip.isHidden = granted
        if last {
            next.isEnabled = granted
        } else {
            next.isEnabled = index != Self.originPage || choices.selected.isAnswered
        }
        layoutButtons()
    }

    @objc private func nextPressed() {
        if onMoveStep { pressMovePrimary(); return }
        if index == Self.permissionPage { onFinish?() } else { show(index + 1) }
    }
    @objc private func backPressed() { show(index - 1) }
    @objc private func skipPressed() {
        if onMoveStep {
            // 跳过就不再在欢迎窗口里问（没能移过去时的“继续”不算跳过）；更新小窗里位置不对时还会再给这一步。
            if !moveFailed { UpdaterMove.shared.declineForWelcome() }
            show(0)
            return
        }
        if index == Self.permissionPage { onLater?() } else { show(Self.permissionPage) }
    }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if onMoveStep {
            // 这一步的 → 就是“跳过”；← 没有上一步。
            if event.keyCode == 124, skip.isEnabled { skipPressed() } else if event.keyCode != 123 { super.keyDown(with: event) }
            return
        }
        switch event.keyCode {
        case 124: show(index + 1)
        case 123: show(index - 1)
        default: super.keyDown(with: event)
        }
    }
}

// MARK: - 页码点

final class WelcomeDots: NSView {
    var count = 0 { didSet { needsDisplay = true } }
    var current = 0 { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?
    private func rects() -> [NSRect] {
        var x: CGFloat = 0
        return (0..<count).map { i in
            let w: CGFloat = i == current ? 18 : 7
            defer { x += w + 7 }
            return NSRect(x: x, y: (bounds.height - 7) / 2, width: w, height: 7)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        for (i, rect) in rects().enumerated() {
            (i == current ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor.withAlphaComponent(0.5)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5).fill()
        }
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = rects().firstIndex(where: { $0.insetBy(dx: -4, dy: -6).contains(p) }) { onSelect?(i) }
    }
}

// MARK: - 第二步：三个选项

/// “你之前常用哪个？”的三个选项，一组单选。点了就存；键盘上 Tab 进来、← → 换、空格选（和系统的单选组一样）。
final class WelcomeChoices: NSView {
    let items = SwitcherOrigin.answers.map { WelcomeChoice(origin: $0) }
    var onPick: ((SwitcherOrigin) -> Void)?
    var selected: SwitcherOrigin = .unanswered {
        didSet {
            guard selected != oldValue else { return }
            for item in items { item.isSelected = item.origin == selected }
        }
    }

    static let itemSize = NSSize(width: 180, height: 140)
    static let spacing: CGFloat = 20

    override init(frame: NSRect) {
        super.init(frame: frame)
        let size = Self.itemSize
        for (i, item) in items.enumerated() {
            item.frame = NSRect(x: CGFloat(i) * (size.width + Self.spacing), y: 0, width: size.width, height: size.height)
            item.onPick = { [weak self, weak item] origin in
                guard let self else { return }
                // 焦点已经在某个选项上（用键盘进来过）时，点了哪个焦点跟到哪个，焦点和选中还是同一个，← → 从这里接着走；
                // 焦点不在选项上时点了不接焦点，← → 照常翻页。
                if let item, let focused = self.window?.firstResponder as? NSView, focused !== item, focused.isDescendant(of: self) {
                    self.window?.makeFirstResponder(item)
                }
                self.onPick?(origin)
            }
            item.onStep = { [weak self] origin, step in self?.step(from: origin, by: step) }
            addSubview(item)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        // 增强对比度打开、关掉时，选项的边跟着变。
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsDidChange),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        let count = CGFloat(items.count)
        return NSSize(width: count * Self.itemSize.width + (count - 1) * Self.spacing, height: Self.itemSize.height)
    }

    /// ← → 在选项之间走一格，焦点和选中一起挪（到头不绕回）。
    private func step(from origin: SwitcherOrigin, by step: Int) {
        guard let at = items.firstIndex(where: { $0.origin == origin }) else { return }
        let target = items[max(0, min(items.count - 1, at + step))]
        guard target.origin != origin else { return }
        window?.makeFirstResponder(target)
        onPick?(target.origin)
    }

    @objc private func displayOptionsDidChange() {
        for item in items { item.needsDisplay = true }
    }
}

/// 一个选项：图标、名字；选中时加一圈强调色的边和一个勾（不只靠颜色）。VoiceOver 里是单选按钮。
final class WelcomeChoice: NSView {
    let origin: SwitcherOrigin
    var onPick: ((SwitcherOrigin) -> Void)?
    var onStep: ((SwitcherOrigin, Int) -> Void)?
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            refresh()
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }
    private var isPressed = false { didSet { needsDisplay = true } }
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let check = NSImageView()

    init(origin: SwitcherOrigin) {
        self.origin = origin
        super.init(frame: NSRect(origin: .zero, size: WelcomeChoices.itemSize))
        wantsLayer = true
        let size = WelcomeChoices.itemSize
        let symbol: String
        switch origin {
        case .windows: symbol = "display"  // 不用 “pc”：它屏幕上画着一张哭脸
        case .ipad: symbol = "ipad.landscape"
        case .mac, .unanswered: symbol = "macbook"
        }
        icon.image = (NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: nil))?
            .withSymbolConfiguration(.init(pointSize: 40, weight: .regular))
        icon.imageScaling = .scaleNone
        icon.frame = NSRect(x: 0, y: 58, width: size.width, height: 52)
        label.stringValue = origin.title ?? ""
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.alignment = .center
        label.frame = NSRect(x: 8, y: 24, width: size.width - 16, height: 20)
        check.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        check.contentTintColor = .controlAccentColor
        check.frame = NSRect(x: size.width - 12 - 18, y: size.height - 12 - 18, width: 18, height: 18)
        for view in [icon, label, check] as [NSView] {
            view.setAccessibilityElement(false)
            addSubview(view)
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refresh() {
        icon.contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
        check.isHidden = !isSelected
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let layer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let fill = SystemAppearancePolicy.groupBoxFill()
            layer.backgroundColor = (isPressed ? fill.blended(withFraction: 0.08, of: .labelColor) ?? fill : fill).cgColor
            layer.cornerRadius = SystemCornerRadius.card
            layer.cornerCurve = .continuous
            if isSelected {
                layer.borderWidth = 2
                layer.borderColor = NSColor.controlAccentColor.cgColor
            } else if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
                layer.borderWidth = 1
                layer.borderColor = NSColor.labelColor.cgColor
            } else {
                layer.borderWidth = 0
            }
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // 点一下选中；按下时暗一点，移出去松手不算。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { isPressed = true }
    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if inside { onPick?(origin) }
    }

    // 键盘：Tab 进来有焦点环；空格选中，← → 换一个。用鼠标点不接焦点，← → 还是翻页。
    // 按下鼠标的那一下说“不接”：窗口就不去挪焦点，焦点留在这一页。（不能在 becomeFirstResponder 里拒绝：
    // 窗口已经让这一页交出了焦点，被拒后焦点落到窗口自己身上，← → 没人接。）Tab、← → 走的是键盘事件，照样能进来。
    override var acceptsFirstResponder: Bool { NSApp.currentEvent?.type != .leftMouseDown }
    override var canBecomeKeyView: Bool { !isHiddenOrHasHiddenAncestor }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: SystemCornerRadius.card, yRadius: SystemCornerRadius.card).fill()
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: onPick?(origin)
        case 123: onStep?(origin, -1)
        case 124: onStep?(origin, 1)
        default: super.keyDown(with: event)
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioButton }
    override func accessibilityLabel() -> String? { origin.title }
    override func accessibilityValue() -> Any? { NSNumber(value: isSelected ? 1 : 0) }
    override func accessibilityPerformPress() -> Bool {
        onPick?(origin)
        return true
    }
}

// MARK: - 舞台：一块迷你桌面

final class WelcomeStage: NSView {
    private var scene: CALayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        // 中途打开或关掉“减少动态效果”：当页重摆（动起来，或停在那一帧）。
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(replay),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        replay()
    }

    private var currentIndex: Int?
    private var currentMoment: Double?
    /// 截图核对用：当作有没有刘海的屏来画；nil 是看窗口所在的那块屏。
    private var forcedNotch: Bool?
    /// 现在这幕是按有刘海还是没有刘海画的（没建场景时是 nil）。
    private var builtNotched: Bool?
    /// 窗口看不见了、图层已经拆掉：这段时间里切外观、改辅助设置、翻页都只记下该播哪一步，不在看不见的窗口里建循环动画
    /// （点了“开始使用”后窗口一直留着，到退出才释放）。又看得见时 occlusionDidChange 从头播。
    private var parked = false

    // 窗口收起来、整个被挡住或在别的桌面上时，循环动画停下（拆掉图层）；又看得见了从头播。
    // 窗口挪到另一块屏、有没有刘海变了：按新的屏重画。
    private weak var observedWindow: NSWindow?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observedWindow {
            NotificationCenter.default.removeObserver(self, name: nil, object: observedWindow)
        }
        observedWindow = window
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionDidChange),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(screenDidChange),
                                                   name: NSWindow.didChangeScreenNotification, object: window)
        }
    }
    @objc private func occlusionDidChange() {
        guard let window else { return }
        if window.occlusionState.contains(.visible) {
            guard parked else { return }
            parked = false
            replay()
        } else if !parked {
            parked = true
            scene?.removeFromSuperlayer()
            scene = nil
            builtNotched = nil
        }
    }
    @objc private func screenDidChange() {
        guard forcedNotch == nil, let built = builtNotched, built != screenHasNotch else { return }
        replay()
    }

    /// 窗口所在那块屏有没有刘海（公开接口：顶上的安全区）。外接屏、没有刘海的 Mac、“避开刘海”模式都没有。
    private var screenHasNotch: Bool {
        ((window?.screen ?? NSScreen.main)?.safeAreaInsets.top ?? 0) > 0
    }

    @objc private func replay() {
        if let current = currentIndex { play(current, stillAt: currentMoment, notched: forcedNotch) }
    }

    func stop() {
        scene?.removeFromSuperlayer()
        scene = nil
        currentIndex = nil
        currentMoment = nil
        forcedNotch = nil
        builtNotched = nil
    }

    /// moment：截图核对用，摆出一轮里那一刻的静帧（和“减少动态效果”同一条路径）；平常是 nil，照常循环播。
    /// notched：截图核对用，当作有 / 没有刘海的屏来画；平常是 nil，看窗口所在的那块屏。
    func play(_ index: Int, stillAt moment: Double? = nil, notched forced: Bool? = nil) {
        stop()
        currentIndex = index
        currentMoment = moment
        forcedNotch = forced
        // 窗口看不见时不建循环动画；静帧没有动画，照样摆（截图核对不受遮挡影响）。
        guard !parked || moment != nil else { return }
        let notched = forced ?? screenHasNotch
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let builder = WelcomeScene(size: bounds.size, dark: dark, scale: window?.backingScaleFactor ?? 2,
                                   still: moment != nil || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                                   notched: notched)
        builder.stillOverride = moment
        builder.build(index)
        layer?.addSublayer(builder.root)
        scene = builder.root
        builtNotched = notched
    }
}

// MARK: - 动画

/// 迷你桌面的零件和那一段动画。坐标用“占舞台的百分比、从左上角量”，单位 u = 舞台宽度的百分之一（和小样的 cqw 一样）。
/// 关键帧的时间是一轮里的比例，整轮循环播放；减少动态效果时只摆出 still 那一刻的样子。
@MainActor
final class WelcomeScene {
    let root = CALayer()
    let size: CGSize
    let dark: Bool
    let scale: CGFloat
    let still: Bool
    /// 这块屏有没有刘海：没有就不画刘海，开口时是浮着的胶囊。
    let notched: Bool
    private var cycle: CFTimeInterval = 8
    private var stillAt: Double = 0.5
    /// 截图核对用：静帧摆出这一刻（一轮里的比例），不用每页自己的 stillAt。
    var stillOverride: Double?
    private var u: CGFloat { size.width / 100 }
    /// 没有刘海时，胶囊顶上离屏幕顶边的缝（和隐形刘海的胶囊一样，在菜单栏里上下各缩一点）。
    private var floatGap: CGFloat { 0.6 * u }

    init(size: CGSize, dark: Bool, scale: CGFloat, still: Bool, notched: Bool = true) {
        self.size = size
        self.dark = dark
        self.scale = scale
        self.still = still
        self.notched = notched
        root.frame = CGRect(origin: .zero, size: size)
        let wall = CAGradientLayer()
        wall.frame = root.bounds
        wall.colors = (dark ? [0x253e72, 0x1f2230, 0x4e2a52] : [0xbcd3ff, 0xdfe4ef, 0xf3cdea]).map { Self.color($0).cgColor }
        wall.startPoint = CGPoint(x: 0, y: 1)
        wall.endPoint = CGPoint(x: 1, y: 0)
        root.addSublayer(wall)
        let warm = CAGradientLayer()
        warm.type = .radial
        warm.frame = CGRect(x: size.width * 0.3, y: -size.height * 0.4, width: size.width, height: size.height)
        warm.colors = [Self.color(dark ? 0x5c3a22 : 0xffd9b8, alpha: 0.85).cgColor, Self.color(0, alpha: 0).cgColor]
        warm.startPoint = CGPoint(x: 0.5, y: 0.5)
        warm.endPoint = CGPoint(x: 1, y: 1)
        root.addSublayer(warm)
    }

    static func color(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    // MARK: 坐标

    /// 左上角量的百分比 → 图层坐标（左下角原点）的矩形。
    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        let width = size.width * w / 100, height = size.height * h / 100
        return CGRect(x: size.width * x / 100, y: size.height - size.height * y / 100 - height, width: width, height: height)
    }

    // MARK: 零件

    private var winFill: NSColor { dark ? Self.color(0x2c2c30) : .white }
    private var barFill: NSColor { dark ? Self.color(0x38383d) : Self.color(0xededf0) }
    private var textFill: NSColor { dark ? Self.color(0x55555c) : Self.color(0xc9c9cf) }
    private var ink: NSColor { dark ? Self.color(0xf5f5f7) : Self.color(0x1d1d1f) }
    private var barHeight: CGFloat { 3.8 * u }
    /// 窗口里几行字的长短（占可写宽度的比例），和选中那一行的位置共用。
    private static let lineWidths: [CGFloat] = [1, 0.78, 0.88, 0.62, 0.84, 0.7]

    private func text(_ string: String, size fontSize: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = string
        layer.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        layer.fontSize = fontSize
        layer.foregroundColor = color.cgColor
        layer.contentsScale = scale
        layer.alignmentMode = .center
        layer.truncationMode = .end
        return layer
    }

    private func menubar(_ app: String) {
        let bar = CALayer()
        bar.frame = CGRect(x: 0, y: size.height - 4.6 * u, width: size.width, height: 4.6 * u)
        bar.backgroundColor = (dark ? Self.color(0x18181c, alpha: 0.55) : Self.color(0xffffff, alpha: 0.55)).cgColor
        root.addSublayer(bar)
        let name = text("\(app)    文件    编辑    窗口", size: 1.6 * u, weight: .semibold, color: ink)
        name.alignmentMode = .left
        name.frame = CGRect(x: 2.4 * u, y: (4.6 * u - 2.2 * u) / 2, width: 40 * u, height: 2.2 * u)
        bar.addSublayer(name)
    }

    /// 刘海：纯黑，顶边锚定（展开时从刘海本身往下长），底下两个角是连续曲线。
    /// 没有刘海的屏：平时什么都没有（隐形刘海看不见）；开口时是菜单栏正中浮出来的一颗胶囊，四角都圆、顶上留缝，
    /// 不画屏幕上没有的硬件（design-system V1、§8 问题 2）。
    private func notch() -> CALayer {
        let n = CALayer()
        n.backgroundColor = NSColor.black.cgColor
        n.anchorPoint = CGPoint(x: 0.5, y: 1)
        n.cornerCurve = .continuous
        n.zPosition = 6
        if notched {
            n.bounds = CGRect(x: 0, y: 0, width: 15 * u, height: 4.6 * u)
            n.position = CGPoint(x: size.width / 2, y: size.height)
            n.cornerRadius = 1.6 * u
            n.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        } else {
            n.bounds = CGRect(x: 0, y: 0, width: 10 * u, height: 3.4 * u)
            n.position = CGPoint(x: size.width / 2, y: size.height - floatGap)
            n.cornerRadius = 1.7 * u
            n.opacity = 0
        }
        root.addSublayer(n)
        return n
    }

    /// 一扇迷你窗口：标题栏、红绿灯、几行字。返回（窗口，影子）两层；窗口那层是翻转坐标（从上往下量）。
    private func window(_ frame: CGRect, title: String, lines: Int = 6) -> [CALayer] {
        let shadow = CALayer()
        shadow.frame = frame
        shadow.cornerRadius = 1.5 * u
        shadow.backgroundColor = winFill.cgColor
        shadow.shadowColor = NSColor.black.cgColor
        shadow.shadowOpacity = dark ? 0.6 : 0.3
        shadow.shadowRadius = 1.6 * u
        shadow.shadowOffset = CGSize(width: 0, height: -0.6 * u)
        let win = CALayer()
        win.frame = frame
        win.cornerRadius = 1.5 * u
        win.masksToBounds = true
        win.backgroundColor = winFill.cgColor
        win.isGeometryFlipped = true
        let bar = CALayer()
        bar.frame = CGRect(x: 0, y: 0, width: frame.width, height: barHeight)
        bar.backgroundColor = barFill.cgColor
        win.addSublayer(bar)
        for (i, hex) in [0xff5f57, 0xfebc2e, 0x28c840].enumerated() {
            let light = CALayer()
            light.frame = CGRect(x: 1.3 * u + CGFloat(i) * 1.7 * u, y: (barHeight - 1.15 * u) / 2, width: 1.15 * u, height: 1.15 * u)
            light.cornerRadius = 0.575 * u
            light.backgroundColor = Self.color(hex).cgColor
            win.addSublayer(light)
        }
        let name = text(title, size: 1.35 * u, color: dark ? Self.color(0xa1a1a6) : Self.color(0x8e8e93))
        name.frame = CGRect(x: 6 * u, y: (barHeight - 1.9 * u) / 2, width: frame.width - 12 * u, height: 1.9 * u)
        win.addSublayer(name)
        for i in 0..<min(lines, Self.lineWidths.count) {
            let line = CALayer()
            line.frame = lineFrame(i, in: frame)
            line.cornerRadius = 0.5 * u
            line.backgroundColor = textFill.cgColor
            win.addSublayer(line)
        }
        root.addSublayer(shadow)
        root.addSublayer(win)
        return [shadow, win]
    }

    /// 窗口里第 i 行字的位置（窗口那层的翻转坐标）。
    private func lineFrame(_ i: Int, in frame: CGRect) -> CGRect {
        CGRect(x: 2 * u, y: barHeight + 1.8 * u + CGFloat(i) * 2.15 * u,
               width: (frame.width - 4 * u) * Self.lineWidths[i], height: 1.05 * u)
    }

    /// 一颗键帽，可以有几张“脸”（同一个位置换字，比如 ⌃ 换成 ⌘）：大的是符号，小的是键帽上印的键名。返回键帽和每张脸。
    private func keycap(_ frame: CGRect, faces: [(symbol: String, name: String?)], in parent: CALayer) -> (CALayer, [CALayer]) {
        let cap = CALayer()
        cap.frame = frame
        cap.cornerRadius = 1.1 * u
        cap.cornerCurve = .continuous
        cap.backgroundColor = (dark ? Self.color(0x3a3a3f) : .white).cgColor
        cap.borderColor = (dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.12)).cgColor
        cap.borderWidth = 0.12 * u
        cap.shadowColor = NSColor.black.cgColor
        cap.shadowOpacity = dark ? 0.5 : 0.18
        cap.shadowRadius = 0.5 * u
        cap.shadowOffset = CGSize(width: 0, height: -0.3 * u)
        parent.addSublayer(cap)
        let faceLayers = faces.map { face -> CALayer in
            let group = CALayer()
            group.frame = cap.bounds
            let symbol = text(face.symbol, size: 2.4 * u, weight: .regular, color: ink)
            if let name = face.name {
                symbol.frame = CGRect(x: 0, y: frame.height * 0.42, width: frame.width, height: 3 * u)
                let word = text(name, size: 1.05 * u, weight: .regular, color: dark ? Self.color(0xa1a1a6) : Self.color(0x6e6e73))
                word.frame = CGRect(x: 0, y: frame.height * 0.14, width: frame.width, height: 1.5 * u)
                group.addSublayer(word)
            } else {
                symbol.frame = CGRect(x: 0, y: (frame.height - 3 * u) / 2, width: frame.width, height: 3 * u)
            }
            group.addSublayer(symbol)
            cap.addSublayer(group)
            return group
        }
        return (cap, faceLayers)
    }

    // MARK: 关键帧

    private func animate(_ layer: CALayer, _ keyPath: String, _ values: [Any], _ times: [Double]) {
        if still {
            // 减少动态效果：取 stillAt 那一刻（它之前最近的一帧）。
            let at = stillOverride ?? stillAt
            let index = times.lastIndex { $0 <= at } ?? 0
            layer.setValue(values[index], forKeyPath: keyPath)
            return
        }
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = values
        a.keyTimes = times.map { NSNumber(value: $0) }
        a.duration = cycle
        a.repeatCount = .infinity
        a.calculationMode = .linear
        a.timingFunctions = Array(repeating: CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1), count: max(1, values.count - 1))
        a.isRemovedOnCompletion = false
        a.fillMode = .both
        layer.add(a, forKey: keyPath)
    }

    // MARK: 那一段

    /// 截图核对用（--settings-shots）：有动画的那一步摆哪几刻的静帧来拍（一轮里的比例），按页排。
    /// 静帧取那一刻之前最近的关键帧：0.2 是按了 ⌃C 没反应，0.5 是刘海说出 Mac 上那一下、键帽已换成 ⌘。
    static let shotMoments: [[Double]] = [
        [0.2, 0.5],
    ]

    func build(_ index: Int) {
        switch index {
        case 0: stuck()
        default: break
        }
    }

    /// 按了 Windows 的 ⌃C 没反应；刘海从自己身上往下长，说 Mac 上按哪一下，键帽上的 ⌃ 换成 ⌘；按对了，刘海马上收回、不再出声。
    /// 刘海里的字照卡住时的真提示写（docs/stuck-habits.md：菜单里那一项叫“拷贝”，副句“常用快捷键把 ⌃ 换成 ⌘”）。
    private func stuck() {
        cycle = 7; stillAt = 0.5
        menubar("备忘录")
        let n = notch()
        let full = rect(20, 24, 60, 52)
        let win = window(full, title: "购物清单", lines: 5)
        // 要拷贝的那一行是选中的（系统的选中底色）。
        let selection = CALayer()
        selection.frame = lineFrame(1, in: full).insetBy(dx: -0.3 * u, dy: -0.5 * u)
        selection.cornerRadius = 0.3 * u
        selection.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        win[1].insertSublayer(selection, at: 1)

        // 刘海展开成一块，下面两行字：主句白色，副句白 0.6（刘海永远是深色，不跟外观）。
        // 没有刘海：胶囊浮出来、长大，没有摄像头那一截，所以矮一些，两行字在正中。
        let closed = n.bounds.size
        let open = CGSize(width: 40 * u, height: notched ? 12.6 * u : 8 * u)
        let islandTimes: [Double] = [0, 0.3, 0.38, 0.7, 0.78, 1]
        animate(n, "bounds.size", [closed, closed, open, open, closed, closed].map { NSValue(size: $0) }, islandTimes)
        if notched {
            animate(n, "cornerRadius", [1.6 * u, 1.6 * u, 3.4 * u, 3.4 * u, 1.6 * u, 1.6 * u], islandTimes)
        } else {
            let (rest, full) = (closed.height / 2, open.height / 2)
            animate(n, "cornerRadius", [rest, rest, full, full, rest, rest], islandTimes)
            animate(n, "opacity", [0, 0, 1, 1, 0, 0], islandTimes)
        }
        let left = (size.width - open.width) / 2
        // 两行字的顶边离屏幕顶边多远：有刘海时在摄像头那一截下面，没有时在胶囊里居中（两行共高 5u）。
        let textTop = notched ? 5.6 * u : floatGap + (open.height - 5 * u) / 2
        let headline = text("Mac 上拷贝按 ⌘C", size: 1.9 * u, color: .white)
        headline.frame = CGRect(x: left, y: size.height - textTop - 2.6 * u, width: open.width, height: 2.6 * u)
        let detail = text("常用快捷键把 ⌃ 换成 ⌘", size: 1.45 * u, weight: .regular, color: NSColor.white.withAlphaComponent(0.6))
        detail.frame = CGRect(x: left, y: size.height - textTop - 5 * u, width: open.width, height: 2 * u)
        for line in [headline, detail] {
            line.zPosition = 7
            line.opacity = 0
            root.addSublayer(line)
            animate(line, "opacity", [0, 0, 1, 1, 0, 0], [0, 0.36, 0.41, 0.66, 0.71, 1])
        }

        // 键帽：先按 ⌃C（没反应），刘海说完 ⌃ 换成 ⌘，再按 ⌘C。
        let keys = CALayer()
        keys.frame = root.bounds
        keys.zPosition = 8
        keys.opacity = 0
        root.addSublayer(keys)
        animate(keys, "opacity", [0, 0, 1, 1, 0, 0], [0, 0.06, 0.1, 0.86, 0.92, 1])
        let modWidth = 9 * u, capSide = 6.4 * u, gap = 1.2 * u
        let x0 = (size.width - modWidth - gap - capSide) / 2
        let (modifier, faces) = keycap(CGRect(x: x0, y: 3 * u, width: modWidth, height: capSide),
                                       faces: [("⌃", "control"), ("⌘", "command")], in: keys)
        let (letter, _) = keycap(CGRect(x: x0 + modWidth + gap, y: 3 * u, width: capSide, height: capSide),
                                 faces: [("C", nil)], in: keys)
        let swap: [Double] = [0, 0.44, 0.47, 0.93, 0.95, 1]
        animate(faces[0], "opacity", [1, 1, 0, 0, 1, 1], swap)
        animate(faces[1], "opacity", [0, 0, 1, 1, 0, 0], swap)
        for cap in [modifier, letter] {
            animate(cap, "transform.scale", [1, 1, 0.9, 1, 1, 0.9, 1, 1], [0, 0.16, 0.18, 0.21, 0.56, 0.58, 0.61, 1])
        }
    }
}
