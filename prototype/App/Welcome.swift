// 欢迎使用 WindowShade：首次打开时出现、菜单里随时能再打开（“欢迎使用 Macintosh”的现代版）。
// 三步（M4 样片，docs/design-drafts/安静的刘海 动效样片.html）：1 刚换 Mac？从刘海开始（舞台上一段短动画）；
// 2 你之前常用哪个？（存进 SwitcherOrigin，设置里能改；选 Windows 时舞台左下四颗键帽原地换成 Mac 的）；3 授权（不放舞台，窗口跟着变矮）。
// 状态机、文案和动效数值在 WelcomeFlow.swift（纯逻辑，有单测）；这里只负责画出来。
// 其余的手势不在这里教，交给刘海在他卡住时教（docs/direction.md）。
// 三步之间窗口不关、舞台不重建：旧内容淡出 0.10 s，新内容淡入 0.18 s 并上浮 6 pt；整段只有窗口高度这一处形变（calm）。
// 动画全是 Core Animation 图层（渲染进程播，不占主线程），窗口看不见时停下、看不见时也不重建。“减少动态效果”打开时只淡化、不位移。
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

/// 标题、选项、说明行、授权行放在这一块里：翻页时整块淡入、上浮，旧的那一块用截图淡出。
final class WelcomeContent: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class WelcomeView: NSView {
    struct Page {
        let title: String
        let lede: String
        /// 舞台上那段动画演的是什么（VoiceOver 读它）；没有舞台的一步是 nil。
        var picture: String? = nil
    }
    static let pages: [Page] = [
        // 一句话（docs/design-drafts 的 M4）：先说刚换 Mac 的人在哪卡住，再说它什么时候出声。
        Page(title: WelcomeFlow.introTitle,
             lede: WelcomeFlow.introLede,
             picture: "动画：按了 ⌃C 没有反应，刘海展开说“Mac 上拷贝按 ⌘C”；按了 ⌘C，刘海收回；再按 ⌘V，那句话落进邮件。"),
        Page(title: WelcomeFlow.originTitle, lede: WelcomeFlow.originNote(for: .unanswered),
             picture: "示意图：选了 Windows，左下角四颗键帽换成 Mac 上的 fn、control、option、command。"),
        Page(title: WelcomeFlow.permissionTitle, lede: WelcomeFlow.permissionLede),
    ]
    /// 问来处的那一步。
    static let originPage = WelcomeFlow.originStep
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
    /// 授权页第三行（日程）现在画的是哪种状态；变了才重画。
    var shownCalendar: CalendarAccess?
    /// 装好新版本后系统要他重新打开两项授权：授权页换成“再打开一次这两项”那组文案。
    var permissionsAgain = false { didSet { if index == Self.permissionPage && !onMoveStep { show(index) } } }

    private let stage = WelcomeStage()
    private let content = WelcomeContent()
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
    /// 第一次摆好页面之前不做翻页动画。
    private var didShowPage = false
    /// 翻页时旧内容的截图（淡出后留着不画，下次翻页或停掉时拆掉）。
    private var leavingSnapshot: CALayer?
    /// 三步之前那一步：放进“应用程序”文件夹。AppDelegate 在从第一步打开时交进来；nil 就没有这一步。
    private var moveStep: UpdaterMoveStep?
    private(set) var onMoveStep = false
    private var moveFailed = false
    private let moveBox = NSStackView()
    private let moveIcon = NSImageView()
    /// 截图核对用：第二步画成这个答案（只画出来，不存）；平常是 nil，画的是存着的答案。
    private var previewOrigin: SwitcherOrigin?

    static let size = NSSize(width: WelcomeFlow.Layout.width, height: WelcomeFlow.Layout.heightWithStage)

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(stage)

        content.wantsLayer = true
        addSubview(content)

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
        content.addSubview(permissionBox)
        NSLayoutConstraint.activate([
            permissionBox.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            permissionBox.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.permissionBoxTop),
        ])
        // 三个选项放在标题下面一排。
        choices.isHidden = true
        choices.setAccessibilityLabel(Self.pages[Self.originPage].title)
        choices.onPick = { [weak self] origin in
            // 点了就存（关窗口、跳过都不丢）；和原来一样时 SwitcherOrigin 自己不发通知。
            self?.previewOrigin = nil
            SwitcherOrigin.current = origin
            self?.showOrigin()
        }
        content.addSubview(choices)
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
        // 放进“应用程序”那一步没有舞台，图标摆在舞台那块区域的正中。
        NSLayoutConstraint.activate([
            moveBox.centerXAnchor.constraint(equalTo: centerXAnchor),
            moveBox.centerYAnchor.constraint(equalTo: topAnchor, constant: WelcomeFlow.Layout.top + WelcomeFlow.Layout.stageHeight / 2),
        ])

        eyebrow.font = .systemFont(ofSize: 12)
        eyebrow.textColor = .tertiaryLabelColor
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        lede.font = .systemFont(ofSize: 14)
        lede.textColor = .secondaryLabelColor
        lede.maximumNumberOfLines = 3
        lede.wantsLayer = true
        [eyebrow, titleLabel, lede].forEach(content.addSubview)

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
        relayout()
        show(0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// 授权行的位置：小标题、标题、导语（最多三行）之后。
    private static let permissionBoxTop: CGFloat = 126

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayout()
    }

    /// 所有位置都从窗口现在的高度算：窗口在 calm 里变矮时，舞台、文字、按钮一起跟着走，不用另外记动画进度。
    private func relayout() {
        typealias L = WelcomeFlow.Layout
        let width = bounds.width, height = bounds.height
        guard width > 0, height > 0 else { return }
        let fraction = onMoveStep ? 1 : WelcomeFlow.stageFraction(forWindowHeight: height)
        let stageWidth = width - L.padding * 2
        stage.frame = NSRect(x: L.padding, y: L.top, width: stageWidth, height: (L.stageHeight * fraction).rounded())
        stage.alphaValue = fraction
        // 舞台收完了才停掉它的动画；平时（第一、二步）看不看得见由 show 定。
        stage.isHidden = onMoveStep || fraction <= 0
        if fraction <= 0 && !WelcomeFlow.hasStage(step: index) { stage.stop() }
        let contentTop = L.top + fraction * (L.stageHeight + L.stageGap)
        content.frame = NSRect(x: 0, y: contentTop, width: width, height: max(0, height - contentTop - L.bottomBar))
        layoutContent(width: width)
        dots.frame = NSRect(x: L.padding, y: height - 40, width: 200, height: 16)
        layoutButtons()
    }

    /// 内容这一块里面的位置（从块的顶上量）：小标题、标题，然后是导语（第二步在选项下面）、授权行。
    private func layoutContent(width: CGFloat) {
        let padding = WelcomeFlow.Layout.padding
        let textWidth = width - padding * 2
        eyebrow.frame = NSRect(x: padding, y: 0, width: textWidth, height: 16)
        titleLabel.frame = NSRect(x: padding, y: 20, width: textWidth, height: 30)
        if index == Self.originPage && !onMoveStep {
            choices.frame = NSRect(x: padding, y: 58, width: WelcomeChoices.totalSize.width, height: WelcomeChoices.totalSize.height)
            lede.frame = NSRect(x: padding, y: 58 + WelcomeChoices.totalSize.height + 12, width: textWidth, height: 40)
        } else {
            // 三行高（授权页在标准账户、更新后要重新授权时会到三行）；字从上往下排，一两行时位置不变。
            lede.frame = NSRect(x: padding, y: 58, width: textWidth, height: 60)
        }
    }

    private func layoutButtons() {
        var x = bounds.width - 26
        next.sizeToFit()
        // 无边框的“跳过”比有边框的按钮矮，按中线对齐，字才在同一条线上。
        let midY = bounds.height - 18 - next.frame.height / 2
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
        let previous = didShowPage && !onMoveStep ? index : nil
        let target = max(0, min(Self.pages.count - 1, page))
        // 同一个窗口里换内容：旧内容淡出、新内容淡入并上浮；窗口没打开、截图核对、第一次摆页面时直接换。
        let animates = preview == nil && window?.isVisible == true && previous != nil && previous != target
        let transition = WelcomeFlow.transition(reduceMotion: Motion.reduced)
        let snapshot = animates ? takeContentSnapshot() : nil

        index = target
        didShowPage = true
        onMoveStep = false
        moveBox.isHidden = true
        dots.isHidden = false
        [skip, next].forEach { $0.isEnabled = true }
        previewOrigin = preview?.origin
        let item = Self.pages[index]
        eyebrow.stringValue = WelcomeFlow.eyebrow(forStep: index)
        titleLabel.stringValue = item.title
        lede.stringValue = index == Self.originPage ? WelcomeFlow.originNote(for: shownOrigin) : item.lede
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
        // 焦点还在某个选项上就离开了第二步：交回这一页，← → 接着翻页，不会在看不见的选项之间换答案。
        if index != Self.originPage, let focused = window?.firstResponder as? NSView, focused.isDescendant(of: choices) {
            window?.makeFirstResponder(self)
        }
        choices.isHidden = index != Self.originPage
        permissionBox.isHidden = !last
        // 舞台只给前两步；离开舞台那一步时舞台随窗口变矮收掉（relayout 里收完才停）。
        if item.picture != nil {
            stage.play(index, stillAt: preview?.moment, notched: preview?.notched, origin: shownOrigin, settled: preview != nil)
        }
        stage.setAccessibilityLabel(item.picture)
        resizeWindow(forStep: index, animated: animates && transition.animatesWindow)
        relayout()
        showOrigin()
        if let snapshot { playContentTransition(from: snapshot, transition) }
        NSAccessibility.post(element: self, notification: .layoutChanged)
        onPageChange?()
    }

    /// 第二步现在画哪个答案。
    private var shownOrigin: SwitcherOrigin { previewOrigin ?? SwitcherOrigin.current }

    // MARK: 翻页：窗口高度和内容淡入淡出

    /// 窗口变矮（或变高）：上边不动，下边挪。用 calm 的时长和不回弹的缓动；不动画（减少动态效果、窗口还没打开）就直接换。
    private func resizeWindow(forStep step: Int, animated: Bool) {
        guard let window else { return }
        let delta = WelcomeFlow.windowHeight(forStep: step) - bounds.height
        guard abs(delta) > 0.5 else { return }
        var frame = window.frame
        frame.size.height += delta
        frame.origin.y -= delta
        guard animated, window.isVisible else {
            window.setFrame(frame, display: window.isVisible)
            return
        }
        let calm = Motion.spring(.calm, keyPath: "bounds.size.height")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = calm.duration
            // 临界阻尼弹簧的形状：一上来就走得快，慢慢收住，没有回弹。
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            window.animator().setFrame(frame, display: true)
        }
    }

    private func takeContentSnapshot() -> CALayer? {
        guard content.bounds.width > 0, content.bounds.height > 0,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return nil }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let image = rep.cgImage else { return nil }
        let layer = CALayer()
        layer.contents = image
        layer.contentsScale = window?.backingScaleFactor ?? 2
        layer.frame = content.frame
        layer.zPosition = 20
        return layer
    }

    /// 旧内容的截图 0.10 s 淡出；新内容等它淡完，0.18 s 淡入并从下面上浮 6 pt（减少动态效果时不位移）。
    private func playContentTransition(from snapshot: CALayer, _ transition: WelcomeFlow.StepTransition) {
        guard let root = layer, let contentLayer = content.layer else { return }
        leavingSnapshot?.removeFromSuperlayer()
        leavingSnapshot = snapshot
        root.addSublayer(snapshot)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        snapshot.opacity = 0
        CATransaction.commit()
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        fadeOut.duration = transition.fadeOut
        snapshot.add(fadeOut, forKey: "welcome.out")

        let begin = contentLayer.convertTime(CACurrentMediaTime(), from: nil) + transition.fadeOut
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = transition.fadeIn
        fadeIn.beginTime = begin
        fadeIn.fillMode = .backwards
        contentLayer.add(fadeIn, forKey: "welcome.in")
        if transition.rise > 0 {
            // 上浮：从低 rise pt 的地方回到原位。翻转的图层 y 向下为正。
            let down = root.isGeometryFlipped ? CGFloat(transition.rise) : -CGFloat(transition.rise)
            let rise = Motion.spring(.calm, keyPath: "position.y")
            rise.isAdditive = true
            rise.fromValue = down
            rise.toValue = 0
            rise.beginTime = begin
            rise.fillMode = .backwards
            contentLayer.add(rise, forKey: "welcome.rise")
        }
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
        // 这一步没有舞台，窗口回到有舞台的高度（图标摆在舞台那块区域里）。
        resizeWindow(forStep: 0, animated: false)
        relayout()
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
        let reduce = Motion.reduced
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.opacity
        fade.toValue = 0.25
        fade.duration = Motion.fadeDuration
        layer.opacity = 0.25
        layer.add(fade, forKey: "move.fade")
        if !reduce {
            let travel = moveBox.arrangedSubviews.last.map { $0.frame.midX - moveIcon.frame.midX } ?? 0
            let scale: CGFloat = 0.55
            let inset = moveIcon.bounds.width * (1 - scale) / 2
            var t = CATransform3DMakeTranslation(travel + inset, moveIcon.bounds.height * (1 - scale) / 2, 0)
            t = CATransform3DScale(t, scale, scale, 1)
            let spring = Motion.spring(.settle, keyPath: "transform")
            spring.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
            spring.toValue = NSValue(caTransform3D: t)
            layer.add(spring, forKey: "move.glide")
            layer.transform = t
        }
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

    /// 第二步的选中状态、键帽、说明行和“继续”能不能点。
    private func showOrigin() {
        choices.selected = shownOrigin
        if index == Self.originPage {
            let note = WelcomeFlow.originNote(for: shownOrigin)
            if lede.stringValue != note {
                // 说明行跟着选项换：旧字淡出、新字淡入（图层的淡化过渡）。
                if didShowPage, window?.isVisible == true, previewOrigin == nil, let layer = lede.layer {
                    let fade = CATransition()
                    fade.type = .fade
                    fade.duration = WelcomeFlow.transition(reduceMotion: Motion.reduced).fadeIn
                    layer.add(fade, forKey: "welcome.note")
                }
                lede.stringValue = note
                NSAccessibility.post(element: lede, notification: .valueChanged)
            }
            stage.setOrigin(shownOrigin, animated: previewOrigin == nil)
        }
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
        let last = WelcomeFlow.isLast(index)
        let granted = last && permissionsGranted()
        skip.title = last ? "稍后再说" : "跳过"
        skip.isHidden = granted
        if last {
            next.isEnabled = granted
        } else {
            next.isEnabled = WelcomeFlow.canAdvance(from: index, origin: choices.selected)
        }
        layoutButtons()
    }

    @objc private func nextPressed() {
        if onMoveStep { pressMovePrimary(); return }
        if index == Self.permissionPage { onFinish?() } else { show(WelcomeFlow.next(from: index)) }
    }
    @objc private func backPressed() { show(WelcomeFlow.back(from: index)) }
    @objc private func skipPressed() {
        if onMoveStep {
            // 跳过就不再在欢迎窗口里问（没能移过去时的“继续”不算跳过）；更新小窗里位置不对时还会再给这一步。
            if !moveFailed { UpdaterMove.shared.declineForWelcome() }
            show(0)
            return
        }
        if index == Self.permissionPage { onLater?() } else { show(WelcomeFlow.skip(from: index)) }
    }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if onMoveStep {
            // 这一步的 → 就是“跳过”；← 没有上一步。
            if event.keyCode == 124, skip.isEnabled { skipPressed() } else if event.keyCode != 123 { super.keyDown(with: event) }
            return
        }
        switch event.keyCode {
        case 124: show(WelcomeFlow.next(from: index))
        case 123: show(WelcomeFlow.back(from: index))
        default: super.keyDown(with: event)
        }
    }
}

// MARK: - 页码点

final class WelcomeDots: NSView {
    var count = 0 { didSet { needsDisplay = true } }
    var current = 0 {
        didSet {
            needsDisplay = true
            if current != oldValue { NSAccessibility.post(element: self, notification: .valueChanged) }
        }
    }
    var onSelect: ((Int) -> Void)?

    // 读屏：页码点是一个整体，读“第 n 页”（n 从 1 数，跟着现在这一页走）。
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { WelcomeFlow.pageLabel(current + 1) }

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

    /// 标题下面一排三个：图标在左、名字在右（舞台还在上面，放不下大卡片）。
    static let itemSize = NSSize(width: 212, height: 56)
    static let spacing: CGFloat = 16
    static var totalSize: NSSize {
        NSSize(width: 3 * itemSize.width + 2 * spacing, height: itemSize.height)
    }

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
        Self.totalSize
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
            .withSymbolConfiguration(.init(pointSize: 24, weight: .regular))
        icon.imageScaling = .scaleNone
        icon.frame = NSRect(x: 14, y: (size.height - 32) / 2, width: 40, height: 32)
        label.stringValue = origin.title ?? ""
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.alignment = .left
        label.frame = NSRect(x: 60, y: (size.height - 20) / 2, width: size.width - 60 - 40, height: 20)
        check.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        check.contentTintColor = .controlAccentColor
        check.frame = NSRect(x: size.width - 14 - 18, y: (size.height - 18) / 2, width: 18, height: 18)
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
    /// 舞台整块的大小：窗口收起舞台时只是被裁掉（顶边对齐），画面不重排。
    static let sceneSize = CGSize(width: WelcomeFlow.Layout.width - WelcomeFlow.Layout.padding * 2, height: WelcomeFlow.Layout.stageHeight)

    private var scene: CALayer?
    private var builder: WelcomeScene?
    /// 刚被换下的画面：淡出后拆掉（定时器拆，不在看不见的时候留着动画）。
    private var retired: [CALayer] = []
    private var retireTimer: Timer?

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

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        alignScene()
    }

    /// 画面顶边对齐舞台顶边：舞台变矮时从下面被裁掉，像收起一块幕布。
    private func alignScene() {
        guard let scene else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scene.frame.origin = CGPoint(x: 0, y: bounds.height - scene.bounds.height)
        CATransaction.commit()
    }

    private var currentIndex: Int?
    private var currentMoment: Double?
    /// 第二步现在画的是哪个答案（键帽只在答 Windows 时出现）。
    private var origin: SwitcherOrigin = .unanswered
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
            dropScene()
            dropRetired()
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
        if let current = currentIndex { play(current, stillAt: currentMoment, notched: forcedNotch, origin: origin, settled: true) }
    }

    private func dropScene() {
        scene?.removeFromSuperlayer()
        scene = nil
        builder = nil
        builtNotched = nil
    }

    private func dropRetired() {
        retireTimer?.invalidate()
        retireTimer = nil
        retired.forEach { $0.removeFromSuperlayer() }
        retired.removeAll()
    }

    func stop() {
        dropScene()
        dropRetired()
        currentIndex = nil
        currentMoment = nil
        forcedNotch = nil
    }

    /// 第二步选了别的答案：键帽跟着出现或收起。
    func setOrigin(_ new: SwitcherOrigin, animated: Bool) {
        guard new != origin else { return }
        origin = new
        builder?.setOrigin(new, animated: animated)
    }

    /// moment：截图核对用，摆出一轮里那一刻的静帧（和“减少动态效果”同一条路径）；平常是 nil，照常循环播。
    /// notched：截图核对用，当作有 / 没有刘海的屏来画；平常是 nil，看窗口所在的那块屏。
    /// origin：第二步画成哪个答案。settled：不放翻页的淡入淡出，直接摆到位（截图、重画）。
    func play(_ index: Int, stillAt moment: Double? = nil, notched forced: Bool? = nil,
              origin answer: SwitcherOrigin = .unanswered, settled: Bool = false) {
        let outgoing = scene
        scene = nil
        builder = nil
        builtNotched = nil
        currentIndex = index
        currentMoment = moment
        forcedNotch = forced
        origin = answer
        // 窗口看不见时不建循环动画；静帧没有动画，照样摆（截图核对不受遮挡影响）。
        guard !parked || moment != nil else { outgoing?.removeFromSuperlayer(); return }
        let notched = forced ?? screenHasNotch
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let builder = WelcomeScene(size: Self.sceneSize, dark: dark, scale: window?.backingScaleFactor ?? 2,
                                   still: moment != nil || Motion.reduced, notched: notched)
        builder.stillOverride = moment
        builder.build(index, origin: answer)
        layer?.addSublayer(builder.root)
        scene = builder.root
        self.builder = builder
        builtNotched = notched
        alignScene()
        // 翻页：旧画面 0.10 s 淡出，新画面等它淡完再 0.18 s 淡入（只淡化，减少动态效果时也一样）。
        if let outgoing, !settled, moment == nil, window?.isVisible == true {
            let transition = WelcomeFlow.transition(reduceMotion: Motion.reduced)
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1
            fadeOut.toValue = 0
            fadeOut.duration = transition.fadeOut
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            outgoing.opacity = 0
            CATransaction.commit()
            outgoing.add(fadeOut, forKey: "welcome.stage.out")
            retired.append(outgoing)
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0
            fadeIn.toValue = 1
            fadeIn.duration = transition.fadeIn
            fadeIn.beginTime = builder.root.convertTime(CACurrentMediaTime(), from: nil) + transition.fadeOut
            fadeIn.fillMode = .backwards
            builder.root.add(fadeIn, forKey: "welcome.stage.in")
            retireTimer?.invalidate()
            let timer = Timer.scheduledTimer(withTimeInterval: transition.fadeOut + 0.05, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.dropRetired() }
            }
            timer.tolerance = 0.05
            retireTimer = timer
        } else {
            outgoing?.removeFromSuperlayer()
        }
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
    private func window(_ frame: CGRect, title: String, lines: Int = 6, skippingFirstLine: Bool = false) -> [CALayer] {
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
        for i in (skippingFirstLine ? 1 : 0)..<min(lines, Self.lineWidths.count) {
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
        // 停下时图层上留的是这一刻（开口帧）：减少动态效果直接摆它，播完几轮也停在它。
        let rest = values[times.lastIndex { $0 <= (stillOverride ?? stillAt) } ?? 0]
        if still {
            layer.setValue(rest, forKeyPath: keyPath)
            return
        }
        layer.setValue(rest, forKeyPath: keyPath)
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = values
        a.keyTimes = times.map { NSNumber(value: $0) }
        a.duration = cycle
        // 播 3 轮，再多播到开口帧那一刻停下：动画一结束，图层上本来就是开口帧，接得上，不用一直循环。
        a.repeatCount = Float(WelcomeFlow.introLoopRounds) + Float(stillAt)
        a.calculationMode = .linear
        // 教学循环的节拍写在 keyTimes 里；段与段之间不另造贝塞尔，形变手感见 `calm`（文法欢迎页）。
        a.timingFunctions = nil
        a.fillMode = .backwards
        layer.add(a, forKey: keyPath)
    }

    // MARK: 那一段

    /// 截图核对用（--settings-shots）：有动画的那一步摆哪几刻的静帧来拍（一轮里的比例），按页排。
    /// 静帧取那一刻之前最近的关键帧：0.2 是按了 ⌃C 没反应，0.5 是刘海说出 Mac 上那一下、键帽已换成 ⌘。
    static let shotMoments: [[Double]] = [
        [0.2, 0.5],
    ]

    /// origin：第二步画成哪个答案（键帽只在答 Windows 时出现）。
    func build(_ index: Int, origin: SwitcherOrigin = .unanswered) {
        switch index {
        case 0: stuck()
        case 1:
            keysStep()
            setOrigin(origin, animated: false)
        default: break
        }
    }

    /// 备忘录和邮件两扇窗口：左边是要拷贝的，右边是要粘贴的。
    private func twoWindows() -> (memo: (frame: CGRect, layers: [CALayer]), mail: (frame: CGRect, layers: [CALayer])) {
        let memoFrame = rect(5, 22, 43, 52), mailFrame = rect(52, 22, 43, 52)
        return ((memoFrame, window(memoFrame, title: "购物清单", lines: 5)),
                (mailFrame, window(mailFrame, title: "邮件", lines: 4, skippingFirstLine: true)))
    }

    /// 要拷贝的那一行是选中的（系统的选中底色）。
    private func select(line: Int, in frame: CGRect, of win: CALayer) {
        let selection = CALayer()
        selection.frame = lineFrame(line, in: frame).insetBy(dx: -0.3 * u, dy: -0.5 * u)
        selection.cornerRadius = 0.3 * u
        selection.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        win.insertSublayer(selection, at: 1)
    }

    /// 按了 Windows 的 ⌃C 没反应；刘海从自己身上往下长，说 Mac 上按哪一下，键帽上的 ⌃ 换成 ⌘；按对了，刘海马上收回、不再出声；
    /// 再按 ⌘V，拷贝的那一行落进邮件。整轮播 3 遍后停在开口帧。
    /// 刘海里的字照卡住时的真提示写（docs/stuck-habits.md：菜单里那一项叫“拷贝”，副句“常用快捷键把 ⌃ 换成 ⌘”）。
    private func stuck() {
        cycle = 8; stillAt = WelcomeFlow.introRestMoment
        menubar("备忘录")
        let n = notch()
        let (memo, mail) = twoWindows()
        select(line: 1, in: memo.frame, of: memo.layers[1])
        // ⌘V：拷贝的那一行（和选中的一样长）落进邮件的第一行。
        let pasted = CALayer()
        var pastedFrame = lineFrame(0, in: mail.frame)
        pastedFrame.size.width = (mail.frame.width - 4 * u) * Self.lineWidths[1]
        pasted.frame = pastedFrame
        pasted.cornerRadius = 0.5 * u
        pasted.backgroundColor = ink.withAlphaComponent(0.5).cgColor
        pasted.opacity = 0
        mail.layers[1].addSublayer(pasted)
        animate(pasted, "opacity", [0, 0, 1, 1, 0], [0, 0.82, 0.86, 0.96, 1])

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

        // 键帽：先按 ⌃C（没反应），刘海说完 ⌃ 换成 ⌘，再按 ⌘C，最后按 ⌘V。
        let keys = CALayer()
        keys.frame = root.bounds
        keys.zPosition = 8
        keys.opacity = 0
        root.addSublayer(keys)
        animate(keys, "opacity", [0, 0, 1, 1, 0, 0], [0, 0.06, 0.1, 0.9, 0.95, 1])
        let modWidth = 9 * u, capSide = 6.4 * u, gap = 1.2 * u
        let x0 = (size.width - modWidth - gap - capSide) / 2
        let (modifier, faces) = keycap(CGRect(x: x0, y: 3 * u, width: modWidth, height: capSide),
                                       faces: [("⌃", "control"), ("⌘", "command")], in: keys)
        let (letter, letterFaces) = keycap(CGRect(x: x0 + modWidth + gap, y: 3 * u, width: capSide, height: capSide),
                                           faces: [("C", nil), ("V", nil)], in: keys)
        let swap: [Double] = [0, 0.44, 0.47, 0.93, 0.95, 1]
        animate(faces[0], "opacity", [1, 1, 0, 0, 1, 1], swap)
        animate(faces[1], "opacity", [0, 0, 1, 1, 0, 0], swap)
        let letterSwap: [Double] = [0, 0.74, 0.77, 0.96, 0.99, 1]
        animate(letterFaces[0], "opacity", [1, 1, 0, 0, 1, 1], letterSwap)
        animate(letterFaces[1], "opacity", [0, 0, 1, 1, 0, 0], letterSwap)
        for cap in [modifier, letter] {
            animate(cap, "transform.scale", [1, 1, 0.9, 1, 1, 0.9, 1, 1, 0.9, 1, 1],
                    [0, 0.16, 0.18, 0.21, 0.56, 0.58, 0.61, 0.80, 0.82, 0.85, 1])
        }
    }

    // MARK: 第二步：左下四颗键帽

    private var keyDeck: CALayer?
    private var keyOld: [CALayer] = []
    private var keyNew: [CALayer] = []
    private var keyGlow: CALayer?
    private var keysShown = false

    /// 第二步的舞台：和第一步停下时同一张桌面，没有动画；左下角一块键盘，选了 Windows 才出现。
    private func keysStep() {
        stillAt = WelcomeFlow.introRestMoment
        menubar("备忘录")
        _ = notch()
        let (memo, _) = twoWindows()
        select(line: 1, in: memo.frame, of: memo.layers[1])

        let capWidth = 7.2 * u, capHeight = 6 * u, gap = 1 * u, padding = 1.4 * u
        let deckWidth = capWidth * 4 + gap * 3 + padding * 2
        let deck = CALayer()
        deck.frame = CGRect(x: 2.4 * u, y: 1.2 * u, width: deckWidth, height: capHeight + padding * 2)
        deck.cornerRadius = 1.6 * u
        deck.cornerCurve = .continuous
        deck.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.07)).cgColor
        deck.zPosition = 8
        deck.opacity = 0
        root.addSublayer(deck)
        keyDeck = deck
        // 四颗按位置对应：Windows 的 Ctrl / Fn / ⊞ / Alt，原地换成 Mac 的 fn / control / option / command。
        let macFaces: [(symbol: String, name: String?)] = [("fn", nil), ("⌃", "control"), ("⌥", "option"), ("⌘", "command")]
        for i in 0..<4 {
            let frame = CGRect(x: padding + CGFloat(i) * (capWidth + gap), y: padding, width: capWidth, height: capHeight)
            let (cap, faces) = keycap(frame, faces: [(WelcomeFlow.windowsKeyNames[i], nil), macFaces[i]], in: deck)
            faces[1].opacity = 0
            keyOld.append(faces[0])
            keyNew.append(faces[1])
            if i == WelcomeFlow.litKeyIndex {
                // ⌘ 的填充：换完字之后从 0.14 亮到 0.28（深色下是白，浅色下是强调色）。
                let glow = CALayer()
                glow.frame = cap.bounds
                glow.cornerRadius = 1.1 * u
                glow.cornerCurve = .continuous
                glow.backgroundColor = (dark ? NSColor.white : NSColor.controlAccentColor).cgColor
                glow.opacity = 0
                cap.insertSublayer(glow, at: 0)
                keyGlow = glow
            }
        }
    }

    private func setOpacity(_ layer: CALayer, _ value: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.opacity = value
        CATransaction.commit()
    }

    /// 模型值马上到位，显示上从现在的样子淡过去（start 秒后开始）。
    private func fade(_ layer: CALayer, to value: Float, start: Double, duration: Double, at now: CFTimeInterval) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = layer.presentation()?.opacity ?? layer.opacity
        a.toValue = value
        a.duration = duration
        a.beginTime = layer.convertTime(now, from: nil) + start
        a.fillMode = .backwards
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = value
        CATransaction.commit()
        layer.add(a, forKey: "welcome.keys")
    }

    /// 键帽跟着答案出现或收起。animated 为 false 时直接摆到位（截图、重画、第一次建场景）。
    func setOrigin(_ origin: SwitcherOrigin, animated: Bool) {
        guard let deck = keyDeck, let glow = keyGlow else { return }
        let show = WelcomeFlow.keycapsShown(for: origin)
        guard show != keysShown else { return }
        keysShown = show
        let plan = WelcomeFlow.keySwapPlan(reduceMotion: Motion.reduced)
        let transition = WelcomeFlow.transition(reduceMotion: Motion.reduced)
        let now = CACurrentMediaTime()
        guard animated else {
            for i in 0..<4 {
                setOpacity(keyOld[i], show ? 0 : 1)
                setOpacity(keyNew[i], show ? 1 : 0)
            }
            setOpacity(glow, show ? Float(plan.glowTo) : 0)
            setOpacity(deck, show ? 1 : 0)
            return
        }
        if !show {
            // 收起：整块键盘 0.10 s 淡出（下次出现时再从 Windows 的字重新换）。
            fade(deck, to: 0, start: 0, duration: transition.fadeOut, at: now)
            return
        }
        // 起点：不论上次停在哪，先把键帽摆回 Windows 的字（键盘藏着，看不见）。
        for i in 0..<4 {
            setOpacity(keyOld[i], 1)
            setOpacity(keyNew[i], 0)
        }
        setOpacity(glow, 0)
        fade(deck, to: 1, start: 0, duration: transition.fadeIn, at: now)
        for step in plan.steps {
            fade(keyOld[step.index], to: 0, start: step.oldFadeStart, duration: step.oldFadeDuration, at: now)
            fade(keyNew[step.index], to: 1, start: step.newFadeStart, duration: step.newFadeDuration, at: now)
            if step.popFrom < 1 {
                let pop = Motion.spring(.pop, keyPath: "transform.scale")
                pop.fromValue = step.popFrom
                pop.toValue = 1
                pop.beginTime = keyNew[step.index].convertTime(now, from: nil) + step.newFadeStart
                pop.fillMode = .backwards
                keyNew[step.index].add(pop, forKey: "welcome.keys.pop")
            }
        }
        // ⌘ 亮起：先随新字淡入到 0.14，再升到 0.28（calm 的时长）。
        let last = plan.steps[WelcomeFlow.litKeyIndex]
        let total = plan.glowStart + plan.glowDuration
        let lit = CAKeyframeAnimation(keyPath: "opacity")
        lit.values = [0, plan.glowFrom, plan.glowFrom, plan.glowTo]
        lit.keyTimes = [0, (last.newFadeStart + last.newFadeDuration) / total, plan.glowStart / total, 1].map { NSNumber(value: $0) }
        lit.duration = total
        lit.beginTime = glow.convertTime(now, from: nil)
        lit.fillMode = .backwards
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.opacity = Float(plan.glowTo)
        CATransaction.commit()
        glow.add(lit, forKey: "welcome.keys.glow")
    }
}
