// 卡住时刘海开口：读前台 App、焦点、菜单，前后比一比，定下说不说（docs/stuck-habits.md 第一部分 §4.2–4.6）。
//
// HabitWorker 在自己的串行队列上跑：钩子（HabitKeys）报上来的每一下都排到这里，AX 读取不上主线程。
// 每个 AX 元素的等待上限设 0.3 秒；菜单按 pid 缓存（某个 App 第一次按到候选键时才扫一次，App 退出时作废；
// 读不到的记 10 秒，这期间连按也不重扫），每个菜单最多看 60 项。没有轮询：只有按键、点按、滚动和系统通知来了才做事，
// 等待都是一次性的 asyncAfter。不用读 AX 就能挡掉的（名单里的 App、不在访达文件列表里的 delete）最先挡，不写日志。
// HabitCenter 在主线程：管开关（来处、刘海和教学的设置、那本账）、把决定交给刘海（Notch+Habit.swift），
// 以及只能在主线程看的事（WindowShade 收起了哪扇窗）。

import Cocoa
import Carbon
import ApplicationServices

// MARK: - AX 小工具（每个元素都设 0.3 秒上限，不动全局的 2 秒）

private enum HabitAX {
    static let timeout: Float = 0.3

    static func app(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let child = value as! AXUIElement
        AXUIElementSetMessagingTimeout(child, timeout)
        return child
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }

    static func range(_ value: Any?) -> CFRange? {
        guard let value, CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        var range = CFRange()
        guard AXValueGetType(ax) == .cfRange, AXValueGetValue(ax, .cfRange, &range) else { return nil }
        return range
    }

    static func range(_ element: AXUIElement, _ attribute: String) -> CFRange? { range(value(element, attribute)) }

    static func parameterized(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value) == .success else {
            return nil
        }
        return value
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    static func parent(_ element: AXUIElement) -> AXUIElement? { self.element(element, kAXParentAttribute) }

    /// 一次读几个属性；读不到的那一项是 nil。
    static func values(_ element: AXUIElement, _ attributes: [String]) -> [Any?] {
        var result: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, AXCopyMultipleAttributeOptions(),
                                                     &result) == .success,
              let array = result as? [Any], array.count == attributes.count else {
            return Array(repeating: nil, count: attributes.count)
        }
        // 读不到的属性以 AXValue 错误占位：只留真正的值。
        return array.map { item -> Any? in
            let ref = item as CFTypeRef
            if CFGetTypeID(ref) == AXValueGetTypeID(), AXValueGetType(ref as! AXValue) == .axError { return nil }
            return item
        }
    }

    static func windowID(_ element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }
}

// MARK: - 菜单

/// 一个 App 菜单里的快捷键：M 用它看“有 Mac 那一下、没有到达的这个组合”，说话时用那一项的标题，点提示时按它。
struct HabitMenuIndex {
    struct Item {
        let title: String
        let element: AXUIElement
    }
    var items: [HabitMenuKey: Item] = [:]
    var readable = false
    /// App 名那个菜单（菜单栏第二项）：🌐M 那条点提示时把它打开。
    var appMenu: AXUIElement?

    static let itemsPerMenu = 60

    static func scan(pid: pid_t) -> HabitMenuIndex {
        var index = HabitMenuIndex()
        let app = HabitAX.app(pid)
        guard let bar = HabitAX.element(app, kAXMenuBarAttribute) else { return index }
        let barItems = HabitAX.children(bar)
        index.readable = barItems.count > 1
        if barItems.count > 1 { index.appMenu = barItems[1] }
        let attributes = [kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute, kAXMenuItemCmdVirtualKeyAttribute,
                          kAXTitleAttribute]
        // 0 是苹果菜单，不看。
        for barItem in barItems.dropFirst() {
            AXUIElementSetMessagingTimeout(barItem, HabitAX.timeout)
            for menu in HabitAX.children(barItem) {
                AXUIElementSetMessagingTimeout(menu, HabitAX.timeout)
                for item in HabitAX.children(menu).prefix(itemsPerMenu) {
                    AXUIElementSetMessagingTimeout(item, HabitAX.timeout)
                    let values = HabitAX.values(item, attributes)
                    let character = (values[0] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    let virtualKey = HabitAX.int(values[2])
                    guard character != nil || virtualKey != nil,
                          let key = HabitMenuKey(character: character, virtualKey: virtualKey,
                                                 modifiers: HabitAX.int(values[1])),
                          index.items[key] == nil else { continue }
                    index.items[key] = Item(title: values[3] as? String ?? "", element: item)
                }
            }
        }
        return index
    }

    /// M：Mac 那一下在不在菜单里、到达的这个组合在不在；再给出 Mac 那一项（说话用标题，点提示时按它）。
    /// 只找要教的那一下：Alt+F4 教的是 ⌘W，菜单里没有 ⌘W 时不能拿 ⌘Q 那一项来说、来按（那是退出整个 App）。
    func evidence(_ rule: HabitRule, pressed: HabitCombo?) -> (HabitMenuEvidence, Item?) {
        guard readable else { return (.unreadable, nil) }
        let mac = rule.taughtCombo.flatMap { items[HabitMenuKey($0)] }
        let foreign = pressed.map { items[HabitMenuKey($0)] != nil } ?? false
        return (.read(hasMac: mac != nil, hasForeign: foreign), mac)
    }
}

// MARK: - 前台 App

/// 一个 App 的底细（按 pid 缓存，App 退出时作废）。
struct HabitAppFacts {
    var bundleID: String?
    var kind: HabitAppKind = .native
    var excluded = false
    var finder = false
    var browser = false
    var chromium = false
    var player = false

    /// 播放器、演示：全屏时不说。
    static let players: Set<String> = [
        "com.apple.iWork.Keynote", "com.apple.QuickTimePlayerX", "com.colliderli.iina", "org.videolan.vlc", "com.apple.TV",
    ]

    static func read(pid: pid_t) -> HabitAppFacts {
        var facts = HabitAppFacts()
        let app = NSRunningApplication(processIdentifier: pid)
        let bundleID = app?.bundleIdentifier
        facts.bundleID = bundleID
        let executable = app?.executableURL?.path
        facts.excluded = HabitExclusions.isExcluded(bundleID: bundleID, executablePath: executable)
        facts.finder = bundleID == "com.apple.finder"
        facts.browser = HabitExclusions.isBrowser(bundleID)
        facts.chromium = HabitExclusions.isChromium(bundleID)
        facts.player = bundleID.map { players.contains($0) } ?? false
        guard let url = app?.bundleURL else { return facts }
        let bundle = Bundle(url: url)
        if HabitExclusions.isGame(category: bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String,
                                  executablePath: executable) {
            facts.excluded = true
        }
        let files = FileManager.default
        // VS Code 系的分支（名字不一定认得出）：包里有 Resources/app/product.json。
        if files.fileExists(atPath: url.appendingPathComponent("Contents/Resources/app/product.json").path) { facts.excluded = true }
        if facts.browser {
            facts.kind = .browser
        } else {
            let frameworks = url.appendingPathComponent("Contents/Frameworks")
            let shells = ["Electron Framework.framework", "Chromium Embedded Framework.framework", "QtWebEngineCore.framework"]
            if shells.contains(where: { files.fileExists(atPath: frameworks.appendingPathComponent($0).path) }) {
                facts.kind = .webShell
            }
        }
        return facts
    }
}

/// 焦点读到的样子。
struct HabitFocusRead {
    var kind: HabitFocus = .unknown
    var element: AXUIElement?
    var selection: Int?
    var characters: Int?
    var caret: CFRange?
    var composing = false
    /// 网页终端的输入框、网页里的远程桌面和网页 IDE：不说。
    var excluded = false
    /// 列表里有选中的项（访达）。
    var selectedItems = false
}

// MARK: - 队列这一边

/// 交给刘海的一句话，和点一下提示时替他做的那一下。
struct HabitDecision {
    let rule: HabitRule
    let lines: (title: String, subtitle: String)
    let demo: HabitDemo
    let action: HabitAction
    let bundleID: String?
}

enum HabitAction {
    /// 按下前台 App 菜单里 Mac 的那一项（拷贝、存储、关闭标签页……）；按不动就把那一下发给这个 App。
    case pressMenu(AXUIElement, pid: pid_t, fallback: HabitCombo?)
    /// 把 Mac 的那一下发给这个 App（⌘← ⌘→）。
    case postKey(HabitCombo, pid: pid_t)
    /// 系统快捷键（⌥⌘esc、⇧⌘4、聚焦搜索）：从键盘那一层发。
    case systemKey(HabitCombo)
    /// 打开前台 App 名那个菜单。
    case openMenu(AXUIElement)
    /// 回到主屏幕（和点一下刘海一样）。
    case home
    /// 排这扇窗口（铺满屏幕、左半屏）。
    case place(GestureAction)
    /// 切到英文输入（ABC）。
    case selectASCII
    case none
}

final class HabitWorker: @unchecked Sendable {
    /// 主线程算好整体换上（在队列上读）。
    struct Settings {
        var active: Set<HabitRule> = []
        /// 当前键盘布局下字母键的位置和 ANSI 一致（不一致时字母那几条不说）。
        var lettersMatch = true
        var inputSource: String?
        var imeVariant: HabitVariant = .plain
        var natural = true
        var spotlight: HabitCombo?
        var dockPID: pid_t = 0
        /// 探针在听：每一次判定都报上去（平时只把读过 AX 的判定写进日志）。
        var traces = false
    }

    let queue = DispatchQueue(label: "WindowShade.Habits", qos: .utility)
    private let ownPID = getpid()

    // 以下只在 queue 上读写。
    private var settings = Settings()
    private var quietUntil: TimeInterval = 0
    private var repeats = HabitRepeats()
    private var clipboard = HabitClipboard()
    private var hides = HabitHideWatch()
    private var swipes = HabitDesktopSwipes()
    private var shiftTaps = HabitShiftTaps()
    private var lastMac: [HabitRule: TimeInterval] = [:]
    private var factsCache: [pid_t: HabitAppFacts] = [:]
    private var menus: [pid_t: HabitMenuIndex] = [:]
    private var unreadableMenus: [pid_t: TimeInterval] = [:]
    private var undoMiss: (at: TimeInterval, characters: Int?)?
    private var altBefore: (pid: pid_t, characters: Int?, focus: HabitFocus)?
    private var menuWatch: (at: TimeInterval, pid: pid_t, clicked: Bool)?
    private var dockDrag: (bundleID: String, press: CGPoint, at: TimeInterval)?
    private var scrollOnDesktop = false
    /// 上一次真去看过、指针下不是桌面的地方和时间：同一处接着滚（看文档、网页）时 3 秒内不再要窗口列表。
    private var notDesktop: (point: CGPoint, at: TimeInterval)?
    private var taken: (combos: Set<HabitCombo>, at: TimeInterval)?
    private var bindings: (combos: Set<HabitCombo>, modified: Date?)?
    private var access: (sticky: Bool, slow: Bool, mouseKeys: Bool, keyboardAccess: Bool, at: TimeInterval)?

    /// 定下来要说：交给主线程（那边再看一次账和节奏）。
    var onDecision: (@Sendable (HabitDecision) -> Void)?
    /// 他自己按了 Mac 那一下。
    var onLearned: (@Sendable (HabitRule) -> Void)?
    /// 在文本里按了 ⌃E、⌃K。
    var onEmacs: (@Sendable () -> Void)?
    /// 盯一会儿所有按键和点按（交给钩子）。
    var onWatch: (@Sendable (TimeInterval) -> Void)?
    /// 鼠标按下、松开（主线程看 WindowShade 收起了哪扇）。
    var onMouse: (@Sendable (HabitKeys.Observation) -> Void)?
    /// 每一次判定的结果（探针看；只在 Settings.traces 开着时报）。
    var onVerdict: (@Sendable (HabitRule, String) -> Void)?

    func update(_ next: Settings) { queue.async { self.settings = next } }
    func setQuiet(until time: TimeInterval) { queue.async { self.quietUntil = time } }
    func forget(pid: pid_t) {
        queue.async { self.factsCache[pid] = nil; self.menus[pid] = nil; self.unreadableMenus[pid] = nil }
    }

    /// 探针用：清掉时间窗和缓存。
    func resetForProbe() {
        queue.async {
            self.repeats = HabitRepeats(); self.clipboard = HabitClipboard(); self.hides = HabitHideWatch()
            self.swipes = HabitDesktopSwipes(); self.shiftTaps = HabitShiftTaps(); self.lastMac = [:]
            self.factsCache = [:]; self.menus = [:]; self.unreadableMenus = [:]; self.quietUntil = 0; self.undoMiss = nil
            self.notDesktop = nil
        }
    }

    // MARK: 入口

    /// 钩子线程上调用：只排队。
    func observe(_ observation: HabitKeys.Observation) {
        queue.async { self.handle(observation) }
    }

    private func handle(_ observation: HabitKeys.Observation) {
        switch observation {
        case let .key(signals, combo, at, target, pasteboard, sinceLetter, sinceFn):
            let pid = target > 0 ? target : frontPID()
            guard pid != ownPID else { return }
            for signal in signals {
                switch signal {
                case .mac(let rule): mac(rule, at: at, pasteboard: pasteboard)
                case .emacs: emacs(pid: pid)
                case .foreign(let rule):
                    foreign(rule, combo: combo, at: at, pid: pid, pasteboard: pasteboard, sinceLetter: sinceLetter, sinceFn: sinceFn)
                }
            }
        case let .altDigitsBegan(_, target): altBegan(pid: target > 0 ? target : frontPID())
        case let .altDigitsEnded(count, at, target): altEnded(count: count, at: at, pid: target > 0 ? target : frontPID())
        case let .shiftTap(at): shiftTap(at: at)
        case let .activity(_, target):
            hides.activity(pid: target, ignoring: [settings.dockPID, ownPID, 0])
        case let .mouseDown(at, location, target, _):
            if var watch = menuWatch, at - watch.at <= 3, Self.inMenuBar(location) {
                watch.clicked = true
                menuWatch = watch
            }
            if target == settings.dockPID, settings.active.contains(.dockRemoved) { dockPressed(at: location, time: at) }
            if settings.active.contains(.titleDoubleClick) || settings.active.contains(.titleFlickUp) { onMouse?(observation) }
        case let .mouseUp(at, location, _, _, _, _):
            if let drag = dockDrag { dockReleased(drag, at: location, time: at) }
            if settings.active.contains(.titleDoubleClick) || settings.active.contains(.titleFlickUp) { onMouse?(observation) }
        case let .scrollBegan(at, location):
            scrollOnDesktop = false
            guard settings.active.contains(.desktopSearch) else { return }
            // 同一处刚看过不是桌面：3 秒内不再去要整张窗口列表（从真看的那次算起，不往后顺延）。
            if let last = notDesktop, at - last.at < 3, hypot(location.x - last.point.x, location.y - last.point.y) < 24 { return }
            scrollOnDesktop = Self.desktop(at: location)
            notDesktop = scrollOnDesktop ? nil : (location, at)
        case let .scrollEnded(at, deltaY):
            guard scrollOnDesktop, settings.active.contains(.desktopSearch) else { return }
            scrollOnDesktop = false
            let travel = HabitDesktopSwipes.fingerTravel(deltaY: deltaY, natural: settings.natural)
            if swipes.swipe(fingersDown: travel, onDesktop: true, at: at) { desktopSearch() }
        }
    }

    // MARK: Mac 那一下、Emacs 键

    private func mac(_ rule: HabitRule, at: TimeInterval, pasteboard: Int?) {
        lastMac[rule] = at
        if rule.watchesPasteboard, let pasteboard { clipboard.sample(pasteboard, at: at, macCopy: rule == .copy || rule == .cut) }
        guard settings.active.contains(rule) else { return }
        onLearned?(rule)
    }

    private func emacs(pid: pid_t) {
        guard !facts(pid).excluded else { return }
        let focus = readFocus(pid: pid, facts: facts(pid))
        if focus.kind == .text { onEmacs?() }
    }

    // MARK: 旧习惯的那一下

    private func foreign(_ rule: HabitRule, combo: HabitCombo, at: TimeInterval, pid: pid_t, pasteboard: Int?,
                         sinceLetter: TimeInterval, sinceFn: TimeInterval) {
        guard settings.active.contains(rule) else { return }
        // 单按 delete、Del 只在访达里才可能是想删文件：切 App 那一瞬还留在表里、落到别的 App 上的，到这里就放过，什么都不读。
        if rule.foreignOnlyInFinder, !facts(pid).finder { return }
        // ⌃V 的前因要拿这一下之前的剪贴板比，所以先算前因、再记这一次。
        var antecedent = false
        if rule == .paste {
            antecedent = repeats.copyMissed(before: at, scale: scale)
                || (pasteboard.map { clipboard.changedWithoutMacCopy(now: $0, at: at) } ?? false)
        }
        if rule.watchesPasteboard, let pasteboard { clipboard.sample(pasteboard, at: at) }
        // 刚说过一条（五分钟内）：什么都不会说，不去读 AX。
        guard Date().timeIntervalSince1970 >= quietUntil else { return }
        switch rule {
        case .hideApp:
            let hadWindows = WindowListCache.shared.onScreenWindows(ofPID: pid)
                .contains { ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 }
            hides.commandH(pid: pid, at: at, hadWindows: hadWindows)
        case .menuBar:
            menuBarPressed(at: at, pid: pid)
        case .lineEnds:
            lineEnds(combo: combo, at: at, pid: pid, sinceFn: sinceFn)
        default:
            generic(rule, combo: combo, at: at, pid: pid, pasteboard: pasteboard, antecedent: antecedent, sinceLetter: sinceLetter)
        }
    }

    /// 大多数按键规则：先记下按之前的样子（P），再看底细（名单、占用、焦点、菜单），0.3 秒后比前后，0.8 秒宽限到了再判（W）。
    private func generic(_ rule: HabitRule, combo: HabitCombo, at: TimeInterval, pid: pid_t, pasteboard: Int?,
                         antecedent: Bool, sinceLetter: TimeInterval) {
        let app = facts(pid)
        // 名单里的 App（终端、IDE……）：在那里 ⌃C 这些天天在按，不读 AX、不要窗口列表、不写日志。
        if app.excluded {
            var s = HabitSituation()
            s.excluded = true
            report(rule, s, app: app, quiet: true)
            return
        }
        // 访达里的 delete：先看焦点。改名、搜索框里打字的退格，没选中文件的，刚按过字母（按名字选文件）的，到这里就放过。
        var trashFocus: HabitFocusRead?
        if rule == .trash {
            let focus = readFocus(pid: pid, facts: app, items: true)
            guard focus.kind == .list, focus.selectedItems, !focus.composing, sinceLetter > HabitRules.letterQuiet else {
                var s = HabitSituation()
                s.finder = app.finder
                s.focus = focus.kind
                s.finderSelection = focus.selectedItems
                s.composing = focus.composing
                s.sinceLetter = sinceLetter
                report(rule, s, app: app, quiet: true)
                return
            }
            trashFocus = focus
        }
        // P 的“之前”：在读占用、焦点、菜单之前先记。第三方热键很快弹出的窗口要落在“之后”里，不然会当成没反应。
        let before = scene(pid: pid, pasteboard: pasteboard)
        var s = baseSituation(rule, combo: combo, pid: pid, app: app)
        s.sinceLetter = sinceLetter
        s.antecedent = antecedent
        if combo == HabitCombo(HabitKey.delete, [.control, .option]) { s.variant = .deleteKey }
        if combo.keyCode == HabitKey.f13, combo.modifiers == .option { s.variant = .window }
        if rule == .screenshot { s.hotkeyAppRunning = Self.hotkeyAppRunning() }
        // 占用、VoiceOver、安全输入这几道门不用读焦点就能定：先挡掉，不去读 AX。
        if s.excluded || s.taken || s.voiceOver {
            report(rule, s, app: app, quiet: true)
            return
        }
        let focus = trashFocus ?? readFocus(pid: pid, facts: app, items: rule == .cut && app.finder)
        s.focus = focus.kind
        s.selection = focus.selection
        s.composing = focus.composing
        s.finderSelection = app.finder && focus.selectedItems
        if focus.excluded { s.excluded = true }
        let evidence: (HabitMenuEvidence, HabitMenuIndex.Item?) = rule.needsMenu || rule == .closeWindow || rule == .trash
            ? menu(pid: pid).evidence(rule, pressed: combo) : (.unreadable, nil)
        s.menu = evidence.0
        let item = evidence.1
        let known = s
        queue.asyncAfter(deadline: .now() + HabitRules.settle) {
            var s = known
            let after = self.scene(pid: pid, pasteboard: rule.watchesPasteboard ? NSPasteboard.general.changeCount : nil)
            s.reacted = before.reacted(to: after)
            s.pasteboardChanged = before.pasteboardChanged(to: after)
            if rule == .paste || rule == .undo, let element = focus.element {
                let values = HabitAX.values(element, [kAXSelectedTextRangeAttribute, kAXNumberOfCharactersAttribute])
                if rule == .paste, let was = focus.caret, let now = HabitAX.range(values[0]), now.location != was.location {
                    s.variant = .pagedDown
                }
                if rule == .undo, app.kind != .native {
                    let characters = HabitAX.int(values[1])
                    let same = characters != nil && characters == focus.characters
                    if let miss = self.undoMiss, at - miss.at <= HabitRepeats.window * self.scale {
                        s.charactersUnchanged = same && miss.characters == characters
                    } else {
                        s.charactersUnchanged = same
                    }
                    if same { self.undoMiss = (at, characters) }
                }
            }
            let settled = s
            self.queue.asyncAfter(deadline: .now() + HabitRules.grace * self.scale - HabitRules.settle) {
                self.conclude(rule, settled, at: at, pid: pid, app: app, pressed: combo, item: item)
            }
        }
    }

    /// 宽限到了：他自己按了 Mac 那一下就不说（已经记成会了）；否则判，没反应的记一次（给 R 和 ⌃V 的前因）。
    private func conclude(_ rule: HabitRule, _ situation: HabitSituation, at: TimeInterval, pid: pid_t, app: HabitAppFacts,
                          pressed: HabitCombo, item: HabitMenuIndex.Item?) {
        if let mac = lastMac[rule], mac >= at {
            if settings.traces { onVerdict?(rule, "silent(learned in grace)") }
            return
        }
        var s = situation
        s.repeated = repeats.isRepeat(rule, at: at, scale: scale)
        let verdict = HabitRules.judge(rule, s)
        if !s.reacted, !s.pasteboardChanged, !s.excluded { repeats.noteMiss(rule, at: at) }
        report(rule, s, app: app, verdict: verdict)
        guard verdict == .teach else { return }
        let finderApp = app.finder
        let lines = HabitWords.lines(rule, menuTitle: item.map { freshTitle($0) }, finder: finderApp, variant: s.variant)
        let demo = HabitWords.demo(rule, pressed: pressed, variant: s.variant)
        onDecision?(HabitDecision(rule: rule, lines: lines, demo: demo, action: action(rule, pid: pid, item: item, variant: s.variant),
                                  bundleID: app.bundleID))
    }

    /// 说之前把那一项的标题再读一次（菜单是扫的时候的样子，⌘W 的标题会随标签页变）。
    private func freshTitle(_ item: HabitMenuIndex.Item) -> String {
        HabitAX.string(item.element, kAXTitleAttribute) ?? item.title
    }

    private func action(_ rule: HabitRule, pid: pid_t, item: HabitMenuIndex.Item?, variant: HabitVariant) -> HabitAction {
        switch rule {
        case .copy, .paste, .undo, .save, .closeTab, .cut, .trash, .closeWindow, .symbols:
            if let item { return .pressMenu(item.element, pid: pid, fallback: rule.taughtCombo) }
            return rule.taughtCombo.map { .postKey($0, pid: pid) } ?? .none
        case .lineEnds:
            return .postKey(HabitCombo(variant == .end ? HabitKey.right : HabitKey.left, .command), pid: pid)
        case .forceQuit, .screenshot:
            return rule.taughtCombo.map { .systemKey($0) } ?? .none
        case .imeShift: return .selectASCII
        case .hideApp: return .home
        case .menuBar: return menu(pid: pid).appMenu.map { .openMenu($0) } ?? .none
        case .dockRemoved: return .place(.leftHalf)
        case .titleDoubleClick, .titleFlickUp: return .place(.fill)
        case .desktopSearch: return settings.spotlight.map { .systemKey($0) } ?? .none
        }
    }

    // MARK: 一条一条

    /// Home / End：120ms 后光标不在行首（行尾），而且整段字都看得见（滚不动）才算没反应。
    private func lineEnds(combo: HabitCombo, at: TimeInterval, pid: pid_t, sinceFn: TimeInterval) {
        let rule = HabitRule.lineEnds
        let app = facts(pid)
        var s = baseSituation(rule, combo: combo, pid: pid, app: app)
        s.sinceFn = sinceFn
        s.variant = combo.keyCode == HabitKey.end ? .end : .home
        // 名单、占用、VoiceOver、刚按过 fn（Apple 键盘的 fn←）：不用读焦点就能定。
        if s.excluded || s.taken || s.voiceOver || sinceFn <= HabitRules.fnQuiet { report(rule, s, app: app, quiet: true); return }
        let focus = readFocus(pid: pid, facts: app)
        s.focus = focus.kind
        s.composing = focus.composing
        if focus.excluded { s.excluded = true }
        // 不在文本里（网页里按 Home、End 翻页是常事）：到这里就定了，不写日志。
        guard let element = focus.element, focus.kind.isText else { report(rule, s, app: app, quiet: true); return }
        let before = scene(pid: pid, pasteboard: nil)
        let known = s
        queue.asyncAfter(deadline: .now() + HabitRules.caretCheck) {
            var s = known
            let edge = Self.caretAtEdge(element, end: s.variant == .end)
            s.caretAtEdge = edge.atEdge
            s.wholeTextVisible = edge.wholeVisible
            s.reacted = before.reacted(to: self.scene(pid: pid, pasteboard: nil))
            let settled = s
            self.queue.asyncAfter(deadline: .now() + HabitRules.grace * self.scale - HabitRules.caretCheck) {
                self.conclude(rule, settled, at: at, pid: pid, app: app, pressed: combo, item: nil)
            }
        }
    }

    /// 光标在不在行首（行尾）；整段字是不是都在可见范围里。带参属性读不到就是 nil（不说）。
    private static func caretAtEdge(_ element: AXUIElement, end: Bool) -> (atEdge: Bool?, wholeVisible: Bool?) {
        let values = HabitAX.values(element, [kAXSelectedTextRangeAttribute, kAXNumberOfCharactersAttribute,
                                              kAXVisibleCharacterRangeAttribute])
        guard let caret = HabitAX.range(values[0]), let count = HabitAX.int(values[1]),
              let visible = HabitAX.range(values[2]) else { return (nil, nil) }
        let whole = visible.location == 0 && visible.length >= count
        guard let lineValue = HabitAX.parameterized(element, kAXLineForIndexParameterizedAttribute,
                                                    NSNumber(value: caret.location)),
              let line = HabitAX.int(lineValue),
              let rangeValue = HabitAX.parameterized(element, kAXRangeForLineParameterizedAttribute, NSNumber(value: line)),
              let lineRange = HabitAX.range(rangeValue) else { return (nil, whole) }
        if !end { return (caret.location == lineRange.location, whole) }
        // 不是最后一行的话，行尾那个换行符不算在“行尾”里。
        let last = HabitAX.parameterized(element, kAXLineForIndexParameterizedAttribute, NSNumber(value: count))
            .flatMap { HabitAX.int($0) } ?? line
        let lineEnd = lineRange.location + lineRange.length - (line < last ? 1 : 0)
        return (caret.location + caret.length >= lineEnd, whole)
    }

    /// ⌥ 加小键盘：按第一个数字时记下字数。
    private func altBegan(pid: pid_t) {
        guard settings.active.contains(.symbols), pid != ownPID else { altBefore = nil; return }
        let focus = readFocus(pid: pid, facts: facts(pid))
        altBefore = (pid, focus.characters, focus.kind)
    }

    /// 松开 ⌥：字数多了和数字个数一样多（数字原样打了出来，没出符号）。
    private func altEnded(count: Int, at: TimeInterval, pid: pid_t) {
        guard let before = altBefore, before.pid == pid, settings.active.contains(.symbols) else { return }
        altBefore = nil
        guard Date().timeIntervalSince1970 >= quietUntil, settings.inputSource != "com.apple.keylayout.UnicodeHexInput" else { return }
        let rule = HabitRule.symbols
        let app = facts(pid)
        var s = baseSituation(rule, combo: nil, pid: pid, app: app)
        s.focus = before.focus
        if accessibility().mouseKeys { s.excluded = true }
        let known = s
        queue.asyncAfter(deadline: .now() + 0.15) {
            var s = known
            let focus = self.readFocus(pid: pid, facts: app)
            s.symbolsTyped = HabitAltDigits.typedAsDigits(count: count, before: before.characters, after: focus.characters)
            let settled = s
            self.queue.asyncAfter(deadline: .now() + HabitRules.grace * self.scale - 0.15) {
                let item = self.menu(pid: pid).evidence(rule, pressed: nil).1
                self.conclude(rule, settled, at: at, pid: pid, app: app,
                              pressed: HabitCombo(HabitKey.space, [.control, .command]), item: item)
            }
        }
    }

    /// 单按 ⇧（要先上真机确认）：输入法是苹果拼音、双拼或五笔，200ms 后输入法没变，20 秒内第二次。
    private func shiftTap(at: TimeInterval) {
        guard settings.active.contains(.imeShift), Date().timeIntervalSince1970 >= quietUntil,
              let source = settings.inputSource, Self.chineseInputs.contains(source) else { return }
        queue.asyncAfter(deadline: .now() + 0.2) {
            guard self.settings.inputSource == source, self.shiftTaps.tap(at: at) else { return }
            let pid = self.frontPID()
            let app = self.facts(pid)
            var s = self.baseSituation(.imeShift, combo: nil, pid: pid, app: app)
            s.variant = self.settings.imeVariant
            self.conclude(.imeShift, s, at: at, pid: pid, app: app, pressed: HabitCombo(HabitKey.space, .control), item: nil)
        }
    }

    static let chineseInputs: Set<String> = [
        "com.apple.inputmethod.SCIM.ITABC", "com.apple.inputmethod.SCIM.Shuangpin", "com.apple.inputmethod.SCIM.WBX",
        "com.apple.inputmethod.SCIM.WBH",
    ]

    /// 🌐M：不在文本里（在文本里是打了个 m），3 秒内没有菜单打开、也没点菜单栏：一次就说。
    private func menuBarPressed(at: TimeInterval, pid: pid_t) {
        let rule = HabitRule.menuBar
        let app = facts(pid)
        var s = baseSituation(rule, combo: HabitCombo(HabitKey.m, globe: true), pid: pid, app: app)
        let focus = readFocus(pid: pid, facts: app)
        s.focus = focus.kind
        if case .silent = HabitRules.judge(rule, s) { report(rule, s, app: app); return }
        menuWatch = (at, pid, false)
        onWatch?(ProcessInfo.processInfo.systemUptime + 3)
        let known = s
        queue.asyncAfter(deadline: .now() + 3) {
            var s = known
            let clicked = self.menuWatch?.clicked ?? false
            self.menuWatch = nil
            s.menuOpened = clicked || Self.menuOnScreen()
            self.conclude(rule, s, at: at, pid: pid, app: app, pressed: HabitCombo(HabitKey.m, globe: true), item: nil)
        }
    }

    /// ⌘H：系统报告藏起、又显示了一个 App（主线程转过来）。
    func appHidden(_ pid: pid_t) {
        queue.async {
            let now = ProcessInfo.processInfo.systemUptime
            guard self.settings.active.contains(.hideApp) else { return }
            if self.hides.didHide(pid: pid, at: now) {
                self.hideApp(pid: pid)
            } else if self.hides.watching {
                self.onWatch?(now + HabitHideWatch.comeBack)
            }
        }
    }

    func appUnhidden(_ pid: pid_t) {
        queue.async {
            guard self.settings.active.contains(.hideApp),
                  self.hides.didUnhide(pid: pid, at: ProcessInfo.processInfo.systemUptime) else { return }
            self.hideApp(pid: pid)
        }
    }

    private func hideApp(pid: pid_t) {
        let rule = HabitRule.hideApp
        let app = facts(pid)
        var s = HabitSituation()
        s.voiceOver = NSWorkspace.shared.isVoiceOverEnabled
        s.excluded = app.excluded
        verdictAndDecide(rule, s, app: app, pid: pid)
    }

    /// 从 Dock 上按下：按在一个 App 图标上、而且它是留在 Dock 里的，才记下来。
    private func dockPressed(at location: CGPoint, time: TimeInterval) {
        dockDrag = nil
        let dock = HabitAX.app(settings.dockPID)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dock, Float(location.x), Float(location.y), &hit) == .success, let hit else { return }
        let values = HabitAX.values(hit, [kAXRoleAttribute, kAXSubroleAttribute, kAXURLAttribute])
        guard values[0] as? String == "AXDockItem", values[1] as? String == "AXApplicationDockItem" else { return }
        let url = (values[2] as? URL) ?? (values[2] as? String).flatMap(URL.init(string:))
        guard let url, let bundleID = Bundle(url: url)?.bundleIdentifier,
              Self.persistentApps().contains(bundleID) else { return }
        dockDrag = (bundleID, location, time)
    }

    /// 松手：像是想分屏或开窗口的地方，1 秒后看它是不是从 Dock 里没了。
    private func dockReleased(_ drag: (bundleID: String, press: CGPoint, at: TimeInterval), at location: CGPoint, time: TimeInterval) {
        dockDrag = nil
        guard time - drag.at <= 10, let screen = Self.displayBounds(containing: location),
              HabitDockDrop.looksLikeSplit(release: location, press: drag.press, screen: screen) else { return }
        queue.asyncAfter(deadline: .now() + 1) {
            guard !Self.persistentApps().contains(drag.bundleID) else { return }
            var s = HabitSituation()
            s.voiceOver = NSWorkspace.shared.isVoiceOverEnabled
            self.verdictAndDecide(.dockRemoved, s, app: HabitAppFacts(bundleID: drag.bundleID), pid: self.frontPID())
        }
    }

    /// 桌面上两指往下滑了两次：教聚焦搜索。
    private func desktopSearch() {
        var s = HabitSituation()
        s.voiceOver = NSWorkspace.shared.isVoiceOverEnabled
        verdictAndDecide(.desktopSearch, s, app: HabitAppFacts(), pid: frontPID())
    }

    /// 双击标题栏、往上甩（主线程认出来的）：判一下，要说就交回主线程。
    func shadeCollision(_ rule: HabitRule) {
        queue.async {
            var s = HabitSituation()
            s.voiceOver = NSWorkspace.shared.isVoiceOverEnabled
            self.verdictAndDecide(rule, s, app: HabitAppFacts(), pid: self.frontPID())
        }
    }

    /// 状态机已经认定的几条：只剩公共的门（VoiceOver、名单、节奏）。
    private func verdictAndDecide(_ rule: HabitRule, _ s: HabitSituation, app: HabitAppFacts, pid: pid_t) {
        guard settings.active.contains(rule), Date().timeIntervalSince1970 >= quietUntil else { return }
        let verdict = HabitRules.judge(rule, s)
        report(rule, s, app: app, verdict: verdict)
        guard verdict == .teach else { return }
        let shortcut = rule == .desktopSearch ? settings.spotlight : nil
        let lines = HabitWords.lines(rule, variant: s.variant, shortcut: shortcut?.label)
        let demo = HabitWords.demo(rule, variant: s.variant, shortcut: shortcut?.parts)
        onDecision?(HabitDecision(rule: rule, lines: lines, demo: demo, action: action(rule, pid: pid, item: nil, variant: s.variant),
                                  bundleID: app.bundleID))
    }

    // MARK: 公共的门

    /// 慢速键开着时，R 和 W 的时间窗放宽一倍。
    private var scale: Double { accessibility().slow ? 2 : 1 }

    /// G 里不用读焦点就能定的那些：名单、占用、VoiceOver、安全输入、调度中心、演示和全屏播放、键盘布局、辅助功能。
    private func baseSituation(_ rule: HabitRule, combo: HabitCombo?, pid: pid_t, app: HabitAppFacts) -> HabitSituation {
        var s = HabitSituation()
        s.app = app.kind
        s.finder = app.finder
        s.excluded = app.excluded || pid == ownPID || IsSecureEventInputEnabled()
            || MissionControlPick.isActive(in: WindowListCache.shared.onScreenWindows())
            || (app.player && Self.coversDisplay(pid: pid))
        if let combo, HabitKey.letters[combo.keyCode] != nil, !settings.lettersMatch { s.excluded = true }
        let access = accessibility()
        if access.sticky || access.mouseKeys || access.keyboardAccess { s.excluded = true }
        s.taken = HabitOccupancy.isTaken(rule, pressed: combo, taken: takenCombos())
        s.voiceOver = NSWorkspace.shared.isVoiceOverEnabled
        return s
    }

    /// 记下一次判定。quiet：不用读 AX 就挡掉的，按一下就走一遍的地方：不写日志（免得刷满、也不留下每个 App 里按键的时间），
    /// 只在探针听着时报上去。
    private func report(_ rule: HabitRule, _ s: HabitSituation, app: HabitAppFacts, verdict: HabitVerdict? = nil,
                        quiet: Bool = false) {
        guard !quiet || settings.traces else { return }
        let verdict = verdict ?? HabitRules.judge(rule, s)
        let text: String
        switch verdict {
        case .teach: text = "teach"
        case .waitForRepeat: text = "wait for a second press"
        case .silent(let reason): text = "silent(\(reason))"
        }
        if !quiet { wlog("habits: \(rule.rawValue) in \(app.bundleID ?? "?") → \(text)") }
        if settings.traces { onVerdict?(rule, text) }
    }

    // MARK: 读

    private func frontPID() -> pid_t { NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0 }

    private func facts(_ pid: pid_t) -> HabitAppFacts {
        if let cached = factsCache[pid] { return cached }
        let read = HabitAppFacts.read(pid: pid)
        factsCache[pid] = read
        return read
    }

    private func menu(pid: pid_t) -> HabitMenuIndex {
        if let cached = menus[pid] { return cached }
        // 读不到的只记 10 秒：App 可能正在启动，过一会儿再扫；这 10 秒里连按也不重扫。
        let now = ProcessInfo.processInfo.systemUptime
        if let at = unreadableMenus[pid], now - at < 10 { return HabitMenuIndex() }
        let scanned = HabitMenuIndex.scan(pid: pid)
        if scanned.readable {
            menus[pid] = scanned
            unreadableMenus[pid] = nil
        } else {
            unreadableMenus[pid] = now
        }
        return scanned
    }

    /// 焦点：角色、选区、字数、是不是在组字；浏览器里看是不是地址栏、网页是不是名单里的网址；网页终端的输入框。
    private func readFocus(pid: pid_t, facts app: HabitAppFacts, items: Bool = false) -> HabitFocusRead {
        var read = HabitFocusRead()
        guard pid > 0, let element = HabitAX.element(HabitAX.app(pid), kAXFocusedUIElementAttribute) else { return read }
        read.element = element
        let values = HabitAX.values(element, [kAXRoleAttribute, kAXSubroleAttribute, "AXEditableAncestor",
                                              kAXSelectedTextRangeAttribute, kAXNumberOfCharactersAttribute,
                                              kAXDescriptionAttribute, "AXMarkedTextRange"])
        let role = values[0] as? String
        let editable = values[2] != nil
        read.caret = HabitAX.range(values[3])
        read.selection = read.caret.map { $0.length }
        read.characters = HabitAX.int(values[4])
        if values[5] as? String == HabitExclusions.webTerminalDescription { read.excluded = true }
        if let marked = HabitAX.range(values[6]), marked.length > 0 { read.composing = true }
        var inToolbar = false
        if app.browser, let role, HabitFocus.textRoles.contains(role) || editable {
            var node = HabitAX.parent(element)
            for _ in 0..<4 {
                guard let current = node else { break }
                if HabitAX.string(current, kAXRoleAttribute) == "AXToolbar" { inToolbar = true; break }
                node = HabitAX.parent(current)
            }
        }
        read.kind = HabitFocus.classify(role: role, subrole: values[1] as? String, editable: editable, browser: app.browser,
                                        chromium: app.chromium, inToolbar: inToolbar)
        // 网页里：往上找到网页那一层，读网址，比对名单（远程桌面、网页 IDE、网页终端）。
        if app.kind != .native, !inToolbar {
            var node: AXUIElement? = element
            for _ in 0..<24 {
                guard let current = node else { break }
                if HabitAX.string(current, kAXRoleAttribute) == "AXWebArea" {
                    let url = HabitAX.value(current, kAXURLAttribute)
                    let host = (url as? URL)?.host ?? (url as? String).flatMap { URL(string: $0)?.host }
                    if HabitExclusions.isExcludedHost(host) { read.excluded = true }
                    break
                }
                node = HabitAX.parent(current)
            }
        }
        if items, read.kind == .list {
            let selected = HabitAX.value(element, kAXSelectedRowsAttribute) ?? HabitAX.value(element, kAXSelectedChildrenAttribute)
            read.selectedItems = !((selected as? [AXUIElement])?.isEmpty ?? true)
        }
        return read
    }

    /// P 要比的样子：前台、焦点窗口和标题、这个 App 的窗口数、layer>0 的窗口、剪贴板。
    private func scene(pid: pid_t, pasteboard: Int?) -> HabitScene {
        let windows = WindowListCache.shared.onScreenWindows()
        var scene = HabitScene()
        scene.frontPID = frontPID()
        scene.pasteboard = pasteboard
        if pid > 0, let window = HabitAX.element(HabitAX.app(pid), kAXFocusedWindowAttribute) {
            scene.focusedWindow = HabitAX.windowID(window)
            scene.focusedTitle = HabitAX.string(window, kAXTitleAttribute)
        }
        for info in windows {
            let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            if owner == pid, layer == 0 { scene.windowCount += 1 }
            if layer > 0, owner != ownPID, let number = info[kCGWindowNumber as String] as? NSNumber {
                scene.overlays.insert(number.uint32Value)
            }
        }
        return scene
    }

    /// 被 WindowShade 占着的组合：所有快捷键的当前组合、开着的 ⌃⌘1…9、窗口浏览、按窗口切换的触发键；
    /// 再加上 DefaultKeyBinding.dict 里绑定过的（文件改了才重读）。一分钟内复用。
    private func takenCombos() -> Set<HabitCombo> {
        let now = ProcessInfo.processInfo.systemUptime
        if let taken, now - taken.at < 60 { return taken.combos.union(keyBindings()) }
        var combos = Set<HabitCombo>()
        for shortcut in GlobalShortcut.allCases {
            if let hotKey = GlobalShortcutSettings.hotKey(for: shortcut) {
                combos.insert(HabitCombo(carbonKeyCode: hotKey.keyCode, carbonModifiers: hotKey.modifiers))
            }
        }
        if GlobalShortcutSettings.numberedExpandEnabled {
            for code in GlobalShortcutSettings.numberedKeyCodes {
                combos.insert(HabitCombo(carbonKeyCode: code, carbonModifiers: GlobalShortcutSettings.numberedModifiers))
            }
        }
        switch WindowSwitcherKeys.trigger {
        case .option: combos.insert(HabitCombo(48, .option))
        case .command: combos.insert(HabitCombo(48, .command))
        case .off: break
        }
        taken = (combos, now)
        return combos.union(keyBindings())
    }

    private func keyBindings() -> Set<HabitCombo> {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/KeyBindings/DefaultKeyBinding.dict")
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let bindings, bindings.modified == modified { return bindings.combos }
        var combos = Set<HabitCombo>()
        if modified != nil, let data = try? Data(contentsOf: url),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            combos = HabitOccupancy.keyBindingCombos(dict)
        }
        bindings = (combos, modified)
        return combos
    }

    /// 粘滞键、慢速键、鼠标键、全键盘控制（一分钟内复用）。
    private func accessibility() -> (sticky: Bool, slow: Bool, mouseKeys: Bool, keyboardAccess: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if let access, now - access.at < 60 { return (access.sticky, access.slow, access.mouseKeys, access.keyboardAccess) }
        func flag(_ key: String, _ domain: String) -> Bool {
            (CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSNumber)?.boolValue ?? false
        }
        let universal = "com.apple.universalaccess"
        let read = (sticky: flag("stickyKey", universal), slow: flag("slowKey", universal),
                    mouseKeys: flag("mouseDriver", universal),
                    keyboardAccess: flag("FullKeyboardAccessEnabled", "com.apple.Accessibility"))
        access = (read.sticky, read.slow, read.mouseKeys, read.keyboardAccess, now)
        return read
    }

    /// Stream Deck、OBS、Discord 这类占着 F13 的 App 在跑。
    private static func hotkeyAppRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier.map(HabitExclusions.hotkeyApps.contains) ?? false }
    }

    /// 前台窗口正好盖满一整块屏（演示、全屏播放）。
    private static func coversDisplay(pid: pid_t) -> Bool {
        guard let front = WindowListCache.shared.onScreenWindows(ofPID: pid)
            .first(where: { ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 }),
              let bounds = cgWindowBounds(front) else { return false }
        return displays().contains { $0 == bounds }
    }

    private static func displays() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    private static func displayBounds(containing point: CGPoint) -> CGRect? {
        displays().first { $0.contains(point) }
    }

    /// 点在菜单栏那一条上（全局坐标，屏幕最上面 40 点以内）。
    private static func inMenuBar(_ point: CGPoint) -> Bool {
        guard let screen = displayBounds(containing: point) else { return false }
        return point.y - screen.minY <= 40
    }

    /// 屏上有菜单（layer 101）开着。
    private static func menuOnScreen() -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == Int(CGWindowLevelForKey(.popUpMenuWindow)) }
    }

    /// 指针下面是桌面：从前往后第一扇盖住这一点的窗口不是普通窗口（layer 0）、不是桌面小组件，而是桌面那一层。
    private static func desktop(at point: CGPoint) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let own = getpid()
        for info in windows {
            guard let bounds = cgWindowBounds(info), bounds.contains(point) else { continue }
            let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard owner != own, alpha > 0 else { continue }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let name = info[kCGWindowOwnerName as String] as? String ?? ""
            if name == "Notification Center" || name == "NotificationCenter" || name == "Widgets" || name == "通知中心" { return false }
            if layer == 0 { return false }
            if layer < 0 { return true }
            // layer>0：菜单栏、Dock、浮动面板盖着这一点，不是桌面。
            return false
        }
        return false
    }

    /// 留在 Dock 里的 App（com.apple.dock 的 persistent-apps）。
    private static func persistentApps() -> Set<String> {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        let apps = CFPreferencesCopyAppValue("persistent-apps" as CFString, domain) as? [[String: Any]] ?? []
        return Set(apps.compactMap { ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String })
    }
}

// MARK: - 主线程这一边

@MainActor
final class HabitCenter {
    static let shared = HabitCenter()
    /// 卡住时的提示那本账和几条规则的进度（HabitMemory 的 JSON）。
    nonisolated static let memoryKey = "Notch.habits"
    /// 已经上真机确认过、可以开的规则（单按 ⇧、Print Screen）：默认空，不开。
    nonisolated static let deviceCheckedKey = "Notch.habitsDeviceChecked"

    let keys = HabitKeys()
    let worker = HabitWorker()
    private weak var owner: AppDelegate?
    private(set) var memory = HabitMemory()
    private(set) var active: Set<HabitRule> = []
    private var started = false
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultsObserver: NSObjectProtocol?
    nonisolated private static let switchesLock = NSLock()
    nonisolated(unsafe) private static var lastSwitches: (Bool, Bool)?
    private var settings = HabitWorker.Settings()
    private var shade = HabitShadeWatch()
    private var shadedAtPress: Set<CGWindowID> = []
    /// 访达在不在前台：单按 delete、Del 只在这时放进钩子的表（别的 App 里打字的退格不出钩子）。
    private var finderFront = false
    /// 桌面两指下滑那条听满日子时重算一次（一次性的 asyncAfter，不轮询）。
    private var desktopSearchExpiry: DispatchWorkItem?

    /// 探针：按这个来处算（不读、不写设置）；记录只在内存里；自己进程发的按键也听。
    var originOverride: SwitcherOrigin?
    var persists = true
    private var acceptsOwnEvents = false
    /// 最近的判定（探针看）。
    private(set) var verdicts: [(rule: HabitRule, verdict: String)] = []

    private init() {}

    func start(owner: AppDelegate) {
        guard !started, !NotchController.probeSilence else { return }
        started = true
        self.owner = owner
        if persists {
            memory = UserDefaults.standard.data(forKey: Self.memoryKey)
                .flatMap { try? JSONDecoder().decode(HabitMemory.self, from: $0) } ?? HabitMemory()
            // 共用的节奏：两边各自上一次开口的时间报进来（探针只用内存里的记录，不读这些）。
            if let last = memory.ledger.lastShownAt { CoachPacing.note(last) }
            if let last = Self.gestureCoach()?.lastShownAt { CoachPacing.note(last) }
        }
        keys.onObservation = { [worker] observation in worker.observe(observation) }
        worker.onDecision = { decision in DispatchQueue.main.async { MainActor.assumeIsolated { HabitCenter.shared.present(decision) } } }
        worker.onLearned = { rule in DispatchQueue.main.async { MainActor.assumeIsolated { HabitCenter.shared.learned(rule) } } }
        worker.onEmacs = { DispatchQueue.main.async { MainActor.assumeIsolated { HabitCenter.shared.emacsHit() } } }
        worker.onWatch = { [keys] until in keys.watch(until: until) }
        worker.onMouse = { observation in DispatchQueue.main.async { MainActor.assumeIsolated { HabitCenter.shared.mouse(observation) } } }
        worker.onVerdict = { rule, verdict in
            DispatchQueue.main.async { MainActor.assumeIsolated { HabitCenter.shared.note(rule, verdict) } }
        }
        observers.append(NotificationCenter.default.addObserver(forName: SwitcherOrigin.didChangeNotification, object: nil,
                                                                queue: .main) { _ in
            MainActor.assumeIsolated { HabitCenter.shared.apply() }
        })
        // 刘海、教学的开关：设置一变就对一次（很便宜：只比两个布尔值，变了才回主线程）。
        Self.switchesLock.lock()
        Self.lastSwitches = (NotchController.isEnabled, NotchController.teachEnabled)
        Self.switchesLock.unlock()
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                                  queue: nil) { _ in
            HabitCenter.switchesMayHaveChanged()
        }
        apply()
    }

    func stop() {
        keys.apply(HabitKeys.Config())
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        updateWorkspaceObservers([])
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        defaultsObserver = nil
        desktopSearchExpiry?.cancel()
        desktopSearchExpiry = nil
        CoachPacing.release()
        active = []
        started = false
    }

    nonisolated private static func switchesMayHaveChanged() {
        let now = (NotchController.isEnabled, NotchController.teachEnabled)
        switchesLock.lock()
        let changed = lastSwitches.map { $0 != now } ?? true
        lastSwitches = now
        switchesLock.unlock()
        guard changed else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { HabitCenter.shared.apply() } }
    }

    /// 算一遍哪些规则开着，照着装上或拆掉钩子、通知。没有要听的就全部拆掉。
    func apply() {
        guard started else { return }
        let origin = originOverride ?? SwitcherOrigin.current
        var rules: Set<HabitRule> = []
        var environment = HabitGate.Environment()
        let now = Date().timeIntervalSince1970
        if NotchController.isEnabled, NotchController.teachEnabled, !NotchController.probeSilence, origin != .mac {
            environment = Self.environment(origin: origin)
            rules = HabitGate.active(origin: origin, deviceChecked: deviceChecked, memory: memory, environment: environment,
                                     now: now)
        }
        let changed = rules != active
        active = rules
        // 收起后的普通提示只在刚双击、甩过标题栏的那十几秒里压着（见 mouse、collapsed）；两条都不开了就马上放开。
        if !rules.contains(.titleDoubleClick), !rules.contains(.titleFlickUp) { CoachPacing.release() }
        scheduleDesktopSearchExpiry(rules, now: now)
        var settings = HabitWorker.Settings()
        settings.active = rules
        settings.traces = acceptsOwnEvents
        if rules.contains(where: { $0.side == .windows }) {
            settings.lettersMatch = Self.lettersMatchLayout()
            settings.inputSource = Self.inputSourceID()
            settings.imeVariant = Self.imeVariant()
        }
        settings.natural = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
        if rules.contains(.desktopSearch), let spotlight = LaunchpadController.spotlightShortcut() {
            settings.spotlight = HabitCombo(keyCode: spotlight.0, flags: spotlight.1.rawValue)
        }
        if rules.contains(where: { $0.side == .ipad }) {
            settings.dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier ?? 0
        }
        self.settings = settings
        worker.update(settings)
        finderFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        var config = HabitKeys.Config()
        config.table = HabitTable(rules: rules, emacs: rules.contains { $0.controlFamily }, finderFront: finderFront)
        config.keys = !config.table.isEmpty
        config.flags = !rules.isDisjoint(with: [.lineEnds, .symbols, .imeShift])
        config.altDigits = rules.contains(.symbols)
        config.shiftTaps = rules.contains(.imeShift)
        config.mouse = !rules.isDisjoint(with: [.hideApp, .menuBar, .dockRemoved, .titleDoubleClick, .titleFlickUp])
        config.scroll = rules.contains(.desktopSearch)
        config.acceptsOwnEvents = acceptsOwnEvents
        keys.apply(config)
        if changed {
            updateWorkspaceObservers(rules)
            wlog("habits: \(origin.rawValue) → \(rules.map(\.rawValue).sorted().joined(separator: ","))")
        }
    }

    /// 桌面两指下滑那条：第一次开着时记下日子；听满 14 天那一刻重算一次（到时 HabitGate 会把它去掉，滚动的钩子跟着拆掉）。
    private func scheduleDesktopSearchExpiry(_ rules: Set<HabitRule>, now: TimeInterval) {
        desktopSearchExpiry?.cancel()
        desktopSearchExpiry = nil
        guard rules.contains(.desktopSearch) else { return }
        if memory.desktopSearchSince == nil {
            memory.desktopSearchSince = now
            save()
        }
        guard let since = memory.desktopSearchSince else { return }
        let item = DispatchWorkItem { MainActor.assumeIsolated { HabitCenter.shared.apply() } }
        let remaining = max(0, since + HabitMemory.desktopSearchDays * 86_400 - now) + 1
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + remaining, execute: item)
        desktopSearchExpiry = item
    }

    /// 换了前台 App：访达进出前台时只换钩子里的表（听的事件种类不变，钩子不重装）。
    private func frontChanged(_ app: NSRunningApplication?) {
        let finder = app?.bundleIdentifier == "com.apple.finder"
        guard started, finder != finderFront else { return }
        finderFront = finder
        guard active.contains(where: \.foreignOnlyInFinder) else { return }
        keys.setTable(HabitTable(rules: active, emacs: active.contains { $0.controlFamily }, finderFront: finder))
    }

    private var deviceChecked: Set<HabitRule> {
        Set((UserDefaults.standard.stringArray(forKey: Self.deviceCheckedKey) ?? []).compactMap(HabitRule.init(rawValue:)))
    }

    /// 开着规则时才挂的通知：App 退出（缓存作废）、藏起和显示（⌘H）、输入法换了（字母位置、单按 ⇧）、
    /// 换了前台 App（访达里的 delete 那条开着时）。
    private func updateWorkspaceObservers(_ rules: Set<HabitRule>) {
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            // 各自挂在哪个中心上都摘一遍（没挂在那里的摘了也没事）。
            workspace.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        workspaceObservers = []
        guard !rules.isEmpty else { return }
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                                        queue: .main) { [worker] note in
            if let pid = HabitCenter.pid(of: note) { worker.forget(pid: pid) }
        })
        if rules.contains(where: \.foreignOnlyInFinder) {
            workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                                            queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { HabitCenter.shared.frontChanged(app) }
            })
        }
        if rules.contains(.hideApp) {
            workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil,
                                                            queue: .main) { [worker] note in
                if let pid = HabitCenter.pid(of: note) { worker.appHidden(pid) }
            })
            workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil,
                                                            queue: .main) { [worker] note in
                if let pid = HabitCenter.pid(of: note) { worker.appUnhidden(pid) }
            })
        }
        if rules.contains(where: { $0.side == .windows }) {
            workspaceObservers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
                queue: .main) { _ in
                MainActor.assumeIsolated { HabitCenter.shared.inputSourceChanged() }
            })
        }
    }

    /// 通知里是哪个 App。
    nonisolated private static func pid(of note: Notification) -> pid_t? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
    }

    /// 换了输入法（拼音用户一天要换很多次）：只重读字母位置和输入法，不整个重算。
    private func inputSourceChanged() {
        guard started, active.contains(where: { $0.side == .windows }) else { return }
        settings.lettersMatch = Self.lettersMatchLayout()
        settings.inputSource = Self.inputSourceID()
        worker.update(settings)
    }

    // MARK: 这台 Mac 的情况

    private static func environment(origin: SwitcherOrigin) -> HabitGate.Environment {
        var environment = HabitGate.Environment()
        environment.remappedModifiers = modifiersRemapped()
        environment.remapToolRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier.map(HabitExclusions.isRemapTool) ?? false
        }
        environment.homeLearned = gestureCoach()?.used.contains(.notchHome) ?? false
        environment.spotlightAvailable = origin != .ipad || LaunchpadController.spotlightShortcut() != nil
        return environment
    }

    /// 手势提示那本账（只读）：它上一次开口的时间、用过哪些手势。
    private static func gestureCoach() -> GestureCoach? {
        UserDefaults.standard.data(forKey: NotchController.coachKey).flatMap { try? JSONDecoder().decode(GestureCoach.self, from: $0) }
    }

    /// 系统设置里对调过修饰键（-currentHost 下的 com.apple.keyboard.modifiermapping.*）。
    private static func modifiersRemapped() -> Bool {
        guard let keys = CFPreferencesCopyKeyList(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                                                  kCFPreferencesCurrentHost) as? [String] else { return false }
        return keys.contains { key in
            guard key.hasPrefix("com.apple.keyboard.modifiermapping") else { return false }
            let value = CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                                               kCFPreferencesCurrentHost) as? [Any]
            return !(value?.isEmpty ?? true)
        }
    }

    /// 当前键盘布局下，规则用到的字母键还在 ANSI 的位置上（德语、法语、Dvorak 布局下字母那几条不说）。
    private static func lettersMatchLayout() -> Bool {
        let codes: [UInt16] = [HabitKey.c, HabitKey.v, HabitKey.x, HabitKey.z, HabitKey.s, HabitKey.w, HabitKey.h, HabitKey.m]
        return codes.allSatisfy { code in character(for: code) == HabitKey.letters[code]?.lowercased() }
    }

    private static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var dead: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length).lowercased()
        }
    }

    private static func inputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    /// 单按 ⇧ 那条的主句按设置选：开了“用大写锁定键切换 ABC”、🌐 键设成切换输入法，否则 ⌃空格。
    private static func imeVariant() -> HabitVariant {
        let domain = "com.apple.HIToolbox" as CFString
        if (CFPreferencesCopyAppValue("TISRomanSwitchState" as CFString, domain) as? NSNumber)?.intValue == 1 { return .capsLock }
        if (CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, domain) as? NSNumber)?.intValue == 1 { return .globe }
        return .plain
    }

    // MARK: 说

    /// 队列定下要说：再看一次开关、账和节奏，交给刘海。说出去了就记一次，五分钟内队列不再去读。
    private func present(_ decision: HabitDecision) {
        let now = Date().timeIntervalSince1970
        let id = decision.rule.rawValue
        guard active.contains(decision.rule), memory.ledger.canShow(id, at: now), let notch = owner?.notch else { return }
        let lines = decision.lines
        let action = decision.action
        var noNotch: HabitTip.Content?
        if decision.rule == .hideApp {
            // 隐形刘海空着时点不到：落在没有刘海的屏上时，改说、改演启动台快捷键的实际绑定，没绑定就不提快捷键。
            // 落在哪块屏由刘海挑（teachHabit），这里两种都备好。
            let shortcut = GlobalShortcutSettings.hotKey(for: .launchpad)
                .map { HabitCombo(carbonKeyCode: $0.keyCode, carbonModifiers: $0.modifiers) }
            let words = HabitWords.lines(.hideApp, variant: .noNotch, shortcut: shortcut?.label)
            noNotch = HabitTip.Content(title: words.title, subtitle: words.subtitle,
                                       demo: HabitWords.demo(.hideApp, variant: .noNotch, shortcut: shortcut?.parts))
        }
        let rule = decision.rule
        let tip = HabitTip(rule: rule, content: HabitTip.Content(title: lines.title, subtitle: lines.subtitle, demo: decision.demo),
                           noNotch: noNotch,
                           perform: { HabitCenter.shared.perform(action, for: rule) },
                           close: { HabitCenter.shared.dismissed(rule) })
        guard notch.teachHabit(tip) else { return }
        memory.ledger.didShow(id, at: now)
        save()
        worker.setQuiet(until: now + GestureCoach.cooldown)
        if memory.ledger.isDone(id) { apply() }
    }

    /// 点了提示：替他做成那一下，这条记成会了。
    private func perform(_ action: HabitAction, for rule: HabitRule) {
        learned(rule)
        switch action {
        case .home:
            guard let owner, let rect = owner.notch.homeRectForProbe else { return }
            owner.launchpad.pressHome(from: rect)
        case .place(let placement):
            owner?.gestures.keyPlace(placement)
        case .selectASCII:
            if let source = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() { TISSelectInputSource(source) }
        case .none:
            break
        case .pressMenu, .postKey, .systemKey, .openMenu:
            // AX 和发按键都放到队列上，不卡主线程。
            worker.queue.async { Self.performOffMain(action) }
        }
        wlog("habits: tip \(rule.rawValue) performed")
    }

    nonisolated private static func performOffMain(_ action: HabitAction) {
        switch action {
        case let .pressMenu(element, pid, fallback):
            AXUIElementSetMessagingTimeout(element, 0.5)
            let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
            // 只在确定没按到时补发那一下。等不到回话（cannotComplete）时 App 可能已经在做了（弹出存储面板、关窗慢），
            // 再发一次就会多关一扇窗、一个标签页，或者把接着选中的文件也扔进废纸篓。
            if pressDidNotHappen(result), let fallback { post(fallback, to: pid) }
        case let .postKey(combo, pid):
            post(combo, to: pid)
        case let .systemKey(combo):
            post(combo, to: nil)
        case let .openMenu(element):
            AXUIElementSetMessagingTimeout(element, 0.5)
            _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
        case .home, .place, .selectASCII, .none:
            break
        }
    }

    /// AX 明确说没按到：元素已经不在了（菜单重建过）、不支持按、这个 App 不接 AX。
    nonisolated private static func pressDidNotHappen(_ result: AXError) -> Bool {
        [.invalidUIElement, .actionUnsupported, .attributeUnsupported, .notImplemented, .illegalArgument].contains(result)
    }

    /// 替他按那一下：打上记号（钩子不当成他按的）。pid 为 nil 时从键盘那一层发（系统快捷键）。
    nonisolated private static func post(_ combo: HabitCombo, to pid: pid_t?) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false) else { return }
        var flags: CGEventFlags = []
        if combo.modifiers.contains(.control) { flags.insert(.maskControl) }
        if combo.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if combo.modifiers.contains(.shift) { flags.insert(.maskShift) }
        if combo.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if combo.globe || [HabitKey.left, HabitKey.right].contains(combo.keyCode) { flags.insert(.maskSecondaryFn) }
        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: HabitKeys.ownEventTag)
            if let pid { event.postToPid(pid) } else { event.post(tap: .cghidEventTap) }
        }
    }

    // MARK: 记账

    private func learned(_ rule: HabitRule) {
        guard !memory.ledger.used.contains(rule.rawValue) else { return }
        memory.ledger.learned(rule.rawValue)
        save()
        wlog("habits: \(rule.rawValue) learned")
        apply()
    }

    private func dismissed(_ rule: HabitRule) {
        memory.ledger.dismiss(rule.rawValue)
        save()
        wlog("habits: tip \(rule.rawValue) closed")
        apply()
    }

    private func emacsHit() {
        guard !memory.controlFamilySilenced else { return }
        memory.emacsHits += 1
        save()
        if memory.controlFamilySilenced {
            wlog("habits: control shortcuts in use; the ⌃ family stays quiet")
            apply()
        }
    }

    private func note(_ rule: HabitRule, _ verdict: String) {
        verdicts.append((rule, verdict))
        if verdicts.count > 40 { verdicts.removeFirst(verdicts.count - 40) }
    }

    private func save() {
        guard persists, !NotchController.probeSilence, !NotchController.probeCoachRun,
              let data = try? JSONEncoder().encode(memory) else { return }
        UserDefaults.standard.set(data, forKey: Self.memoryKey)
    }

    // MARK: 双击标题栏、往上甩（WindowShade 自己的动作，iPad 上是铺满）

    /// 鼠标按下：记下这时收着哪几扇；松开：0.35 秒（甩的话 0.45 秒）后看多收了哪一扇；有在等放大的，看它变没变大。
    private func mouse(_ observation: HabitKeys.Observation) {
        guard let owner, active.contains(.titleDoubleClick) || active.contains(.titleFlickUp) else { return }
        switch observation {
        case let .mouseDown(_, _, _, clicks):
            if clicks <= 1 { shadedAtPress = Set(owner.shaded.keys) }
        case let .mouseUp(at, location, _, clicks, down, downAt):
            var kind: HabitShadeWatch.Kind?
            if clicks == 2 {
                kind = .doubleClick
            } else if clicks <= 1, let down, let downAt, down.y - location.y >= 40, at - downAt <= 0.8 {
                kind = .flickUp
            }
            let before = shadedAtPress
            if let kind, active.contains(HabitShadeWatch.rule(for: kind)) {
                // 可能刚收起了一扇：看清之前（1 秒多）先压住收起后的普通提示，别让它抢在前面。
                CoachPacing.hold([.shade, .shake], for: 1.5)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated { HabitCenter.shared.collapsed(kind, before: before, retry: true) }
                }
            }
            if !shade.enlargeCandidates.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    MainActor.assumeIsolated { HabitCenter.shared.checkEnlarged() }
                }
            }
        default:
            break
        }
    }

    /// 看多收起了哪一扇。收起动画还没走完、记录还没写上时，再等 0.6 秒看一次。
    private func collapsed(_ kind: HabitShadeWatch.Kind, before: Set<CGWindowID>, retry: Bool) {
        guard let owner else { return }
        let added = Set(owner.shaded.keys).subtracting(before)
        if added.isEmpty, retry {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated { HabitCenter.shared.collapsed(kind, before: before, retry: false) }
            }
            return
        }
        guard added.count == 1, let id = added.first else { return }
        let rule = HabitShadeWatch.rule(for: kind)
        guard active.contains(rule) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let watching = shade.collapsed(id, kind: kind, at: now, priorCollapses: memory.shadeCollapses, held: memory.heldShade)
        memory.shadeCollapses += 1
        save()
        guard watching else { apply(); return }
        // 盯这一扇的那十几秒里压住收起后的普通提示；到点自己放开。
        CoachPacing.hold([.shade, .shake], for: HabitShadeWatch.longest)
        DispatchQueue.main.asyncAfter(deadline: .now() + HabitShadeWatch.quick) {
            MainActor.assumeIsolated { HabitCenter.shared.quickCheck(id) }
        }
    }

    private func quickCheck(_ id: CGWindowID) {
        guard let owner else { return }
        let info = cgWindowInfo(id)
        let check = shade.quickCheck(id, stillShaded: owner.shaded[id] != nil, exists: info != nil,
                                     frame: info.flatMap(cgWindowBounds), at: ProcessInfo.processInfo.systemUptime)
        switch check {
        case .checkHoldLater:
            DispatchQueue.main.asyncAfter(deadline: .now() + HabitShadeWatch.hold - HabitShadeWatch.quick) {
                MainActor.assumeIsolated { HabitCenter.shared.holdCheck(id) }
            }
        case .waitForEnlarge:
            // 只用键盘放大（🌐⌃F）时没有鼠标松开：时间窗结束时再看一次。
            DispatchQueue.main.asyncAfter(deadline: .now() + HabitShadeWatch.enlarge) {
                MainActor.assumeIsolated { HabitCenter.shared.checkEnlarged() }
            }
        case .drop:
            break
        }
    }

    private func holdCheck(_ id: CGWindowID) {
        guard let owner, shade.holdCheck(id, stillShaded: owner.shaded[id] != nil) else { return }
        memory.heldShade = true
        save()
        wlog("habits: a collapsed window stayed collapsed; double-click and flick-up tips stay quiet")
        apply()
    }

    private func checkEnlarged() {
        let now = ProcessInfo.processInfo.systemUptime
        for id in shade.enlargeCandidates {
            let frame = cgWindowInfo(id).flatMap(cgWindowBounds)
            // 铺满这块屏（填充、往下拉），或者进了全屏（窗口和整块屏一样大）。
            let fills = frame.map { frame in
                NSScreen.screens.contains { screen in
                    [screen.visibleFrame, screen.frame].contains { area in
                        abs(frame.width - area.width) <= 8 && abs(frame.height - area.height) <= 8
                    }
                }
            } ?? false
            if let rule = shade.resized(id, frame: frame, fillsScreen: fills, at: now) {
                worker.shadeCollision(rule)
            }
        }
        shade.expire(at: now)
    }

    // MARK: 探针

    /// 探针：按这个来处从头来（记录只在内存里，自己发的按键也听）。
    func startForProbe(owner: AppDelegate, origin: SwitcherOrigin) {
        persists = false
        originOverride = origin
        acceptsOwnEvents = true
        memory = HabitMemory()
        verdicts = []
        CoachPacing.reset()
        worker.resetForProbe()
        if started { self.owner = owner; apply() } else { start(owner: owner) }
    }

    func resetForProbe() {
        memory = HabitMemory()
        verdicts = []
        CoachPacing.reset()
        worker.resetForProbe()
        apply()
    }

    func stopForProbe() {
        stop()
        originOverride = nil
        acceptsOwnEvents = false
    }
}
