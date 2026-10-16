// “过去”：编程会话在哪个终端窗口里。按会话所在的目录，在终端类 App（Terminal、iTerm2、Ghostty、Warp）的
// 窗口标题或 AXDocument 里找；找到就带着那扇窗切过去（和刘海那一排里“别的桌面上的窗口”同一条路：NotchShelf.goTo），
// 找不到就交给调用方打开会话页。不为每种终端单写一套：四个 App 走同一段代码，只有 bundle ID 不同。
// A1：hook 报来终端身份时，只在它说的那个 App 里找（TERM_PROGRAM），标题里有 tty 名也算认出；
// 在 tmux 里还会先把那个窗格选到前面（调 tmux 命令行，不需要任何授权，只发 select-window／select-pane）。
// 只走辅助功能：到窗口为止，到不了 tab（tab 级要每个 App 的自动化授权，这里不做）。
// 读：窗口列表、窗口标题和文档属性；不输入。目录不写进日志。

import Cocoa
import ApplicationServices

@MainActor
enum WS2AgentSessionWindowFinder {
    /// 每次“过去”领一张号；找窗口的途中又点了一次，旧的一轮回来就丢掉。
    private static var epoch = 0

    /// 找到就带着那扇窗切过去；找不到（没开终端、没有对得上的窗口）调用 fallback，由它打开会话页。
    static func go(cwd: String, terminal: TerminalIdentity? = nil, fallback: @escaping @MainActor () -> Void) {
        epoch += 1
        let ticket = epoch
        let wantedIDs = Set(TerminalBinding.searchBundleIDs(for: terminal))
        let pids = NSWorkspace.shared.runningApplications
            .filter { app in
                guard let id = app.bundleIdentifier else { return false }
                return wantedIDs.contains(id) && !app.isTerminated
            }
            .map(\.processIdentifier)
        let home = NSHomeDirectory()
        guard !cwd.isEmpty || terminal?.tty.isEmpty == false, !pids.isEmpty else { fallback(); return }
        if let commands = TerminalBinding.tmuxSelectArguments(for: terminal) { selectTmuxPane(commands) }
        DispatchQueue.global(qos: .userInitiated).async {
            let found = find(cwd: cwd, terminal: terminal, pids: pids, home: home)
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

    /// tmux：后台依次跑 select-window、select-pane，每条最多等 2 秒；失败不影响抬窗口。
    /// 参数只来自 TerminalBinding 校验过的窗格编号（%数字）。找不到 tmux 就什么也不做。
    private static func selectTmuxPane(_ commands: [[String]]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            guard let tmux = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
            for arguments in commands {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tmux)
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return }
                let deadline = Date().addingTimeInterval(2)
                while process.isRunning && Date() < deadline { usleep(20_000) }
                if process.isRunning { process.terminate(); return }
                if process.terminationStatus != 0 { return }
            }
        }
    }

    /// 后台：窗口列表里挑出这几个终端 App 的普通窗口（从前到后），标题取窗口列表的，文档取辅助功能的
    /// （辅助功能只看得见当前桌面上的窗口，别的桌面的窗口靠标题认）。
    nonisolated private static func find(cwd: String, terminal: TerminalIdentity?, pids: [pid_t], home: String) -> (windowID: UInt32, pid: pid_t)? {
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
        guard let best = TerminalBinding.best(identity: terminal, cwd: cwd, among: candidates, home: home) else { return nil }
        return (best.windowID, best.pid)
    }
}
