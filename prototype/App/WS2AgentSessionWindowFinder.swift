// “过去”：编程会话在哪个终端窗口里。按会话所在的目录，在终端类 App（Terminal、iTerm2、Ghostty、Warp）的
// 窗口标题或 AXDocument 里找；找到就带着那扇窗切过去（和刘海那一排里“别的桌面上的窗口”同一条路：NotchShelf.goTo），
// 找不到就交给调用方打开会话页。不为每种终端单写一套：四个 App 走同一段代码，只有 bundle ID 不同。
// 只读：窗口列表、窗口标题和文档属性；不输入、不执行任何东西。目录不写进日志。

import Cocoa
import ApplicationServices

@MainActor
enum WS2AgentSessionWindowFinder {
    /// 每次“过去”领一张号；找窗口的途中又点了一次，旧的一轮回来就丢掉。
    private static var epoch = 0

    /// 找到就带着那扇窗切过去；找不到（没开终端、没有对得上的窗口）调用 fallback，由它打开会话页。
    static func go(cwd: String, fallback: @escaping @MainActor () -> Void) {
        epoch += 1
        let ticket = epoch
        let pids = NSWorkspace.shared.runningApplications
            .filter { app in
                guard let id = app.bundleIdentifier else { return false }
                return AgentSessionWindowMatch.terminalBundleIDs.contains(id) && !app.isTerminated
            }
            .map(\.processIdentifier)
        let home = NSHomeDirectory()
        guard !cwd.isEmpty, !pids.isEmpty else { fallback(); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let found = find(cwd: cwd, pids: pids, home: home)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard ticket == epoch else { return }
                    if let found {
                        wlog("agent session: go to terminal window id=\(found.windowID)")
                        NotchShelf.goTo(id: CGWindowID(found.windowID), pid: found.pid)
                    } else {
                        fallback()
                    }
                }
            }
        }
    }

    /// 后台：窗口列表里挑出这几个终端 App 的普通窗口（从前到后），标题取窗口列表的，文档取辅助功能的
    /// （辅助功能只看得见当前桌面上的窗口，别的桌面的窗口靠标题认）。
    nonisolated private static func find(cwd: String, pids: [pid_t], home: String) -> (windowID: UInt32, pid: pid_t)? {
        let wanted = Set(pids)
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var documents: [UInt32: String] = [:]
        for windows in concurrentAppWindows(pids) {
            for window in windows {
                guard let id = windowID(of: window) else { continue }
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &value) == .success,
                   let text = value as? String, !text.isEmpty {
                    documents[UInt32(id)] = text
                }
            }
        }
        var candidates: [AgentSessionWindowMatch.Candidate] = []
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, wanted.contains(pid),
                  let number = info[kCGWindowNumber as String] as? NSNumber else { continue }
            let id = number.uint32Value
            candidates.append(.init(windowID: id, pid: pid, title: info[kCGWindowName as String] as? String, document: documents[id]))
        }
        guard let best = AgentSessionWindowMatch.best(cwd: cwd, among: candidates, home: home) else { return nil }
        return (best.windowID, best.pid)
    }
}
