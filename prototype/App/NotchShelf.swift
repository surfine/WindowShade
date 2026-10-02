// 刘海也收着系统里最小化的窗口和隐藏的 App：程序坞右边那一段、⌘H 藏起来的 App，都能在刘海的一排里看到、点一下拿回来。
//
// 指针停到刘海上时在后台查一遍（和展开前那一小会儿同时进行，查完就补进那一排）：
// 先用窗口列表挑出有“不在屏幕上”的窗口的 App，只问这几个 App 的辅助功能哪些窗口是最小化的；隐藏的 App 直接看
// NSRunningApplication。WindowShade 自己收起、侧拉、收进刘海的窗口已经在那一排里，不重复算；
// 收起时 WindowShade 临时藏起来的 App 也不算。
//
// 别的桌面上的窗口也在这一排里（docs/direction.md「回到窗口」第 1 步）：停在那一格上，从那张桌面实时抓画面、
// 在原处看一眼；点一下带着这扇窗切过去。挑哪几扇、写“桌面几”见 Core/ElsewhereWindows.swift。

import Cocoa

struct NotchShelfItem: Equatable {
    enum Kind { case minimized, hiddenApp, elsewhere }
    let id: CGWindowID
    let pid: pid_t
    let kind: Kind
    let title: String
    /// 别的桌面上的窗口：在哪张桌面、窗口的位置和大小（窗口列表的坐标，左上角为原点）。
    var place: ElsewhereWindow.Place? = nil
    var bounds: CGRect = .zero
}

@MainActor
final class NotchShelf {
    private(set) var items: [NotchShelfItem] = []
    private var scanning = false
    private var elsewhereScanning = false
    private var scannedAt: CFAbsoluteTime = 0
    /// 作废一次就加一：还在路上的查询回来时代数不对，结果丢掉（别把刚还原、刚换桌面之前的样子写回去）。
    private var generation = 0
    /// 查完了、内容变了：刘海正展开着就换上新的一排。
    var onChange: (() -> Void)?

    func item(_ id: CGWindowID) -> NotchShelfItem? { items.first { $0.id == id } }
    /// 下一次指针停上来时一定重新查（探针、刚还原过一扇）。
    func invalidate() {
        scannedAt = 0
        generation += 1
    }

    /// exclude：已经在那一排里的窗口（收起的、侧拉的、收进刘海的、带到每张桌面的）；
    /// ownHidden：WindowShade 收起窗口时临时藏起来的 App。一秒内查过就不再查。
    func refresh(exclude: Set<CGWindowID>, ownHidden: Set<pid_t>) {
        guard !scanning, CFAbsoluteTimeGetCurrent() - scannedAt > 1 else { return }
        scanning = true
        let own = getpid()
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != own
        }
        let hidden = apps.filter { $0.isHidden && !ownHidden.contains($0.processIdentifier) }
            .map { ($0.processIdentifier, $0.localizedName ?? "") }
        let shown = Set(apps.filter { !$0.isHidden }.map(\.processIdentifier))
        let names = Dictionary(apps.map { ($0.processIdentifier, $0.localizedName ?? "") }, uniquingKeysWith: { a, _ in a })
        let started = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.scan(shown: shown, hidden: hidden, exclude: exclude, names: names)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self else { return }
                    self.scanning = false
                    // 查的途中被作废了（还原了一扇、换了桌面）：这份结果是旧的，下次再查。
                    guard started == self.generation else { return }
                    self.scannedAt = CFAbsoluteTimeGetCurrent()
                    guard found != self.items else { return }
                    self.items = found
                    wlog("notch: shelf minimized=\(found.filter { $0.kind == .minimized }.count) hidden=\(found.filter { $0.kind == .hiddenApp }.count) elsewhere=\(found.filter { $0.kind == .elsewhere }.count)")
                    self.onChange?()
                }
            }
        }
    }

    /// 换了桌面：只重查“别的桌面上的窗口”这一段（窗口列表加每扇一次私有调用，不问任何 App 的辅助功能），
    /// 最小化、隐藏的留到下次指针停上来再查。这样指针停上来时，这一段已经是新的，那一排不会在指针下重排。
    func refreshElsewhere(exclude: Set<CGWindowID>) {
        guard !elsewhereScanning else { return }
        elsewhereScanning = true
        let own = getpid()
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != own
        }
        let shown = Set(apps.filter { !$0.isHidden }.map(\.processIdentifier))
        let names = Dictionary(apps.map { ($0.processIdentifier, $0.localizedName ?? "") }, uniquingKeysWith: { a, _ in a })
        let started = generation
        let others = Set(items.filter { $0.kind != .elsewhere }.map(\.id))
        DispatchQueue.global(qos: .userInitiated).async {
            let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let found = Self.elsewhere(list: list, shown: shown, exclude: exclude.union(others), names: names)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self else { return }
                    self.elsewhereScanning = false
                    guard started == self.generation else { return }
                    let kept = self.items.filter { $0.kind != .elsewhere }
                    let next = kept + found.filter { item in !kept.contains { $0.id == item.id } }
                    guard next != self.items else { return }
                    self.items = next
                    wlog("notch: shelf elsewhere=\(found.count) after a desktop switch")
                    self.onChange?()
                }
            }
        }
    }

    /// 后台：窗口列表挑人，辅助功能核对。
    nonisolated private static func scan(shown: Set<pid_t>, hidden: [(pid_t, String)],
                                         exclude: Set<CGWindowID>, names: [pid_t: String]) -> [NotchShelfItem] {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var offscreen = Set<pid_t>()
        var firstWindow: [pid_t: CGWindowID] = [:]
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let number = info[kCGWindowNumber as String] as? NSNumber else { continue }
            if firstWindow[pid] == nil { firstWindow[pid] = CGWindowID(number.uint32Value) }
            if (info[kCGWindowIsOnscreen as String] as? Bool) != true { offscreen.insert(pid) }
        }
        let candidates = shown.filter(offscreen.contains).sorted()
        var found: [NotchShelfItem] = []
        for (pid, windows) in zip(candidates, concurrentAppWindows(candidates)) {
            for win in windows where axBoolAttribute(win, kAXMinimizedAttribute as String) {
                guard let id = windowID(of: win), !exclude.contains(id) else { continue }
                found.append(NotchShelfItem(id: id, pid: pid, kind: .minimized, title: axTitle(win)))
            }
        }
        for (pid, name) in hidden {
            guard let id = firstWindow[pid], !exclude.contains(id) else { continue }
            found.append(NotchShelfItem(id: id, pid: pid, kind: .hiddenApp, title: name))
        }
        found += elsewhere(list: list, shown: shown, exclude: exclude.union(found.map(\.id)), names: names)
        return found
    }

    /// 别的桌面上的窗口：只问不在屏幕上、够大的普通窗口在哪张桌面（每扇一次私有调用，几十扇也就几毫秒）。
    /// 隐藏的 App 已经有自己那一格，不再按窗口列。
    nonisolated private static func elsewhere(list: [[String: Any]], shown: Set<pid_t>, exclude: Set<CGWindowID>,
                                              names: [pid_t: String]) -> [NotchShelfItem] {
        let sls = PrivateSLSWindowMover.shared
        let desktops = sls.desktopRows()
        guard !desktops.isEmpty else { return [] }
        var titles: [CGWindowID: String] = [:]
        var candidates: [ElsewhereCandidate] = []
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0
            && (info[kCGWindowIsOnscreen as String] as? Bool) != true {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, shown.contains(pid),
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let bounds = cgWindowBounds(info),
                  bounds.width >= ElsewhereWindows.minimumSize.width,
                  bounds.height >= ElsewhereWindows.minimumSize.height else { continue }
            let id = CGWindowID(number.uint32Value)
            guard !exclude.contains(id) else { continue }
            titles[id] = info[kCGWindowName as String] as? String
            candidates.append(ElsewhereCandidate(
                id: id, pid: pid, layer: 0, bounds: bounds,
                alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                isOnScreen: false, spaces: sls.windowSpaces(id: id)))
        }
        let plan = ElsewhereWindows.plan(windows: candidates, desktops: desktops, exclude: exclude, ownPID: getpid())
        return plan.map { window in
            let title = titles[window.id].flatMap { $0.isEmpty ? nil : $0 } ?? names[window.pid] ?? ""
            return NotchShelfItem(id: window.id, pid: window.pid, kind: .elsewhere, title: title,
                                  place: window.place, bounds: window.bounds)
        }
    }

    /// 点了一格：最小化的窗口从程序坞里还原、放到最前；隐藏的 App 显示出来；别的桌面上的窗口，带着它切过去。
    func restore(_ item: NotchShelfItem) {
        items.removeAll { $0 == item }
        invalidate()
        let app = NSRunningApplication(processIdentifier: item.pid)
        switch item.kind {
        case .elsewhere:
            Self.goTo(id: item.id, pid: item.pid)
        case .hiddenApp:
            app?.unhide()
            app?.activate()
            wlog("notch: shelf unhide pid=\(item.pid)")
        case .minimized:
            let id = item.id, pid = item.pid
            DispatchQueue.global(qos: .userInitiated).async {
                guard let win = appWindows(pid: pid).first(where: { windowID(of: $0) == id }) else { return }
                AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementPerformAction(win, kAXRaiseAction as CFString)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { app?.activate() }
                }
            }
            wlog("notch: shelf unminimize id=\(item.id)")
        }
    }

    /// 去那扇窗所在的桌面，并让它在最前（Core/ElsewhereWindows.goPlan）。实测（macOS 27）：
    /// - 激活一个 App，系统切到它最前那扇窗所在的桌面（约 0.8 秒）；它在眼前也有窗口时不切。
    /// - 私有的“带着窗口前置”（_SLPSSetFrontProcessWithOptions）在本机不切；AX remote token 找不到别的桌面上的窗口。
    /// 所以：激活能准确落到这扇窗的桌面时就激活；否则按系统自己的“往左 / 往右移动一个空间”快捷键走过去
    /// （调度中心负责切，桌面状态不会乱；它只动指针所在那块屏，目标在别的屏上时退回激活）。
    /// 切过去以后辅助功能才看得见这扇窗，再把它提到最前（那张桌面上这个 App 有好几扇时，要的是这一扇）。
    nonisolated static func goTo(id: CGWindowID, pid: pid_t) {
        let ticket = GoTicket.next()
        switch plan(id: id, pid: pid, forceKeys: false) {
        case .activate:
            NSRunningApplication(processIdentifier: pid)?.activate()
            wlog("notch: elsewhere go id=\(id) by activating")
            raiseWhenReachable(id: id, pid: pid, attempt: 0, activate: false, fellBack: false, ticket: ticket)
        case .keys(let key, let count):
            wlog("notch: elsewhere go id=\(id) by \(count) space step(s) key=\(key.keyCode)")
            walk(key, count) {
                raiseWhenReachable(id: id, pid: pid, attempt: 0, activate: true, fellBack: true, ticket: ticket)
            }
        }
    }

    /// 每次“去”领一张号；还在等的旧一轮看到号不是最新的就停，不去提一扇早就不要了的窗。
    private final class GoTicket: @unchecked Sendable {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var latest = 0
        static func next() -> Int { lock.lock(); defer { lock.unlock() }; latest += 1; return latest }
        static func isCurrent(_ ticket: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return ticket == latest }
    }

    /// forceKeys：激活没把人带过去（切桌面动画还没完时再激活，系统会不理），改走快捷键。
    nonisolated private static func plan(id: CGWindowID, pid: pid_t, forceKeys: Bool) -> ElsewhereWindows.GoPlan {
        let sls = PrivateSLSWindowMover.shared
        let target = sls.windowSpaces(id: id).first
        let row = sls.desktopRows().first { row in target.map { t in row.spaces.contains { $0.id == t } } ?? false }
        func layerZero(_ info: [String: Any]) -> Bool {
            (info[kCGWindowOwnerPID as String] as? pid_t) == pid && (info[kCGWindowLayer as String] as? Int) == 0
        }
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        // 这个 App 最前的那扇（窗口列表按前后次序，跳过小的工具条）。
        let front = all.first { info in
            layerZero(info) && (cgWindowBounds(info).map { $0.width >= ElsewhereWindows.minimumSize.width
                && $0.height >= ElsewhereWindows.minimumSize.height } ?? false)
        }.flatMap { ($0[kCGWindowNumber as String] as? NSNumber).map { CGWindowID($0.uint32Value) } }
        // 指针所在那块屏此刻的桌面：目标那一排的当前桌面就是它，才说明快捷键会动对屏。
        let pointer = CGEvent(source: nil)?.location ?? .zero
        var display: CGDirectDisplayID = 0
        var found: UInt32 = 0
        let pointerSpace = CGGetDisplaysWithPoint(pointer, 1, &display, &found) == .success && found > 0
            ? sls.currentSpace(displayID: display) : nil
        let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
        let facts = ElsewhereWindows.GoFacts(
            appHasWindowHere: forceKeys || onScreen.contains(where: layerZero),
            targetIsAppFront: front == id,
            activationSwitches: activationSwitchesDesktop(),
            appIsFrontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
            targetOnPointerDisplay: row.map { $0.current == pointerSpace } ?? false)
        return ElsewhereWindows.goPlan(
            facts, row: row, target: target,
            moveLeft: ElsewhereWindows.spaceKey(hotkeys["79"] as? [String: Any], defaultKeyCode: 123),
            moveRight: ElsewhereWindows.spaceKey(hotkeys["81"] as? [String: Any], defaultKeyCode: 124))
    }

    /// 系统设置 › 桌面与程序坞 › “切换到某个应用程序时，会切换到包含该应用程序已打开窗口的空间”。
    /// 新系统写在全局域的 AppleSpacesSwitchOnActivate，老办法是 com.apple.dock 的 workspaces-auto-swoosh；
    /// 两处任何一处明确关掉都算关。读不到当开着（系统默认）。
    nonisolated private static func activationSwitchesDesktop() -> Bool {
        let global = UserDefaults(suiteName: UserDefaults.globalDomain)?.object(forKey: "AppleSpacesSwitchOnActivate") as? Bool
        let dock = UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "workspaces-auto-swoosh") as? Bool
        return global != false && dock != false
    }

    /// 按“往左 / 往右移动一个空间”走 count 步（后台线程，步与步之间留 80 毫秒），走完再 then。
    nonisolated private static func walk(_ key: ElsewhereWindows.SpaceKey, _ count: Int, then: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let source = CGEventSource(stateID: .hidSystemState)
            for step in 0..<count {
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: down)
                    event?.flags = CGEventFlags(rawValue: key.flags)
                    event?.post(tap: .cghidEventTap)
                }
                if step < count - 1 { usleep(80_000) }
            }
            then()
        }
    }

    /// 等切到那张桌面（窗口出现在屏幕上），再把这扇提到最前；走快捷键过去的，到了再激活 App。最多等 3 秒。
    /// 激活后 1.2 秒还没切过去（系统不理，或者这个 App 别处也有窗口），改走快捷键，只改一次。
    nonisolated private static func raiseWhenReachable(id: CGWindowID, pid: pid_t, attempt: Int, activate: Bool,
                                                       fellBack: Bool, ticket: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            DispatchQueue.global(qos: .userInitiated).async {
                // 又点了别的一格：这一轮作废。
                guard GoTicket.isCurrent(ticket) else { return }
                guard cgWindowIsCurrentlyOnScreen(id),
                      let win = appWindows(pid: pid).first(where: { windowID(of: $0) == id }) else {
                    if !fellBack, attempt == 8, case .keys(let key, let count) = plan(id: id, pid: pid, forceKeys: true) {
                        wlog("notch: elsewhere id=\(id) activation did not switch; \(count) space step(s) instead")
                        walk(key, count) {
                            raiseWhenReachable(id: id, pid: pid, attempt: 0, activate: true, fellBack: true, ticket: ticket)
                        }
                        return
                    }
                    if attempt < 20 {
                        raiseWhenReachable(id: id, pid: pid, attempt: attempt + 1, activate: activate, fellBack: fellBack,
                                           ticket: ticket)
                    } else {
                        wlog("notch: elsewhere id=\(id) not reachable after switching")
                    }
                    return
                }
                AXUIElementPerformAction(win, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
                if activate {
                    DispatchQueue.main.async { NSRunningApplication(processIdentifier: pid)?.activate() }
                }
                wlog("notch: elsewhere raised id=\(id) after \(attempt + 1) tries")
            }
        }
    }
}
