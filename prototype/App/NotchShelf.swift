// 刘海也收着系统里最小化的窗口和隐藏的 App：程序坞右边那一段、⌘H 藏起来的 App，都能在刘海的一排里看到、点一下拿回来。
//
// 指针停到刘海上时在后台查一遍（和展开前那一小会儿同时进行，查完就补进那一排）：
// 先用窗口列表挑出有“不在屏幕上”的窗口的 App，只问这几个 App 的辅助功能哪些窗口是最小化的；隐藏的 App 直接看
// NSRunningApplication。WindowShade 自己收起、侧拉、收进刘海的窗口已经在那一排里，不重复算；
// 收起时 WindowShade 临时藏起来的 App 也不算。

import Cocoa

struct NotchShelfItem: Equatable {
    enum Kind { case minimized, hiddenApp }
    let id: CGWindowID
    let pid: pid_t
    let kind: Kind
    let title: String
}

@MainActor
final class NotchShelf {
    private(set) var items: [NotchShelfItem] = []
    private var scanning = false
    private var scannedAt: CFAbsoluteTime = 0
    /// 查完了、内容变了：刘海正展开着就换上新的一排。
    var onChange: (() -> Void)?

    func item(_ id: CGWindowID) -> NotchShelfItem? { items.first { $0.id == id } }
    /// 下一次指针停上来时一定重新查（探针、刚还原过一扇）。
    func invalidate() { scannedAt = 0 }

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
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.scan(shown: shown, hidden: hidden, exclude: exclude)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self else { return }
                    self.scanning = false
                    self.scannedAt = CFAbsoluteTimeGetCurrent()
                    guard found != self.items else { return }
                    self.items = found
                    wlog("notch: shelf minimized=\(found.filter { $0.kind == .minimized }.count) hidden=\(found.filter { $0.kind == .hiddenApp }.count)")
                    self.onChange?()
                }
            }
        }
    }

    /// 后台：窗口列表挑人，辅助功能核对。
    nonisolated private static func scan(shown: Set<pid_t>, hidden: [(pid_t, String)],
                                         exclude: Set<CGWindowID>) -> [NotchShelfItem] {
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
        return found
    }

    /// 点了一格：最小化的窗口从程序坞里还原、放到最前；隐藏的 App 显示出来。
    func restore(_ item: NotchShelfItem) {
        items.removeAll { $0 == item }
        scannedAt = 0
        let app = NSRunningApplication(processIdentifier: item.pid)
        switch item.kind {
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
}
