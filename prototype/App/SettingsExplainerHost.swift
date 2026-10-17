// 讲解带接到设置页的行上（1.0.18 工作单 9）：悬停、键盘焦点、点选住、分段控件逐段悬停、开关状态，
// 都换成 `ExplainerDirector` 的事件，再把结果交给 `SettingsExplainerView` 去摆。
//
// 用法（页的人只碰这两处，见 Core/ExplainerScript.swift 文件头）：
//   let (root, stack) = makeSettingsPageRoot(explainer: .gestures)   // 顶上插 640 × 200 的讲解带，下面留 14 pt
//   makeUnifiedToggleRow(…, explainer: ExplainerRow.Gestures.titleBar) // 行构造器给 explainer:
// 行构造器只给行“挂个牌”（`SettingsExplainerHost.tag`）；讲解带进了窗口才在整页上找挂了牌的行接线，
// 所以行建在哪张卡片里、包几层都不影响。没有挂牌的行不接，指上去回到页默认。
//
// 指针一进行就换（不等停留，换讲解在 120 ms 以内）；指针扫过几行时每进一行改一次目标，不排队。
// 点一下行（不是控件）选住，指针移开也接着演；再点放开。开关、分段控件的 target / action 原样保留，
// 这里只在它们之后多收一份通知。整页重建（开关一拨、语言切换）在同一拍里拆旧装新：状态机接着用，不重演页默认。

import Cocoa
import IOKit

@MainActor
final class SettingsExplainerHost: NSResponder {
    // MARK: 挂牌

    private final class Tag {
        let row: ExplainerRow
        init(_ row: ExplainerRow) { self.row = row }
    }
    private static let tags = NSMapTable<NSView, Tag>.weakToStrongObjects()

    /// 行构造器调：这一行（或对照表的一行）演哪一段。nil 不挂。返回同一个视图，方便链着写。
    @discardableResult
    static func tag(_ view: NSView, _ row: ExplainerRow?) -> NSView {
        guard let row else { return view }
        tags.setObject(Tag(row), forKey: view)
        // 读屏的人不用悬停也听得到：同一句说明挂到行的开关 / 控件上。
        if let help = row.description(option: selectedOption(in: view))?.shown, let control = primaryControl(in: view) {
            let existing = control.accessibilityHelp() ?? ""
            control.setAccessibilityHelp(existing.isEmpty ? help : existing + "\n" + help)
        }
        return view
    }

    // MARK: 设置搜索跳到一行（1.0.18 新表面稿第 2 节第 4 条）

    /// 设置搜索选中了一行：讲解带像点住那一行一样演它（发 .click）；命中的是分段控件的某一段，演那一段
    /// （发 .hoverOption）。和指针点住走同一条路。讲解带还没接线（刚换页）就先记下，接好了再做。
    /// 这一页没有讲解带、这一行没挂牌：不做什么（讲解带照旧演页默认）。
    static func focus(row: NSView, option: Int?) {
        var top: NSView = row
        while let parent = top.superview { top = parent }
        guard let band = band(in: top, containing: row) else { return }
        band.host.focus(view: row, option: option)
    }

    private static func band(in view: NSView, containing row: NSView) -> SettingsExplainerBand? {
        if let band = view as? SettingsExplainerBand, let root = band.pageRoot, row.isDescendant(of: root) { return band }
        for sub in view.subviews {
            if let found = band(in: sub, containing: row) { return found }
        }
        return nil
    }

    private var pendingFocus: (view: NSView, option: Int?)?

    func focus(view: NSView, option: Int?) {
        guard observedWindow != nil else {
            pendingFocus = (view, option)
            return
        }
        pendingFocus = nil
        // 行本身挂了牌，或者牌挂在它外面一层 / 里面一层（对照表的一行）。
        var candidate: NSView? = view
        var id: Int?
        while let current = candidate, id == nil {
            id = rows.first(where: { $0.value.view === current })?.key
            candidate = current.superview
        }
        if id == nil { id = rows.first(where: { $0.value.view?.isDescendant(of: view) == true })?.key }
        guard let id, let state = rowState(id) else { return }
        if director.selected?.id != id { send(.click(state)) }
        if let option, case .options = state.row.kind { send(.hoverOption(state, option: option)) }
    }

    // MARK: 整页重建时接着用的状态

    private struct Saved {
        var director: ExplainerDirector
        var detachedAt: TimeInterval?
    }
    private static var saved: [String: Saved] = [:]
    /// 拆下到装上隔这么久以内，算同一页重建（不是切页回来）。
    private static let rebuildWindow: TimeInterval = 0.5

    // MARK: 实例

    private(set) var page: ExplainerPage
    let band: SettingsExplainerView
    private weak var root: NSView?
    private weak var observedWindow: NSWindow?
    private var director: ExplainerDirector
    private var rows: [Int: Weak] = [:]
    private var trackingArea: NSTrackingArea?
    private var observers: [NSObjectProtocol] = []
    private var focusObservation: NSKeyValueObservation?
    private var clickRecognizers: [NSClickGestureRecognizer] = []
    /// 分段控件现在悬停的是第几段（没悬停是 nil）。
    private var hoveredSegment: (row: Int, segment: Int)?

    private final class Weak { weak var view: NSView?; init(_ view: NSView) { self.view = view } }

    init(page: ExplainerPage, band: SettingsExplainerView) {
        self.page = page
        self.band = band
        director = ExplainerDirector(page: page)
        super.init()
        band.onLoopsFinished = { [weak self] id in self?.send(.loopsFinished(id)) }
    }
    required init?(coder: NSCoder) { nil }

    /// 讲解带进了窗口：在整页上找挂牌的行、装悬停与焦点、接开关；拿到系统状态后开演。
    func attach(root: NSView) {
        guard let window = root.window else { return }
        detach()
        self.root = root
        observedWindow = window
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = Self.saved[page.id], let at = previous.detachedAt, now - at < Self.rebuildWindow {
            director = previous.director
        } else {
            director = ExplainerDirector(page: page, environment: environment(of: window))
        }
        band.usesMouse = !PointingDevices.hasTrackpad()
        collectRows(in: root)
        installTracking(on: root)
        observe(window)
        if let current = director.current {
            // 重建：直接摆上次的样子，再按新行的状态对一遍（开关可能刚拨过）。
            var restore = current
            restore.transition = .instant
            restore.announces = false
            band.apply(restore)
            if let hovered = director.hovered, let state = rowState(hovered.id) { send(.rowChanged(state)) }
            send(.environment(environment(of: window)))
        } else {
            // 窗口还不在最前时，状态机先停在关键帧，等看得见了再演。
            send(.openPage)
        }
        enterRowUnderPointer()
        if let pendingFocus { focus(view: pendingFocus.view, option: pendingFocus.option) }
    }

    /// 同一页换了一组行（例如手势页的分段）：换页默认，行的接线不动。指着的、选住的都放开，
    /// 新的页默认从头演（已经演过的那一组回来只摆关键帧）。
    func switchPage(_ next: ExplainerPage) {
        guard next.id != page.id else { return }
        if observedWindow != nil { Self.saved[page.id] = Saved(director: director, detachedAt: nil) }
        page = next
        let played = Self.saved[next.id]?.director.pagePlayed ?? false
        director = ExplainerDirector(page: next, environment: environment(of: observedWindow), pagePlayed: played)
        pointerRow = nil
        hoveredSegment = nil
        guard observedWindow != nil else { return }
        send(.openPage)
        enterRowUnderPointer()
    }

    func detach() {
        if observedWindow != nil { Self.saved[page.id] = Saved(director: director, detachedAt: ProcessInfo.processInfo.systemUptime) }
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        focusObservation?.invalidate()
        focusObservation = nil
        if let trackingArea, let root { root.removeTrackingArea(trackingArea) }
        trackingArea = nil
        clickRecognizers.forEach { $0.view?.removeGestureRecognizer($0) }
        clickRecognizers.removeAll()
        rows.removeAll()
        observedWindow = nil
        band.stop()
    }

    private func send(_ event: ExplainerDirector.Event) {
        if let next = director.handle(event) { band.apply(next) }
    }

    // MARK: 行

    /// 深度优先给挂牌的视图编号：整页重建后同一行编号不变，状态机能接着用。
    private func collectRows(in root: NSView) {
        var index = 0
        func walk(_ view: NSView) {
            if Self.tags.object(forKey: view) != nil {
                rows[index] = Weak(view)
                hook(view, id: index)
                index += 1
            }
            view.subviews.forEach(walk)
        }
        walk(root)
    }

    private func hook(_ view: NSView, id: Int) {
        // 开关、分段控件：动作照旧发给原来的 target，之后这里再读一次新状态。
        for control in Self.controls(in: view) {
            ExplainerActionRelay.attach(to: control) { [weak self] in
                guard let self, let state = self.rowState(id) else { return }
                self.send(.rowChanged(state))
            }
        }
        // 点一下行（不是控件）：选住 / 放开。
        let click = NSClickGestureRecognizer(target: self, action: #selector(rowClicked(_:)))
        click.delaysPrimaryMouseButtonEvents = false
        view.addGestureRecognizer(click)
        clickRecognizers.append(click)
    }

    private func rowState(_ id: Int) -> ExplainerDirector.RowState? {
        guard let view = rows[id]?.view, let tag = Self.tags.object(forKey: view) else { return nil }
        let toggle = Self.controls(in: view).compactMap { $0 as? NSSwitch }.first
        return ExplainerDirector.RowState(id: id, row: tag.row, isOn: toggle.map { $0.state == .on },
                                          selectedOption: Self.selectedOption(in: view))
    }

    @objc private func rowClicked(_ recognizer: NSClickGestureRecognizer) {
        guard let view = recognizer.view else { return }
        // 点在开关、按钮、分段上的不算选住。
        let point = recognizer.location(in: view)
        if let hit = view.hitTest(view.convert(point, to: view.superview)), hit is NSControl || hit.superview is NSControl { return }
        guard let id = rows.first(where: { $0.value.view === view })?.key, let state = rowState(id) else { return }
        send(.click(state))
    }

    // MARK: 悬停与焦点

    private func installTracking(on root: NSView) {
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        root.addTrackingArea(area)
        trackingArea = area
    }

    /// 指针下最里面那个挂牌的视图（对照表的一行比它所在的行更里面）。
    private func taggedRow(at windowPoint: NSPoint) -> Int? {
        guard let root, let hit = root.hitTest(root.convert(windowPoint, from: nil)) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== root.superview {
            if let id = rows.first(where: { $0.value.view === current })?.key { return id }
            view = current.superview
        }
        return nil
    }

    private var pointerRow: Int?

    override func mouseMoved(with event: NSEvent) { pointerMoved(to: event.locationInWindow) }
    override func mouseEntered(with event: NSEvent) { pointerMoved(to: event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { pointerMoved(to: nil) }

    private func enterRowUnderPointer() {
        guard let window = observedWindow else { return }
        let point = window.mouseLocationOutsideOfEventStream
        guard window.contentView?.bounds.contains(window.contentView?.convert(point, from: nil) ?? .zero) == true else { return }
        pointerMoved(to: point)
    }

    private func pointerMoved(to point: NSPoint?) {
        let id = point.flatMap(taggedRow(at:))
        if id != pointerRow {
            if let old = pointerRow { send(.exit(rowID: old)); hoveredSegment = nil }
            pointerRow = id
            if let id, let state = rowState(id) { send(.enter(state)) }
        }
        segmentHover(at: point)
    }

    /// 分段控件逐段悬停：指针停在另一段上先演那一段（不改设置），移开回到选中的那一段。
    private func segmentHover(at point: NSPoint?) {
        guard let id = pointerRow, let view = rows[id]?.view, let state = rowState(id),
              case .options = state.row.kind,
              let segmented = Self.controls(in: view).compactMap({ $0 as? NSSegmentedControl }).first else {
            hoveredSegment = nil
            return
        }
        var segment: Int?
        if let point {
            let local = segmented.convert(point, from: nil)
            if segmented.bounds.contains(local), segmented.segmentCount > 0 {
                segment = Self.segment(at: local.x, in: segmented)
            }
        }
        let previous = hoveredSegment?.row == id ? hoveredSegment?.segment : nil
        guard segment != previous else { return }
        if let segment {
            hoveredSegment = (id, segment)
            send(.hoverOption(state, option: segment))
        } else {
            hoveredSegment = nil
            send(.leaveOption(state))
        }
    }

    /// x 落在第几段：有固定宽度的段照宽度量，没有的平分剩下的宽度。
    private static func segment(at x: CGFloat, in control: NSSegmentedControl) -> Int {
        let count = control.segmentCount
        let fixed = (0..<count).map { control.width(forSegment: $0) }
        let free = fixed.filter { $0 <= 0 }.count
        let remaining = max(0, control.bounds.width - fixed.filter { $0 > 0 }.reduce(0, +))
        var edge: CGFloat = 0
        for i in 0..<count {
            edge += fixed[i] > 0 ? fixed[i] : remaining / CGFloat(max(free, 1))
            if x < edge { return i }
        }
        return count - 1
    }

    private func focusChanged(_ responder: NSResponder?) {
        guard let view = responder as? NSView, let root, view.isDescendant(of: root) else { return }
        var current: NSView? = view
        while let candidate = current, candidate !== root {
            if let id = rows.first(where: { $0.value.view === candidate })?.key {
                guard id != pointerRow, let state = rowState(id) else { return }
                if let old = pointerRow { send(.exit(rowID: old)) }
                pointerRow = id
                send(.enter(state))
                return
            }
            current = candidate.superview
        }
    }

    // MARK: 系统状态

    private func environment(of window: NSWindow?) -> ExplainerDirector.Environment {
        let visible = window.map { $0.isKeyWindow && $0.occlusionState.contains(.visible) && !$0.isMiniaturized } ?? false
        return ExplainerDirector.Environment(reduceMotion: Motion.reduced, lowPower: PowerPolicy.shared.tier != .normal, visible: visible)
    }

    private func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
                                          NSWindow.didResignKeyNotification, NSWindow.didMiniaturizeNotification,
                                          NSWindow.didDeminiaturizeNotification]
        for name in names {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.environmentChanged() }
            })
        }
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // 关窗（窗口只是收起，视图还在里面）：换一个新的状态机，下次打开从页默认重新演两轮。
                var hidden = self.environment(of: nil)
                hidden.visible = false
                self.director = ExplainerDirector(page: self.page, environment: hidden)
                self.pointerRow = nil
                self.band.stop()
                self.send(.openPage)
            }
        })
        observers.append(center.addObserver(forName: PowerPolicy.tierDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.environmentChanged() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.environmentChanged() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.environmentChanged() }
        })
        focusObservation = window.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
            MainActor.assumeIsolated { self?.focusChanged(window.firstResponder) }
        }
    }

    private func environmentChanged() {
        send(.environment(environment(of: observedWindow)))
    }

    // MARK: 在行里找控件

    private static func controls(in view: NSView) -> [NSControl] {
        var found: [NSControl] = []
        func walk(_ v: NSView) {
            if let control = v as? NSControl, control is NSSwitch || control is NSSegmentedControl || control is NSPopUpButton {
                found.append(control)
                return
            }
            v.subviews.forEach(walk)
        }
        walk(view)
        return found
    }

    private static func primaryControl(in view: NSView) -> NSControl? {
        controls(in: view).first
    }

    private static func selectedOption(in view: NSView) -> Int? {
        for control in controls(in: view) {
            if let segmented = control as? NSSegmentedControl { return segmented.selectedSegment >= 0 ? segmented.selectedSegment : nil }
            if let popup = control as? NSPopUpButton { return popup.indexOfSelectedItem >= 0 ? popup.indexOfSelectedItem : nil }
        }
        return nil
    }
}

/// 这台 Mac 连没连着触控板（内建的或妙控板）：讲解带左块画触控板还是鼠标。讲解带进窗口时读一次，
/// 只看有没有，不读手指、不监听、不存（隐私登记 pointing-device）。读不到时当作有触控板。
enum PointingDevices {
    static func hasTrackpad() -> Bool {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("AppleMultitouchDevice"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return true }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            // 妙控鼠标也是多点触控设备；触控板才有这一项，或产品名里带 Trackpad。
            func property(_ key: String) -> CFTypeRef? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            if property("TrackpadThreeFingerDrag") != nil { return true }
            if let product = property("Product") as? String, product.contains("Trackpad") { return true }
            service = IOIteratorNext(iterator)
        }
        return false
    }
}

/// 开关、分段控件的动作中继：原来的 target / action 照发，之后再告诉讲解带。
/// 中继对象挂在控件上（随控件释放），重复接线时只换回调，不叠两层。
@MainActor
final class ExplainerActionRelay: NSObject {
    private weak var originalTarget: AnyObject?
    private let originalAction: Selector?
    private var after: () -> Void
    private static let relays = NSMapTable<NSControl, ExplainerActionRelay>.weakToStrongObjects()

    private init(target: AnyObject?, action: Selector?, after: @escaping () -> Void) {
        originalTarget = target
        originalAction = action
        self.after = after
    }

    static func attach(to control: NSControl, after: @escaping () -> Void) {
        if let existing = relays.object(forKey: control) {
            existing.after = after
            return
        }
        let relay = ExplainerActionRelay(target: control.target, action: control.action, after: after)
        relays.setObject(relay, forKey: control)
        control.target = relay
        control.action = #selector(fire(_:))
    }

    @objc private func fire(_ sender: NSControl) {
        if let originalAction { NSApp.sendAction(originalAction, to: originalTarget, from: sender) }
        after()
    }
}

/// 页顶的讲解带：一个视图带着它的 host，进窗口接线、出窗口拆线。
@MainActor
final class SettingsExplainerBand: NSView {
    let host: SettingsExplainerHost
    /// 在哪一页的根视图上找行（makeSettingsPageRoot 给）。
    weak var pageRoot: NSView?

    init(page: ExplainerPage, scale: CGFloat = 1) {
        let view = SettingsExplainerView(scale: scale)
        host = SettingsExplainerHost(page: page, band: view)
        super.init(frame: NSRect(origin: .zero, size: view.intrinsicContentSize))
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.widthAnchor.constraint(equalToConstant: view.intrinsicContentSize.width),
            view.heightAnchor.constraint(equalToConstant: view.intrinsicContentSize.height),
            trailingAnchor.constraint(greaterThanOrEqualTo: view.trailingAnchor),
            bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { nil }

    /// 同一页换了一组行（手势页的分段）：换页默认，见 `SettingsExplainerHost.switchPage`。
    func switchPage(_ page: ExplainerPage) { host.switchPage(page) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let root = pageRoot ?? superview {
            // 等这一拍的布局排完（整页重建时行刚放进去）再接线。
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.host.attach(root: root)
            }
        } else {
            host.detach()
        }
    }
}
