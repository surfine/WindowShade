// 欢迎使用 WindowShade：首次打开时出现、菜单里随时能再打开（“欢迎使用 Macintosh”的现代版）。
// 设计稿《首次打开 1.0.17 小样》（1.0.18 版）：三页，页码点只数这三页（HIG 上限）——
//   A1 看一遍，再试一下：顶上两块演示（左块手上做什么，右块屏幕上发生什么），双击标题栏收成卷帘条演两轮，
//      然后右块那扇窗口就是练习窗口，他自己双击收起、再双击展开（收起 WindowShade 自己画的窗口，不要授权，所以排在授权前面）；
//   A2 辅助功能（必需）+ 屏幕录制（可选）：两行各自实时变 ✓，“继续”只等辅助功能；
//   T 再看四样：刘海、窗口浏览、手势与卷轴、菜单栏，一页分段，自己往下走，随时能停；刘海一段下面一行可选的“你之前常用哪个？”。
// U1“再打开一次这两项”是升级上来缺授权时单独的一页（不算页码）。两块演示是设置窗口同一个讲解视图（SettingsExplainerView，
// 欢迎窗口按 326 / 312 放大），帧数据在 Core/ExplainerScenes+Common.swift 与 +Welcome.swift。
// 状态机、文案和动效数值在 WelcomeFlow.swift（纯逻辑，有单测）；这里只负责画出来。
// 页之间窗口不关：旧内容淡出 0.10 s，新内容淡入 0.18 s 并上浮 6 pt；窗口高度用 calm。“减少动态效果”时只淡化、不位移，
// 演示停在关键帧加箭头，T 不自己往下走。窗口看不见时演示停下，又看得见了从这一块开头演。
// 关窗口也算看过，下次不再自动弹出。从“下载”等地方直接打开时，三页之前多一步“放进‘应用程序’文件夹”（UpdaterMove，不算页码）。

import Cocoa

/// 截图核对用（--settings-shots、AppKit 测试）：这一张摆成什么样，只画出来，不存、不循环播。平常不传。
struct WelcomePreview {
    /// A1 摆成哪一刻（nil 是演示的关键帧）。
    var practice: WelcomeFlow.PracticeState? = nil
    /// 授权行画成这样（不读系统）。
    var accessibility: Bool? = nil
    var screenRecording: Bool? = nil
    /// T 摆哪一段。
    var segment: WelcomeFlow.TourSegment? = nil
    /// A2 摆成“回来 10 秒还没好”。
    var stuck = false
}

/// CADisplayLink 强引用 target：代理只弱引用欢迎视图。回调在主线程 run loop。
final class WelcomeHeightProxy: NSObject {
    weak var owner: WelcomeView?
    init(owner: WelcomeView) { self.owner = owner }
    @objc func step(_ link: CADisplayLink) {
        guard owner != nil else { link.invalidate(); return }
        let owner = owner
        MainActor.assumeIsolated { owner?.advanceHeightMotion() }
    }
}

/// 页的内容放在这一块里：翻页时整块淡入、上浮，旧的那一块用截图淡出。
final class WelcomeContent: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class WelcomeView: NSView {
    static let practicePage = WelcomeFlow.practiceStep
    /// 授权那一页（缺权限的提醒直接打开到这里；U1 也停在这一页的位置上）。
    static let permissionPage = WelcomeFlow.permissionStep
    static let tourPage = WelcomeFlow.tourStep
    static let pageCount = WelcomeFlow.stepCount

    var onFinish: (() -> Void)?
    var onLater: (() -> Void)?
    /// 翻了一页：AppDelegate 据此决定授权页的每秒刷新开不开（只在停在授权页时开）。
    var onPageChange: (() -> Void)?
    /// 授权行里的“去授权”：AppDelegate 带系统询问、打开对的那一栏。
    var onGrantAccessibility: (() -> Void)?
    var onGrantScreenRecording: (() -> Void)?
    /// 辅助功能有没有：A2 的“继续”、U1 的“开始使用”只等它（屏幕录制可选）。
    var permissionsGranted: () -> Bool = { true }
    /// 授权行现在画的是哪种状态（辅助功能、屏幕录制）；没变就不重画。AppDelegate 停刷新时看它。
    private(set) var shownGrants: [Bool]?
    /// 装好新版本后系统要他重新打开两项授权：换成单独的 U1 那一页。
    var permissionsAgain = false { didSet { if permissionsAgain, !showingAgain, !onMoveStep { showAgain() } } }
    /// 现在停在 A2 或 U1：要每秒刷新授权行。
    var needsPermissionRefresh: Bool { !onMoveStep && index == Self.permissionPage }

    private let hero = WelcomeHero()
    private let segments = NSSegmentedControl()
    private let content = WelcomeContent()
    private let stack = NSStackView()
    private var stackTop: NSLayoutConstraint?
    private let eyebrow = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let lede = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let permissionCard = WelcomePermissionCard()
    private let progress = NSTextField(labelWithString: "")
    private let stuck = NSTextField(wrappingLabelWithString: "")
    private let admin = NSTextField(wrappingLabelWithString: "")
    private let permissionStatus = NSTextField(labelWithString: "")
    private let privacyNote = NSTextField(wrappingLabelWithString: "")
    private let origin = WelcomeOriginRow()
    private let missingAccessibility = NSTextField(wrappingLabelWithString: "")
    private let optionNote = NSTextField(labelWithString: "")
    private let dots = WelcomeDots()
    private let skip = NSButton(title: WSL10n.text("welcome.button.skip", zh: "跳过"), target: nil, action: nil)
    private let back = NSButton(title: WSL10n.text("welcome.button.back", zh: "上一步"), target: nil, action: nil)
    let next = NSButton(title: WSL10n.text("welcome.button.next", zh: "继续"), target: nil, action: nil)
    private(set) var index = 0
    /// 正在 U1（“再打开一次这两项”）。
    private(set) var showingAgain = false
    /// 第一次摆好页面之前不做翻页动画。
    private var didShowPage = false
    private var leavingSnapshot: CALayer?
    private var moveStep: UpdaterMoveStep?
    private(set) var onMoveStep = false
    private var heightMotion: WelcomeFlow.HeightMotion?
    private var heightLink: CADisplayLink?
    private lazy var heightProxy = WelcomeHeightProxy(owner: self)
    private var moveFailed = false
    private let moveBox = NSStackView()
    private let moveIcon = NSImageView()
    private let moveTitle = NSTextField(wrappingLabelWithString: "")
    private let moveLede = NSTextField(wrappingLabelWithString: "")

    // A1
    private(set) var practice: WelcomeFlow.PracticeState = .demo
    // A2 / U1
    private var grants = (accessibility: false, screenRecording: false)
    private var permissionShownAt: Date?
    private var stuckTimer: Timer?
    private var forceStuck = false
    // T
    private(set) var tour = WelcomeFlow.TourPlayback(segment: .notch)
    private var tourGap: Timer?
    /// 截图核对：正在摆静帧，不演、不自己往下走。
    private var previewing = false

    static let size = NSSize(width: WelcomeFlow.Layout.width, height: WelcomeFlow.Layout.practiceHeight)
    private static let contentWidth = WelcomeFlow.Layout.width - WelcomeFlow.Layout.padding * 2

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        content.wantsLayer = true
        addSubview(content)
        buildStack()
        buildMoveStep()
        buildFooter()

        hero.onLoopsFinished = { [weak self] id in self?.heroFinished(id) }
        hero.onPracticeDoubleClick = { [weak self] in self?.practiceDoubleClicked() }
        hero.onPointerEntered = { [weak self] in self?.stopTourAuto() }
        hero.onBecameVisible = { [weak self] in self?.replayHero() }
        origin.onPick = { origin in SwitcherOrigin.current = origin }
        permissionCard.onGrant = { [weak self] kind in self?.grantPressed(kind) }

        // Tab 顺序：这一页 → 练习标题栏（A1）→ 分段、三个来处（T）→ 授权行（A2、U1）→ 上一步、跳过、继续 → 回到这一页。
        let loop: [NSView] = [self, hero.practiceTarget, segments] + origin.items + permissionCard.buttons + [back, skip, next]
        let following: [NSView] = Array(loop.dropFirst()) + [self]
        for (view, after) in zip(loop, following) { view.nextKeyView = after }
        NotificationCenter.default.addObserver(self, selector: #selector(originDidChange),
                                               name: SwitcherOrigin.didChangeNotification, object: nil)
        relayout()
        show(0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: 搭界面

    private func buildStack() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        let top = stack.topAnchor.constraint(equalTo: content.topAnchor)
        stackTop = top
        NSLayoutConstraint.activate([
            top,
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: WelcomeFlow.Layout.padding),
            stack.widthAnchor.constraint(equalToConstant: Self.contentWidth),
        ])

        segments.segmentCount = WelcomeFlow.TourSegment.allCases.count
        segments.trackingMode = .selectOne
        segments.segmentDistribution = .fillEqually
        segments.controlSize = .large
        segments.target = self
        segments.action = #selector(segmentPicked(_:))
        segments.translatesAutoresizingMaskIntoConstraints = false
        segments.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true

        eyebrow.font = .systemFont(ofSize: 12)
        eyebrow.textColor = .tertiaryLabelColor
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.maximumNumberOfLines = 2
        lede.font = .systemFont(ofSize: 14)
        lede.textColor = .secondaryLabelColor
        lede.maximumNumberOfLines = 3
        status.font = .systemFont(ofSize: 13)
        permissionStatus.font = .systemFont(ofSize: 13)
        permissionStatus.textColor = .secondaryLabelColor
        progress.font = .systemFont(ofSize: 13, weight: .medium)
        stuck.font = .systemFont(ofSize: 12.5)
        stuck.textColor = .systemOrange
        for fine in [admin, privacyNote, optionNote] {
            fine.font = .systemFont(ofSize: 12)
            fine.textColor = .tertiaryLabelColor
        }
        missingAccessibility.font = .systemFont(ofSize: 12)
        missingAccessibility.textColor = .systemOrange
        for label in [titleLabel, lede, stuck, admin, privacyNote, missingAccessibility] {
            label.preferredMaxLayoutWidth = Self.contentWidth
        }
        for label in [titleLabel, lede, status] { label.wantsLayer = true }
        permissionCard.translatesAutoresizingMaskIntoConstraints = false
        permissionCard.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true

        let views: [NSView] = [hero, segments, eyebrow, titleLabel, lede, status, permissionCard, progress, stuck, admin,
                               permissionStatus, origin, missingAccessibility, privacyNote]
        views.forEach(stack.addArrangedSubview)
        // 稿里的间距：分段在演示块下 12、标题在分段下 14；眉题、标题、导语之间 2 / 6；授权行之后 8，隐私小字前 16。
        stack.setCustomSpacing(14, after: segments)
        stack.setCustomSpacing(2, after: eyebrow)
        stack.setCustomSpacing(6, after: titleLabel)
        stack.setCustomSpacing(8, after: permissionCard)
        stack.setCustomSpacing(8, after: progress)
        stack.setCustomSpacing(8, after: stuck)
        stack.setCustomSpacing(8, after: admin)
        stack.setCustomSpacing(16, after: permissionStatus)
        stack.setCustomSpacing(6, after: origin)
    }

    private func buildMoveStep() {
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
        // 这一步没有演示块，图标摆在演示块那块区域的正中；标题和说明在演示块下面，和 A1 的标题同一个位置。
        NSLayoutConstraint.activate([
            moveBox.centerXAnchor.constraint(equalTo: centerXAnchor),
            moveBox.centerYAnchor.constraint(equalTo: topAnchor, constant: WelcomeFlow.Layout.top + WelcomeFlow.Layout.heroHeight / 2),
        ])
        let textTop = WelcomeFlow.Layout.top + WelcomeFlow.Layout.heroHeight + WelcomeFlow.Layout.heroGap
        moveTitle.font = .systemFont(ofSize: 24, weight: .semibold)
        moveTitle.frame = NSRect(x: WelcomeFlow.Layout.padding, y: textTop + 18, width: Self.contentWidth, height: 32)
        moveLede.font = .systemFont(ofSize: 14)
        moveLede.textColor = .secondaryLabelColor
        moveLede.frame = NSRect(x: WelcomeFlow.Layout.padding, y: textTop + 56, width: Self.contentWidth, height: 60)
        for label in [moveTitle, moveLede] {
            label.preferredMaxLayoutWidth = Self.contentWidth
            label.isHidden = true
            addSubview(label)
        }
    }

    private func buildFooter() {
        dots.count = Self.pageCount
        dots.onSelect = { [weak self] in self?.show($0) }
        addSubview(dots)
        optionNote.alignment = .right
        optionNote.lineBreakMode = .byTruncatingHead
        addSubview(optionNote)
        for (button, action) in [(skip, #selector(skipPressed)), (back, #selector(backPressed)), (next, #selector(nextPressed))] {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
            button.controlSize = .large
            addSubview(button)
        }
        skip.isBordered = false
        skip.contentTintColor = .secondaryLabelColor
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayout()
    }

    /// 所有位置都从窗口现在的高度算：窗口在 calm 里变高变矮时，内容顶边不动，按钮跟着底边走。
    private func relayout() {
        typealias L = WelcomeFlow.Layout
        let width = bounds.width, height = bounds.height
        guard width > 0, height > 0 else { return }
        content.frame = NSRect(x: 0, y: L.top, width: width, height: max(0, height - L.top - L.bottomBar))
        dots.frame = NSRect(x: L.padding, y: height - 40, width: 80, height: 16)
        layoutButtons()
    }

    private func layoutButtons() {
        var x = bounds.width - WelcomeFlow.Layout.padding
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
        if !optionNote.isHidden {
            optionNote.sizeToFit()
            let left = dots.frame.maxX + 12
            let noteWidth = min(optionNote.frame.width, max(0, x - 6 - left))
            optionNote.frame = NSRect(x: x - 6 - noteWidth, y: (midY - optionNote.frame.height / 2).rounded(),
                                      width: noteWidth, height: optionNote.frame.height)
        }
    }

    // MARK: 翻页

    /// preview：截图核对用，摆出静帧、画成某个状态；平常不传，照常演。
    func show(_ page: Int, preview: WelcomePreview? = nil) {
        let previous = didShowPage && !onMoveStep && !showingAgain ? index : nil
        let target = WelcomeFlow.clamped(page)
        let animates = preview == nil && window?.isVisible == true && previous != nil && previous != target
        let transition = WelcomeFlow.transition(reduceMotion: Motion.reduced)
        let snapshot = animates ? takeContentSnapshot() : nil

        index = target
        didShowPage = true
        leaveSpecialSteps()
        showingAgain = false
        previewing = preview != nil
        dots.isHidden = false
        dots.current = index
        forceStuck = preview?.stuck ?? false
        if let preview, preview.accessibility != nil || preview.screenRecording != nil {
            updateGrants(accessibility: preview.accessibility ?? false, screenRecording: preview.screenRecording ?? false)
        }
        // 焦点留在藏起来的控件上就交回这一页，← → 接着翻页。
        if let focused = window?.firstResponder as? NSView, focused !== self, focused.isDescendant(of: self) {
            window?.makeFirstResponder(self)
        }

        switch index {
        case Self.practicePage: showPractice(preview: preview)
        case Self.permissionPage: showPermissions(again: false)
        default: showTour(preview: preview)
        }
        window?.title = titleLabel.stringValue
        resizeWindow(toHeight: WelcomeFlow.windowHeight(forStep: index), animated: animates && transition.animatesWindow)
        relayout()
        refreshButtons()
        if let snapshot { playContentTransition(from: snapshot, transition) }
        NSAccessibility.post(element: self, notification: .layoutChanged)
        onPageChange?()
    }

    /// 离开“放进应用程序”那一步、停掉上一页的计时器。
    private func leaveSpecialSteps() {
        onMoveStep = false
        moveBox.isHidden = true
        [moveTitle, moveLede].forEach { $0.isHidden = true }
        content.isHidden = false
        stopTourGap()
        stuckTimer?.invalidate()
        stuckTimer = nil
    }

    /// 每页先把所有的块藏起来，再按这一页打开要的那几块。
    private func hideAll() {
        [hero, segments, eyebrow, titleLabel, lede, status, permissionCard, progress, stuck, admin, permissionStatus, origin,
         missingAccessibility, privacyNote, optionNote].forEach { $0.isHidden = true }
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        stackTop?.constant = 0
        stack.setCustomSpacing(12, after: hero)
        stack.setCustomSpacing(8, after: lede)
    }

    private func showPractice(preview: WelcomePreview?) {
        hideAll()
        hero.isHidden = false
        hero.practiceEnabled = true
        stack.setCustomSpacing(WelcomeFlow.Layout.heroGap, after: hero)
        eyebrow.isHidden = false
        eyebrow.stringValue = WelcomeFlow.eyebrow
        titleLabel.isHidden = false
        titleLabel.stringValue = WelcomeFlow.practiceTitle
        lede.isHidden = false
        lede.stringValue = WelcomeFlow.practiceLede
        status.isHidden = false
        optionNote.isHidden = false
        optionNote.stringValue = Self.optionNote
        back.isHidden = true
        skip.isHidden = false
        skip.title = WSL10n.text("welcome.button.skip", zh: "跳过")
        if let preview {
            let state = preview.practice ?? .demo
            practice = state
            switch state {
            case .demo: hero.hold(ExplainerScenes.doubleClickRoll, arrows: Motion.reduced)
            case .idle: hero.hold(ExplainerScenes.practiceIdle)
            case .rolled: hero.hold(ExplainerScenes.practiceToggle(from: false))
            case .done: hero.hold(ExplainerScenes.practiceToggle(from: true))
            }
        } else if Motion.reduced {
            // 减少动态效果：不演示，停在收成卷帘条那一帧、加箭头和原位虚线框；直接轮到他。
            practice = .idle
            hero.hold(ExplainerScenes.doubleClickRoll, arrows: true)
        } else {
            practice = .demo
            hero.play(ExplainerScenes.doubleClickRoll, loops: WelcomeFlow.demoLoops)
        }
        hero.setAccessibilityLabel(ExplainerScenes.doubleClickRoll.description.shown)
        showPracticeState(animated: false)
    }

    private func showPermissions(again: Bool) {
        hideAll()
        stackTop?.constant = again ? 10 : 14
        eyebrow.isHidden = !again
        eyebrow.stringValue = "WindowShade 1.0.18"
        titleLabel.isHidden = false
        titleLabel.stringValue = again ? UpdateCopy.permissionsAgainTitle : WelcomeFlow.permissionTitle
        lede.isHidden = false
        lede.stringValue = again
            ? UpdateCopy.permissionsAgainLead + WSL10n.text("welcome.u1.once", zh: "只要这一次，以后更新不用再开。")
            : WelcomeFlow.permissionLede
        stack.setCustomSpacing(18, after: lede)
        permissionCard.isHidden = false
        permissionCard.configure(again: again)
        progress.isHidden = !again
        stuck.stringValue = UpdateCopy.permissionsStuckHint
        admin.isHidden = !UpdaterMove.shared.isStandardAccount
        admin.stringValue = UpdateCopy.standardAccount
        privacyNote.isHidden = again
        privacyNote.stringValue = WSL10n.text("welcome.a2.privacy", zh: "读了什么、为什么读，设置 → 隐私 里都列着。")
        back.isHidden = again
        skip.isHidden = false
        skip.title = WSL10n.text("welcome.button.later", zh: "稍后再说")
        permissionShownAt = Date()
        if !again, !previewing {
            // 回到这页 10 秒还有一项没好，出现“−”那句。
            let timer = Timer(timeInterval: WelcomeFlow.stuckHintDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.showPermissionState() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            stuckTimer = timer
        }
        showPermissionState()
    }

    /// U1：升级上来缺授权时单独的一页（没有页码点、没有上一步）。
    private func showAgain() {
        let animates = didShowPage && window?.isVisible == true && !onMoveStep
        let snapshot = animates ? takeContentSnapshot() : nil
        index = Self.permissionPage
        didShowPage = true
        leaveSpecialSteps()
        showingAgain = true
        dots.isHidden = true
        showPermissions(again: true)
        window?.title = titleLabel.stringValue
        resizeWindow(toHeight: WelcomeFlow.Layout.againHeight, animated: false)
        relayout()
        refreshButtons()
        if let snapshot { playContentTransition(from: snapshot, WelcomeFlow.transition(reduceMotion: Motion.reduced)) }
        NSAccessibility.post(element: self, notification: .layoutChanged)
        onPageChange?()
    }

    /// 截图核对用：把 U1 摆成某个授权状态。
    func showAgain(preview: WelcomePreview) {
        previewing = true
        updateGrants(accessibility: preview.accessibility ?? false, screenRecording: preview.screenRecording ?? false)
        if showingAgain { showPermissionState(); refreshButtons() } else { permissionsAgain = true }
    }

    private func showTour(preview: WelcomePreview?) {
        hideAll()
        hero.isHidden = false
        hero.practiceEnabled = false
        segments.isHidden = false
        titleLabel.isHidden = false
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        lede.isHidden = false
        back.isHidden = true
        skip.isHidden = false
        skip.title = WSL10n.text("welcome.button.skip", zh: "跳过")
        for segment in WelcomeFlow.TourSegment.allCases {
            segments.setLabel(segment.segmentTitle, forSegment: segment.rawValue)
        }
        segments.setAccessibilityLabel(WSL10n.text("welcome.tour.segmentsA11y", zh: "再看四样"))
        origin.configure(question: WelcomeFlow.originQuestion, optional: WelcomeFlow.originOptional)
        tour = WelcomeFlow.TourPlayback(segment: preview?.segment ?? .notch, hero: 0, auto: preview == nil && !Motion.reduced)
        playTour(fade: false)
    }

    // MARK: A1

    /// 底下那行小字：怎么回到系统的双击（系统设置里双击是“缩放”或“最小化”时，照设置页“双击标题栏”那一行的副标题）。
    private static var optionNote: String {
        switch systemTitlebarDoubleClickAction() {
        case .zoom: return WSL10n.text("settings.shade.doubleClick.subZoom", zh: "三击标题栏会缩放窗口。按住 Option 双击不收起")
        case .minimize: return WSL10n.text("settings.shade.doubleClick.subMinimize", zh: "三击标题栏会最小化窗口。按住 Option 双击不收起")
        case .none: return WSL10n.text("welcome.a1.option", zh: "想要系统原来的双击？按住 Option 再双击。")
        }
    }

    private func practiceDoubleClicked() {
        guard index == Self.practicePage, !onMoveStep, !showingAgain else { return }
        let wasRolled = WelcomeFlow.practiceIsRolled(practice)
        practice = WelcomeFlow.practice(afterDoubleClick: practice)
        hero.play(ExplainerScenes.practiceToggle(from: wasRolled), loops: 1, instant: true)
        showPracticeState(animated: true)
        wlog("welcome: practice double-click -> \(practice)")
    }

    private func showPracticeState(animated: Bool) {
        let text = WelcomeFlow.practiceStatus(practice)
        let done = practice == .done
        let shown = done ? "✓ " + text : text
        if status.stringValue != shown {
            if animated, let layer = status.layer {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = Motion.Fade.fadeIn()
                layer.add(fade, forKey: "welcome.status")
            }
            status.stringValue = shown
            if animated { NSAccessibility.post(element: status, notification: .valueChanged) }
        }
        status.textColor = done ? .systemGreen : .secondaryLabelColor
        hero.setHint(practice == .idle ? WelcomeFlow.practiceHint : nil, animated: animated)
        hero.practiceRolled = WelcomeFlow.practiceIsRolled(practice)
        refreshButtons()
    }

    // MARK: 演示块

    private func heroFinished(_ id: String) {
        guard !onMoveStep, !showingAgain else { return }
        if index == Self.practicePage {
            if id == ExplainerScenes.doubleClickRoll.id, practice == .demo {
                // 演完两轮：右块那扇窗口变成练习窗口，轮到他。
                practice = .idle
                hero.hold(ExplainerScenes.practiceIdle, transition: .crossfade)
                showPracticeState(animated: true)
            } else if id.hasPrefix("welcome.practice.") {
                hero.holdCurrent()
            }
        } else if index == Self.tourPage, id == currentTourSpec.id {
            guard let following = WelcomeFlow.tour(after: tour, reduceMotion: Motion.reduced) else { return }
            stopTourGap()
            let timer = Timer(timeInterval: WelcomeFlow.tourHeroGap, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.index == Self.tourPage, !self.onMoveStep else { return }
                    let changesSegment = following.segment != self.tour.segment
                    // 他在这 0.4 s 里点了分段或按了“继续”：照他的来，不再自己往下走。
                    guard self.tour.auto || !changesSegment else { return }
                    self.tour = following
                    self.playTour(fade: changesSegment)
                }
            }
            timer.tolerance = 0.05
            RunLoop.main.add(timer, forMode: .common)
            tourGap = timer
        }
    }

    /// 窗口又看得见了：从这一块开头演（A1 还在演示就重演演示）。
    private func replayHero() {
        guard !onMoveStep, !previewing, !hero.isHidden else { return }
        if index == Self.practicePage {
            if practice == .demo, !Motion.reduced { hero.play(ExplainerScenes.doubleClickRoll, loops: WelcomeFlow.demoLoops) }
        } else if index == Self.tourPage {
            playTour(fade: false)
        }
    }

    // MARK: T

    private var currentTourSpec: ExplainerSpec {
        let heroes = ExplainerScenes.tourHeroes(tour.segment)
        return heroes[min(tour.hero, heroes.count - 1)]
    }

    private func playTour(fade: Bool) {
        let segment = tour.segment
        segments.selectedSegment = segment.rawValue
        if fade, !Motion.reduced {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = Motion.Fade.fadeIn()
            for label in [titleLabel, lede] { label.layer?.add(transition, forKey: "welcome.tour") }
        }
        titleLabel.stringValue = segment.title
        lede.stringValue = segment.lede
        window?.title = segment.title
        origin.isHidden = !segment.asksOrigin
        origin.selected = SwitcherOrigin.current
        missingAccessibility.isHidden = !(segment.showsMissingAccessibility && !permissionsGrantedNow)
        missingAccessibility.stringValue = WelcomeFlow.missingAccessibilityNote
        let spec = currentTourSpec
        if previewing || Motion.reduced {
            hero.hold(spec, arrows: Motion.reduced)
        } else {
            hero.play(spec, loops: segment.loopsPerHero)
        }
        hero.setAccessibilityLabel(spec.description.shown)
        refreshButtons()
    }

    private var permissionsGrantedNow: Bool { shownGrants?.first ?? permissionsGranted() }

    @objc private func segmentPicked(_ sender: NSSegmentedControl) {
        guard let segment = WelcomeFlow.TourSegment(rawValue: sender.selectedSegment) else { return }
        stopTourGap()
        tour = WelcomeFlow.TourPlayback(segment: segment, hero: 0, auto: false)
        playTour(fade: true)
        NSAccessibility.post(element: hero, notification: .announcementRequested,
                             userInfo: [.announcement: segment.title,
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private func stopTourAuto() {
        guard index == Self.tourPage else { return }
        tour.auto = false
    }

    private func stopTourGap() {
        tourGap?.invalidate()
        tourGap = nil
    }

    // MARK: A2 / U1

    /// 按现在的授权状态画授权行；和上次画的一样就什么都不动。返回画没画。
    @discardableResult
    func updateGrants(accessibility: Bool, screenRecording: Bool) -> Bool {
        let now = [accessibility, screenRecording]
        guard shownGrants != now else { return false }
        let before = shownGrants
        shownGrants = now
        grants = (accessibility, screenRecording)
        let animated = before != nil && window?.isVisible == true && !previewing
        permissionCard.setGranted(accessibility: accessibility, screenRecording: screenRecording, animated: animated)
        if animated, let before {
            let changes: [(WelcomePermissionCard.Kind, Bool, Bool)] = [(.accessibility, before[0], accessibility),
                                                                       (.screenRecording, before[1], screenRecording)]
            for (kind, was, isOn) in changes where !was && isOn {
                NSAccessibility.post(element: permissionCard, notification: .announcementRequested,
                                     userInfo: [.announcement: WSL10n.text("welcome.a2.grantedA11y", zh: "%@已授权", kind.name),
                                                .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
        }
        if index == Self.permissionPage, !onMoveStep { showPermissionState() }
        if index == Self.tourPage { missingAccessibility.isHidden = !(tour.segment.showsMissingAccessibility && !accessibility) }
        // 辅助功能一好，窗口拿回最前面（他多半还在系统设置里）。
        if animated, before?.first == false, accessibility, index == Self.permissionPage, let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        refreshButtons()
        return true
    }

    private func showPermissionState() {
        let ax = grants.accessibility, sr = grants.screenRecording
        let seconds = permissionShownAt.map { Date().timeIntervalSince($0) } ?? 0
        stuck.isHidden = !(forceStuck || WelcomeFlow.showsStuckHint(again: showingAgain, accessibility: ax,
                                                                      screenRecording: sr, secondsOnPage: seconds))
        if showingAgain {
            progress.stringValue = WelcomeFlow.againProgress(accessibility: ax, screenRecording: sr)
            progress.textColor = ax && sr ? .systemGreen : .labelColor
            permissionStatus.isHidden = true
        } else {
            permissionStatus.stringValue = WelcomeFlow.permissionStatus(accessibility: ax)
            permissionStatus.isHidden = !ax
        }
    }

    private func grantPressed(_ kind: WelcomePermissionCard.Kind) {
        switch kind {
        case .accessibility:
            permissionCard.waitingForAccessibility = !showingAgain
            onGrantAccessibility?()
        case .screenRecording:
            onGrantScreenRecording?()
        }
    }

    // MARK: 按钮

    /// A1：“继续”一直能点，试完后变主按钮。A2：“继续”只等辅助功能，没有时旁边给“稍后再说”。
    /// T：“继续”一段一段走，最后一段是“开始使用”。U1：“开始使用”只等辅助功能。
    func refreshButtons() {
        guard !onMoveStep else { return }
        let ax = permissionsGrantedNow
        let primary: Bool
        if showingAgain {
            next.title = WSL10n.text("welcome.button.start", zh: "开始使用")
            next.isEnabled = ax
            skip.isHidden = ax
            primary = ax
        } else {
            switch index {
            case Self.practicePage:
                next.title = WSL10n.text("welcome.button.next", zh: "继续")
                next.isEnabled = true
                primary = WelcomeFlow.practiceNextIsPrimary(practice)
            case Self.permissionPage:
                next.title = WSL10n.text("welcome.button.next", zh: "继续")
                next.isEnabled = WelcomeFlow.canAdvance(from: index, accessibilityGranted: ax)
                skip.isHidden = ax
                primary = ax
            default:
                next.title = WelcomeFlow.tour(continueFrom: tour.segment) == nil
                    ? WSL10n.text("welcome.button.start", zh: "开始使用")
                    : WSL10n.text("welcome.button.next", zh: "继续")
                next.isEnabled = true
                primary = true
            }
        }
        // 主按钮靠回车键等价着强调色；不是主按钮时回车照样是“继续”（keyDown 里接）。
        next.keyEquivalent = primary ? "\r" : ""
        layoutButtons()
    }

    @objc private func nextPressed() {
        if onMoveStep { pressMovePrimary(); return }
        if showingAgain { onFinish?(); return }
        switch index {
        case Self.tourPage:
            stopTourGap()
            if let following = WelcomeFlow.tour(continueFrom: tour.segment) {
                tour = WelcomeFlow.TourPlayback(segment: following, hero: 0, auto: false)
                playTour(fade: true)
            } else {
                onFinish?()
            }
        default:
            guard next.isEnabled else { return }
            show(WelcomeFlow.next(from: index))
        }
    }

    @objc private func backPressed() { show(WelcomeFlow.back(from: index)) }

    @objc private func skipPressed() {
        if onMoveStep {
            // 跳过就不再在欢迎窗口里问（没能移过去时的“继续”不算跳过）；更新小窗里位置不对时还会再给这一步。
            if !moveFailed { UpdaterMove.shared.declineForWelcome() }
            show(0)
            return
        }
        if showingAgain { onLater?(); return }
        if WelcomeFlow.skipCloses(from: index) { onFinish?(); return }
        show(WelcomeFlow.skip(from: index))
    }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if onMoveStep {
            // 这一步的 → 就是“跳过”；← 没有上一步。
            if event.keyCode == 124, skip.isEnabled { skipPressed() } else if event.keyCode != 123 { super.keyDown(with: event) }
            return
        }
        switch event.keyCode {
        case 36, 76:
            if next.isEnabled { nextPressed() }
        case 124 where !showingAgain:
            // → 和“继续”一样：A2 没授权时不往后翻，最后一页不重来。
            guard WelcomeFlow.next(from: index) != index, WelcomeFlow.canAdvance(from: index, accessibilityGranted: permissionsGrantedNow) else { return }
            show(WelcomeFlow.next(from: index))
        case 123 where !showingAgain:
            guard WelcomeFlow.back(from: index) != index else { return }
            show(WelcomeFlow.back(from: index))
        default:
            super.keyDown(with: event)
        }
    }

    @objc private func originDidChange() {
        origin.selected = SwitcherOrigin.current
    }

    // MARK: 窗口高度和内容淡入淡出

    /// 窗口变高变矮：上边不动，下边挪。高度逐帧由 FlickSpring.calm 驱动，不用贝塞尔；
    /// 中途换目标（连点“继续”）沿用当前位置和速度，停稳就停帧。不动画（减少动态效果、窗口还没打开）就直接换。
    private func resizeWindow(toHeight targetHeight: CGFloat, animated: Bool) {
        guard let window else { return }
        let running = heightLink != nil
        let current = running ? CGFloat(heightMotion?.target ?? Double(bounds.height)) : bounds.height
        guard abs(targetHeight - current) > 0.5 else { return }
        guard animated, window.isVisible else {
            stopHeightMotion()
            setWindowContentHeight(targetHeight)
            return
        }
        let now = CACurrentMediaTime()
        var motion = running ? (heightMotion ?? WelcomeFlow.HeightMotion(at: Double(bounds.height)))
                             : WelcomeFlow.HeightMotion(at: Double(bounds.height))
        motion.retarget(to: Double(targetHeight), at: now)
        heightMotion = motion
        guard !running else { return }
        let link = displayLink(target: heightProxy, selector: #selector(WelcomeHeightProxy.step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        heightLink = link
    }

    private func setWindowContentHeight(_ height: CGFloat) {
        guard let window else { return }
        let delta = height - bounds.height
        guard abs(delta) > 0.01 else { return }
        var frame = window.frame
        frame.size.height += delta
        frame.origin.y -= delta
        window.setFrame(frame, display: window.isVisible)
    }

    fileprivate func advanceHeightMotion() {
        guard let motion = heightMotion, window != nil else { stopHeightMotion(); return }
        let now = CACurrentMediaTime()
        if motion.isSettled(at: now) {
            let target = CGFloat(motion.target)
            stopHeightMotion()
            setWindowContentHeight(target)
        } else {
            setWindowContentHeight(CGFloat(motion.height(at: now)))
        }
    }

    fileprivate func stopHeightMotion() {
        heightLink?.invalidate(); heightLink = nil
        heightMotion = nil
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

    // MARK: 放进“应用程序”

    /// 三页之前那一步：放进“应用程序”文件夹。没有这一步（已经在里面、他跳过过）就直接从第一页开始。
    func showMove(_ step: UpdaterMoveStep?) {
        moveStep = step
        guard let step else { show(0); return }
        onMoveStep = true
        showingAgain = false
        moveFailed = false
        hero.stop()
        stopTourGap()
        content.isHidden = true
        moveBox.isHidden = false
        dots.isHidden = true
        optionNote.isHidden = true
        back.isHidden = true
        skip.isHidden = false
        skip.title = step.secondaryTitle
        next.title = step.primaryTitle
        next.keyEquivalent = "\r"
        [skip, next].forEach { $0.isEnabled = true }
        window?.title = step.title
        moveTitle.stringValue = step.title
        moveLede.stringValue = step.lead + (step.note ?? "")
        [moveTitle, moveLede].forEach { $0.isHidden = false }
        resetMoveIcon()
        resizeWindow(toHeight: WelcomeFlow.Layout.practiceHeight, animated: false)
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
            // .relaunching：这个进程马上退出，新位置那一份接着从第一页走。
            guard let self, case .failed = result else { return }
            self.moveFailed = true
            self.resetMoveIcon()
            self.moveLede.stringValue = UpdateCopy.moveFailed
            self.next.title = UpdateCopy.showInFinder
            self.skip.title = WSL10n.text("welcome.button.next", zh: "继续")
            [self.skip, self.next].forEach { $0.isEnabled = true }
            self.layoutButtons()
            NSAccessibility.post(element: self.moveLede, notification: .valueChanged)
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

    // 读屏：页码点是一个整体，读“第 n 页，共 3 页”（n 从 1 数，跟着现在这一页走）。
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

// MARK: - 两块演示 + 练习窗口

/// 顶上两块演示（设置窗口同一个讲解视图，放大到 326 × 209）。A1 时右块那扇窗口的标题栏上叠一块看不见的练习目标，
/// 他双击它，演示里那扇窗口收起、展开（WindowShade 自己画的窗口，不要授权）。
@MainActor
final class WelcomeHero: NSView {
    let band = SettingsExplainerView(scale: SettingsExplainerView.welcomeScale)
    let practiceTarget = WelcomePracticeTarget()
    private let hint = NSTextField(labelWithString: "")
    var onLoopsFinished: ((String) -> Void)?
    var onPracticeDoubleClick: (() -> Void)?
    var onPointerEntered: (() -> Void)?
    /// 窗口又看得见了（之前被挡住、收起、在别的桌面）：由欢迎视图决定从哪一块演。
    var onBecameVisible: (() -> Void)?
    var practiceEnabled = false {
        didSet {
            practiceTarget.isHidden = !practiceEnabled
            if !practiceEnabled { setHint(nil, animated: false) }
        }
    }
    var practiceRolled = false { didSet { practiceTarget.rolled = practiceRolled } }
    private var current: ExplainerPresentation?
    private var parked = false
    private weak var observedWindow: NSWindow?
    private var trackingArea: NSTrackingArea?

    private static var scale: CGFloat { SettingsExplainerView.welcomeScale }
    /// 右块在整条里的横向起点。
    private static var resultTileX: CGFloat { (SettingsExplainerView.tileSize.width + SettingsExplainerView.gap) * scale }

    override var isFlipped: Bool { true }

    init() {
        let size = CGSize(width: SettingsExplainerView.bandSize.width * SettingsExplainerView.welcomeScale,
                          height: SettingsExplainerView.bandSize.height * SettingsExplainerView.welcomeScale)
        super.init(frame: NSRect(origin: .zero, size: size))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size.width).isActive = true
        heightAnchor.constraint(equalToConstant: size.height).isActive = true
        band.translatesAutoresizingMaskIntoConstraints = true
        band.frame = NSRect(origin: .zero, size: size)
        addSubview(band)
        band.onLoopsFinished = { [weak self] id in self?.onLoopsFinished?(id) }
        band.usesMouse = !PointingDevices.hasTrackpad()

        // 练习目标：右块那扇窗口的标题栏，上下各放宽 5 pt，好点中。
        let s = Self.scale
        let bar = ExplainerScenes.practiceTitleBar
        practiceTarget.frame = NSRect(x: Self.resultTileX + bar.minX * s, y: bar.minY * s - 5, width: bar.width * s, height: bar.height * s + 10)
        practiceTarget.onDoubleClick = { [weak self] in self?.onPracticeDoubleClick?() }
        practiceTarget.isHidden = true
        addSubview(practiceTarget)

        hint.font = .systemFont(ofSize: 10, weight: .semibold)
        hint.textColor = .windowBackgroundColor
        hint.alignment = .center
        hint.wantsLayer = true
        hint.layer?.cornerRadius = 8
        hint.layer?.backgroundColor = NSColor.labelColor.cgColor
        hint.alphaValue = 0
        hint.setAccessibilityElement(false)
        addSubview(hint)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func isAccessibilityElement() -> Bool { false }

    /// 两块合起来是一张图，名字读当前演的是什么。
    override func setAccessibilityLabel(_ accessibilityLabel: String?) {
        band.setAccessibilityLabel(accessibilityLabel)
    }

    /// “在这里双击”小牌子：nil 收起（淡出）。
    func setHint(_ text: String?, animated: Bool) {
        if let text {
            hint.stringValue = text
            hint.sizeToFit()
            let s = Self.scale
            let center = ExplainerScenes.practiceHintCenter
            let width = ceil(hint.frame.width) + 14, height: CGFloat = 16
            hint.frame = NSRect(x: Self.resultTileX + center.x * s - width / 2, y: center.y * s - height / 2 - 6,
                                width: width, height: height)
        }
        let target: CGFloat = text == nil ? 0 : 1
        guard hint.alphaValue != target else { return }
        if animated, !Motion.reduced, window?.isVisible == true {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.fadeDuration
                hint.animator().alphaValue = target
            }
        } else {
            hint.alphaValue = target
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            hint.layer?.backgroundColor = NSColor.labelColor.cgColor
        }
    }

    // MARK: 演

    func play(_ spec: ExplainerSpec, loops: Int, instant: Bool = false) {
        apply(ExplainerPresentation(spec: spec, mode: .play(loops: loops), dimmed: false,
                                    transition: instant ? .instant : .crossfade, announces: false))
    }

    /// 停在关键帧（arrows：叠箭头和原位虚线框，减少动态效果用）。
    func hold(_ spec: ExplainerSpec, arrows: Bool = false, transition: ExplainerPresentation.Transition = .instant) {
        apply(ExplainerPresentation(spec: spec, mode: .hold(arrows: arrows), dimmed: false,
                                    transition: Motion.reduced ? .instant : transition, announces: false))
    }

    /// 正在演的这一段直接停在它的关键帧（练习的回声演完）。
    func holdCurrent() {
        guard let current else { return }
        hold(current.spec)
    }

    func stop() {
        band.stop()
        current = nil
    }

    private func apply(_ presentation: ExplainerPresentation) {
        current = presentation
        guard !parked else { return }
        band.apply(presentation)
    }

    // MARK: 看不见时停

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observedWindow { NotificationCenter.default.removeObserver(self, name: nil, object: observedWindow) }
        observedWindow = window
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionDidChange),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
    }

    // 窗口收起来、整个被挡住、关掉或在别的桌面上：停下（拆计时器、摘动画）；又看得见了从这一块开头演。
    @objc private func occlusionDidChange() {
        guard let window else { return }
        if window.occlusionState.contains(.visible) {
            guard parked else { return }
            parked = false
            if let current, case .hold = current.mode { band.apply(current) } else { onBecameVisible?() }
        } else if !parked {
            parked = true
            band.stop()
        }
    }

    // 指针停到两块上：T 不再自己往下走。
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onPointerEntered?() }
}

/// 练习窗口的标题栏：看不见的一块，叠在演示里那扇窗口的标题栏上。双击收起、再双击展开；
/// 按住 Option 双击不收起（和别的窗口一样）。读屏：按钮“购物清单的标题栏”，自定动作“收起窗口”；Tab 到这里按空格等于双击。
final class WelcomePracticeTarget: NSView {
    var onDoubleClick: (() -> Void)?
    var rolled = false

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount >= 2, event.clickCount % 2 == 0, !event.modifierFlags.contains(.option) else { return }
        onDoubleClick?()
    }

    // 键盘：Tab 进来有焦点环；空格等于双击。用鼠标点不接焦点，← → 还是翻页。
    override var acceptsFirstResponder: Bool { NSApp.currentEvent?.type != .leftMouseDown }
    override var canBecomeKeyView: Bool { !isHiddenOrHasHiddenAncestor }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 0, dy: 4) }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 4, yRadius: 4).fill()
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { onDoubleClick?() } else { super.keyDown(with: event) }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? {
        WSL10n.text("welcome.a1.practiceA11y", zh: "购物清单的标题栏。双击收起窗口。")
    }
    override func accessibilityPerformPress() -> Bool {
        onDoubleClick?()
        return true
    }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        let name = rolled ? WSL10n.text("browser.action.unfold", zh: "展开窗口") : WSL10n.text("browser.action.foldRow", zh: "收起窗口")
        return [NSAccessibilityCustomAction(name: name) { [weak self] in
            self?.onDoubleClick?()
            return true
        }]
    }
}

// MARK: - 授权行

/// A2 / U1 的两行：辅助功能（必需）、屏幕录制（可选）。各自实时变 ✓：按钮收掉、“✓ 已授权”用 pop 弹进来。
@MainActor
final class WelcomePermissionCard: NSView {
    enum Kind {
        case accessibility, screenRecording

        var name: String {
            switch self {
            case .accessibility: return PrivacyPaneName.adjust(WSL10n.text("settings.common.accessibility", zh: "辅助功能"))
            case .screenRecording: return WSL10n.text("settings.common.screenRecording", zh: "屏幕录制")
            }
        }
    }

    var onGrant: ((Kind) -> Void)?
    private let rows = [WelcomePermissionRow(kind: .accessibility), WelcomePermissionRow(kind: .screenRecording)]
    /// A2 里点了辅助功能的“去授权”、还没好：行下多一句“在系统设置里打开……”。
    var waitingForAccessibility = false { didSet { rows[0].wait.isHidden = !waitingForAccessibility || rows[0].granted } }
    var buttons: [NSView] { rows.map(\.button) }
    private let separator = NSBox()

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        let stack = NSStackView(views: [rows[0], separator, rows[1]])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            row.onGrant = { [weak self] kind in self?.onGrant?(kind) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsDidChange),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A2 和 U1 的副标题不一样（U1 是找回，说清不开也能收起窗口）。
    func configure(again: Bool) {
        waitingForAccessibility = false
        rows[0].configure(subtitle: again
            ? WSL10n.text("welcome.u1.axSub", zh: "收起和移动窗口要用")
            : WSL10n.text("welcome.a2.axSub", zh: "找到、移动和收起窗口"))
        rows[1].configure(subtitle: again
            ? WSL10n.text("welcome.u1.srSub", zh: "看一眼和缩略图里的实时画面要用。不开也能收起窗口。")
            : WSL10n.text("welcome.a2.srSub", zh: "开了，看一眼和窗口浏览里能看到窗口的实时画面。不开也能用。"))
    }

    func setGranted(accessibility: Bool, screenRecording: Bool, animated: Bool) {
        rows[0].setGranted(accessibility, animated: animated)
        rows[1].setGranted(screenRecording, animated: animated)
        if accessibility { rows[0].wait.isHidden = true }
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let layer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = SystemAppearancePolicy.groupBoxFill().cgColor
            layer.cornerRadius = SystemCornerRadius.card
            layer.cornerCurve = .continuous
            let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            layer.borderWidth = contrast ? 1 : 0.5
            layer.borderColor = (contrast ? NSColor.labelColor : NSColor.separatorColor).cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    @objc private func displayOptionsDidChange() { needsDisplay = true }
}

@MainActor
final class WelcomePermissionRow: NSView {
    let kind: WelcomePermissionCard.Kind
    var onGrant: ((WelcomePermissionCard.Kind) -> Void)?
    let button = NSButton(title: WSL10n.text("settings.privacy.needsGrant", zh: "去授权"), target: nil, action: nil)
    let wait = NSTextField(wrappingLabelWithString: WSL10n.text("welcome.a2.wait", zh: "在系统设置里打开 WindowShade 的开关，这里会自己变。"))
    private(set) var granted = false
    private let check = NSTextField(labelWithString: "✓ " + WSL10n.text("settings.privacy.granted", zh: "已授权"))
    private let subtitle = NSTextField(wrappingLabelWithString: "")

    init(kind: WelcomePermissionCard.Kind) {
        self.kind = kind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let chip = NSView()
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 8
        chip.layer?.cornerCurve = .continuous
        chip.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        let symbol = kind == .accessibility ? "accessibility" : "display"
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 15, weight: .medium)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(icon)
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.setAccessibilityElement(false)

        let name = NSTextField(labelWithString: kind.name)
        name.font = .systemFont(ofSize: 13.5, weight: .semibold)
        var nameViews: [NSView] = [name]
        if kind == .screenRecording {
            let tag = NSTextField(labelWithString: WSL10n.text("welcome.a2.optional", zh: "可选"))
            tag.font = .systemFont(ofSize: 11, weight: .medium)
            tag.textColor = .secondaryLabelColor
            nameViews.append(tag)
        }
        let nameLine = NSStackView(views: nameViews)
        nameLine.orientation = .horizontal
        nameLine.alignment = .firstBaseline
        nameLine.spacing = 6
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        wait.font = .systemFont(ofSize: 12)
        wait.textColor = .secondaryLabelColor
        wait.isHidden = true
        for label in [subtitle, wait] { label.preferredMaxLayoutWidth = 480 }
        let labels = NSStackView(views: [nameLine, subtitle, wait])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.target = self
        button.action = #selector(grantPressed)
        button.setAccessibilityHelp(kind.name)
        check.font = .systemFont(ofSize: 13, weight: .semibold)
        check.textColor = .systemGreen
        check.wantsLayer = true
        check.isHidden = true
        for view in [button, check] {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [chip, labels, spacer, button, check])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            chip.widthAnchor.constraint(equalToConstant: 32),
            chip.heightAnchor.constraint(equalToConstant: 32),
            icon.centerXAnchor.constraint(equalTo: chip.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(kind.name)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(subtitle text: String) { subtitle.stringValue = text }

    /// 变成已授权：按钮收掉，“✓ 已授权”用 pop 弹进来（减少动态效果时直接换）。
    func setGranted(_ on: Bool, animated: Bool) {
        granted = on
        button.isHidden = on
        check.isHidden = !on
        guard on, animated, !Motion.reduced, let layer = check.layer else { return }
        let pop = Motion.spring(.pop, keyPath: "transform.scale")
        pop.fromValue = 0.9
        pop.toValue = 1
        layer.add(pop, forKey: "welcome.pop")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = Motion.Fade.fadeIn()
        layer.add(fade, forKey: "welcome.popFade")
    }

    @objc private func grantPressed() { onGrant?(kind) }
}

// MARK: - T：你之前常用哪个？

/// 刘海一段下面那一行可选的单选（Windows / iPad / 一直用 Mac），旁边写“不选也行”。点了就存进 SwitcherOrigin；
/// 键盘上 Tab 进来、← → 换、空格选（和系统的单选组一样）。
@MainActor
final class WelcomeOriginRow: NSView {
    let items = SwitcherOrigin.answers.map { WelcomeChoice(origin: $0) }
    var onPick: ((SwitcherOrigin) -> Void)?
    var selected: SwitcherOrigin = .unanswered {
        didSet {
            guard selected != oldValue else { return }
            for item in items { item.isSelected = item.origin == selected }
        }
    }
    private let question = NSTextField(labelWithString: "")
    private let optional = NSTextField(labelWithString: "")
    private let group = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        for label in [question, optional] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = .tertiaryLabelColor
        }
        group.orientation = .horizontal
        group.spacing = 6
        for item in items {
            group.addArrangedSubview(item)
            item.onPick = { [weak self, weak item] origin in
                guard let self else { return }
                // 焦点已经在某个选项上（用键盘进来过）时，点了哪个焦点跟到哪个；焦点不在选项上时点了不接焦点。
                if let item, let focused = self.window?.firstResponder as? NSView, focused !== item, focused.isDescendant(of: self) {
                    self.window?.makeFirstResponder(item)
                }
                self.selected = origin
                self.onPick?(origin)
            }
            item.onStep = { [weak self] origin, step in self?.step(from: origin, by: step) }
        }
        group.setAccessibilityElement(true)
        group.setAccessibilityRole(.radioGroup)
        let row = NSStackView(views: [question, group, optional])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(question text: String, optional note: String) {
        question.stringValue = text
        optional.stringValue = note
        group.setAccessibilityLabel(text)
        items.forEach { $0.refreshTitle() }
    }

    /// ← → 在选项之间走一格，焦点和选中一起挪（到头不绕回）。
    private func step(from origin: SwitcherOrigin, by step: Int) {
        guard let at = items.firstIndex(where: { $0.origin == origin }) else { return }
        let target = items[max(0, min(items.count - 1, at + step))]
        guard target.origin != origin else { return }
        window?.makeFirstResponder(target)
        selected = target.origin
        onPick?(target.origin)
    }
}

/// 一个选项：小胶囊。选中时强调色的边、字前加 ✓（不只靠颜色）。VoiceOver 里是单选按钮。
final class WelcomeChoice: NSView {
    let origin: SwitcherOrigin
    var onPick: ((SwitcherOrigin) -> Void)?
    var onStep: ((SwitcherOrigin, Int) -> Void)?
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            refreshTitle()
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }
    private var isPressed = false { didSet { needsDisplay = true } }
    private let label = NSTextField(labelWithString: "")
    private var width: NSLayoutConstraint?

    init(origin: SwitcherOrigin) {
        self.origin = origin
        super.init(frame: NSRect(x: 0, y: 0, width: 80, height: 22))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.alignment = .center
        label.setAccessibilityElement(false)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let width = widthAnchor.constraint(equalToConstant: 80)
        self.width = width
        NSLayoutConstraint.activate([
            width,
            heightAnchor.constraint(equalToConstant: 22),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refreshTitle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func refreshTitle() {
        let name = origin.titleText ?? ""
        label.stringValue = isSelected ? "✓ " + name : name
        label.textColor = isSelected ? .controlAccentColor : .labelColor
        label.sizeToFit()
        width?.constant = ceil(label.frame.width) + 24
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let layer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let fill = SystemAppearancePolicy.groupBoxFill()
            layer.backgroundColor = (isPressed ? fill.blended(withFraction: 0.08, of: .labelColor) ?? fill : fill).cgColor
            layer.cornerRadius = 11
            layer.cornerCurve = .continuous
            if isSelected {
                layer.borderWidth = 2
                layer.borderColor = NSColor.controlAccentColor.cgColor
            } else {
                let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                layer.borderWidth = 1
                layer.borderColor = (contrast ? NSColor.labelColor : NSColor.separatorColor).cgColor
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
    override var acceptsFirstResponder: Bool { NSApp.currentEvent?.type != .leftMouseDown }
    override var canBecomeKeyView: Bool { !isHiddenOrHasHiddenAncestor }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 11, yRadius: 11).fill()
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
    override func accessibilityLabel() -> String? { origin.titleText }
    override func accessibilityValue() -> Any? { NSNumber(value: isSelected ? 1 : 0) }
    override func accessibilityPerformPress() -> Bool {
        onPick?(origin)
        return true
    }
}
