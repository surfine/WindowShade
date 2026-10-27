import AppKit
import Darwin

/// A3「看一眼那扇终端」的页面级验收：开一扇真 Terminal 停在临时目录，按会话目录
/// 走悬停路径，核对：找到那扇窗、浮层出现、实时画面真的收到帧（首帧存成 PNG），
/// 移开即收走。不点任何窗口、不切桌面；结束只关自己开的那一扇 Terminal。
@MainActor
enum SessionPeekProbe {
    private static let logURL = URL(fileURLWithPath:
        ProcessInfo.processInfo.environment["WINDOWSHADE_PROBE_OUT"] ?? "/tmp/windowshade-session-peek-probe.txt")

    private static func log(_ line: String) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else { try? data.write(to: logURL) }
    }
    private static func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated(body) }
    }

    static func run(owner: AppDelegate) {
        log("probe start")
        after(3) { prepare(owner) }
    }

    private static func prepare(_ owner: AppDelegate) {
        guard hasScreenRecordingPermission() else {
            // 新签的二进制每次都要重新授一次屏幕录制；这是本人一次性动作，探针不代授、不绕。
            log("SKIP session-peek: this fresh build has no screen-recording permission yet;")
            log("  grant it once in System Settings for this WindowShade build, then rerun.")
            log("FAIL session-peek: permission missing (one-time manual grant)")
            finish(); return
        }
        WindowBrowserSettings.livePreviewEnabled = true
        let dir = "/tmp/ws-session-peek-\(UUID().uuidString.prefix(6))"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: false)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            configuration: configuration,
            completionHandler: { app, error in
            MainActor.assumeIsolated {
                guard let app, error == nil else {
                    log("FAIL session-peek: cannot open Terminal (\(error.map { String(describing: $0) } ?? "?"))")
                    finish(); return
                }
                log("terminal pid=\(app.processIdentifier)")
                after(2.5) { openWindowAt(app: app, dir: dir, owner: owner) }
            }
        })
    }

    private static func openWindowAt(app: NSRunningApplication, dir: String, owner: AppDelegate) {
        // 让 Terminal 在那个目录开一扇新窗：open 文件夹会落到已开的实例。
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Terminal", dir]
        try? task.run()
        waitForTitle(pid: app.processIdentifier, name: (dir as NSString).lastPathComponent,
                     dir: dir, owner: owner, attempts: 40)
    }

    private static func waitForTitle(pid: pid_t, name: String, dir: String,
                                     owner: AppDelegate, attempts: Int) {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let match = list.contains { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) == pid &&
            (info[kCGWindowName as String] as? String)?.contains(name) == true &&
            (info[kCGWindowLayer as String] as? Int) == 0
        }
        if match { log("ok   Terminal window title carries the directory name"); startPeek(dir: dir, owner: owner, pid: pid); return }
        guard attempts > 0 else {
            log("FAIL session-peek: terminal window with that title never appeared")
            cleanup(pid: pid, dir: dir); return
        }
        after(0.5) { waitForTitle(pid: pid, name: name, dir: dir, owner: owner, attempts: attempts - 1) }
    }

    private static func startPeek(dir: String, owner: AppDelegate, pid: pid_t) {
        let peek = owner.ws2Runtime.sessionPeek
        let anchor = NSRect(x: (NSScreen.main?.frame.midX ?? 600) - 200, y: (NSScreen.main?.frame.maxY ?? 900) - 120,
                            width: 400, height: 80)
        let framePath = "/tmp/ws-session-peek-frame.png"
        try? FileManager.default.removeItem(atPath: framePath)
        WindowStreamCapture.probeRawFrameURL.withLock { $0 = URL(fileURLWithPath: framePath) }
        peek.begin(cwd: dir, terminal: nil, anchor: anchor)
        pollFrame(peek: peek, pid: pid, dir: dir, path: framePath, attempts: 40)
    }

    private static func pollFrame(peek: WS2SessionTerminalPeekController, pid: pid_t, dir: String,
                                  path: String, attempts: Int) {
        if peek.probePanelVisible, let id = peek.probeWindowID {
            log("ok   peek panel shown for window id=\(id)")
            if FileManager.default.fileExists(atPath: path) {
                log("ok   live stream delivered a frame (PNG saved)")
                peek.end()
                after(0.5) {
                    let gone = !peek.probePanelVisible
                    log(gone ? "ok   leaving the card closes the peek" : "FAIL peek panel still visible after leaving")
                    log(gone ? "PASS session-peek" : "FAIL session-peek")
                    cleanup(pid: pid, dir: dir)
                }
                return
            }
        } else if attempts < 40, peek.probeWindowID == nil {
            // 还没解析到窗口：继续等
        }
        guard attempts > 0 else {
            log("FAIL session-peek: no frame in time (window=\(peek.probeWindowID.map(String.init) ?? "nil") panel=\(peek.probePanelVisible)）")
            peek.end()
            cleanup(pid: pid, dir: dir); return
        }
        after(0.3) { pollFrame(peek: peek, pid: pid, dir: dir, path: path, attempts: attempts - 1) }
    }

    private static func cleanup(pid: pid_t, dir: String) {
        WindowStreamCapture.probeRawFrameURL.withLock { $0 = nil }
        WindowBrowserSettings.livePreviewEnabled = false
        kill(pid, SIGTERM)
        try? FileManager.default.removeItem(atPath: dir)
        finish()
    }
    private static func finish() { kill(getpid(), SIGKILL) }
}
