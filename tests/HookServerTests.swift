// 编程会话 hook 服务端：解析拒畸形和超长输入、状态转移、socket 权限、关掉后删文件。
// 只在临时目录里开 socket，不碰 ~/Library/Application Support/WindowShade。
import Foundation
#if canImport(Darwin)
import Darwin
#endif

@main
struct HookServerTests {
    static func line(_ body: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
    static func event(_ name: String, session: String = "s-1", cwd: String? = "/Users/me/Code/WindowShade",
                      tool: String? = nil) -> [String: Any] {
        var body: [String: Any] = ["version": 1, "provider": "claude", "event": name, "sessionID": session]
        if let cwd { body["cwd"] = cwd }
        if let tool { body["tool_name"] = tool; body["tool_input"] = ["command": "rm -rf /"] }
        return body
    }
    static func parsed(_ name: String, session: String = "s-1", cwd: String? = "/Users/me/Code/WindowShade",
                       tool: String? = nil) -> WS2HookEvent {
        WS2HookEvent.parse(line(event(name, session: session, cwd: cwd, tool: tool)))!
    }

    @MainActor static func spin(until done: () -> Bool, seconds: Double = 3) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !done() && Date() < end { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        return done()
    }

    static func send(_ data: Data, to path: String) -> Data? {
        guard let client = try? WS2UnixSocket.connect(to: path) else { return nil }
        defer { client.closeSocket() }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        do {
            if data.count > WS2UnixSocket.maximumFrame {
                // 绕过客户端自己的限长，直接写超长的一行，看服务端拒不拒。
                let bytes = data + Data([10]); var offset = 0
                while offset < bytes.count, ProcessInfo.processInfo.systemUptime < deadline {
                    let n = bytes.withUnsafeBytes { Darwin.send(client.fd, $0.baseAddress!.advanced(by: offset), $0.count - offset, 0) }
                    if n < 0 && (errno == EAGAIN || errno == EINTR) { usleep(1000); continue }
                    if n <= 0 { break }; offset += n
                }
            } else {
                try client.sendLine(data, deadline: deadline)
            }
            return try client.readLine(deadline: deadline)
        } catch { return nil }
    }

    /// 绑定后直接关 fd、不删文件：和崩溃留下的一样。
    static func leaveStaleSocket(at path: String) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8) + [0]
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        _ = chmod(path, 0o600); _ = close(fd)
    }

    @MainActor static func main() {
        var t = TestSuite("HookServer")

        t.section("H-01", "解析：只收本机 hook 的六种事件，只留工具名")
        let ok = WS2HookEvent.parse(line(event("PreToolUse", tool: "Bash")))
        t.expect(ok?.kind == .preToolUse && ok?.sessionID == "s-1" && ok?.tool == "Bash", "合法事件")
        t.expect(ok?.projectName == "WindowShade", "项目名取 cwd 最后一段")
        t.expect(WS2HookEvent.parse(line(event("Stop", cwd: nil)))?.projectPath == "", "没有 cwd 也收")
        var withTerminal = event("PreToolUse", tool: "Bash")
        withTerminal["terminal"] = ["program": "ghostty", "tmuxPane": "%4", "tty": "/dev/ttys007"]
        let termEvent = WS2HookEvent.parse(line(withTerminal))
        t.expect(termEvent?.terminal == TerminalIdentity(program: "ghostty", itermSession: "", tmuxPane: "%4", tty: "/dev/ttys007"), "终端身份跟着事件收下")
        t.expect(ok?.terminal == nil, "不报终端也收")
        for bad in [["program": "x y"], ["tmuxPane": "4"], ["extra": "x"], [String: String]()] {
            withTerminal["terminal"] = bad
            t.expect(WS2HookEvent.parse(line(withTerminal)) == nil, "不合格的终端身份整个事件拒")
        }
        var bindingModel = WS2HookSessions()
        _ = bindingModel.receive(termEvent!, at: sec(1))
        t.expect(bindingModel.terminal(of: "s-1")?.tmuxPane == "%4", "会话→终端绑定")
        var newer = withTerminal; newer["terminal"] = ["program": "iTerm.app", "tty": "/dev/ttys009"]
        _ = bindingModel.receive(WS2HookEvent.parse(line(newer))!, at: sec(2))
        t.expect(bindingModel.terminal(of: "s-1")?.program == "iTerm.app", "后来报的覆盖旧的")
        _ = bindingModel.receive(parsed("Stop"), at: sec(3))
        t.expect(bindingModel.terminal(of: "s-1")?.program == "iTerm.app" && bindingModel.terminal(of: "nope") == nil, "不带身份的事件不清掉绑定")

        t.section("H-02", "畸形输入一律拒")
        var bad: [Data] = [Data(), Data("not json".utf8), Data("[1,2]".utf8), Data("{}".utf8)]
        var b = event("Stop"); b["version"] = 2; bad.append(line(b))
        b = event("Stop"); b["version"] = true; bad.append(line(b))
        b = event("Stop"); b["version"] = 1.5; bad.append(line(b))
        b = event("Stop"); b["provider"] = "codex"; bad.append(line(b))
        b = event("SessionEnd"); bad.append(line(b))
        b = event("Stop"); b["sessionID"] = ""; bad.append(line(b))
        b = event("Stop"); b["sessionID"] = String(repeating: "a", count: 513); bad.append(line(b))
        b = event("Stop"); b["sessionID"] = "a\nb"; bad.append(line(b))
        b = event("Stop"); b["sessionID"] = 7; bad.append(line(b))
        b = event("Stop", cwd: "relative/path"); bad.append(line(b))
        b = event("Stop"); b["tool_name"] = ["x"]; bad.append(line(b))
        b = event("Stop"); b["transcript_path"] = "/tmp/x"; bad.append(line(b))
        for (index, data) in bad.enumerated() { t.expect(WS2HookEvent.parse(data) == nil, "畸形 #\(index) 被拒") }

        t.section("H-03", "超长输入被拒")
        b = event("Stop"); b["cwd"] = "/" + String(repeating: "x", count: 4096)
        t.expect(WS2HookEvent.parse(line(b)) == nil, "cwd 超过 4096 字节")
        b = event("PreToolUse", tool: "Bash"); b["tool_input"] = ["command": String(repeating: "y", count: 70_000)]
        t.expect(WS2HookEvent.parse(line(b)) == nil, "整行超过 64 KiB")

        t.section("H-04", "应答：不决定、拒绝、允许这一次，三种都明确")
        let none = String(decoding: WS2HookEvent.reply(.none), as: UTF8.self)
        let deny = String(decoding: WS2HookEvent.reply(.deny), as: UTF8.self)
        let allow = String(decoding: WS2HookEvent.reply(.allow), as: UTF8.self)
        t.expect(none == "{}" && deny.contains(#""deny""#) && allow.contains(#""allow""#), "三种各自成形")
        t.expect(!none.contains("allow"), "不决定里没有放行")

        t.section("H-05", "状态转移：开始 → 在跑 → 等你 → 在跑 → 做完了")
        var m = WS2HookSessions()
        var changes = m.receive(parsed("SessionStart"), at: sec(1))
        t.expect(m.status(of: "s-1") == .idle && changes.first?.status == .idle, "开始：空闲")
        t.expect(m.sessions.first?.context.session.provider == .claudeCode && m.sessions.first?.control == .observed, "助手是 Claude Code，只观测")
        changes = m.receive(parsed("UserPromptSubmit"), at: sec(2))
        t.expect(m.status(of: "s-1") == .running && changes.map(\.status) == [.running], "发了提示：在跑")
        t.expect(m.sessions.first?.summary == "WindowShade", "摘要只是项目名")
        _ = m.receive(parsed("PreToolUse", tool: "Bash"), at: sec(3))
        changes = m.receive(parsed("PermissionRequest", tool: "Bash"), at: sec(4))
        t.expect(m.status(of: "s-1") == .waiting && changes.first?.status == .waiting && changes.first?.project == "WindowShade", "要权限：等你")
        changes = m.receive(parsed("PostToolUse", tool: "Bash"), at: sec(9))
        t.expect(m.status(of: "s-1") == .running && changes.map(\.status) == [.running], "终端里处理完：回到在跑")
        t.expect(m.store.approvalCount == 0, "占位审批已交回")
        var decided = WS2HookSessions()
        _ = decided.receive(parsed("UserPromptSubmit", session: "d"), at: sec(1))
        _ = decided.receive(parsed("PermissionRequest", session: "d", tool: "Read"), at: sec(2))
        t.expect(decided.status(of: "d") == .waiting && decided.waitingDigest(of: "d")?.count == 32,
                 "等你，摘要就位")
        t.expect(decided.project(of: "d") == "WindowShade", "项目名在账上")
        let decidedChanges = decided.handled(sessionID: "d", at: sec(3))
        t.expect(decided.status(of: "d") == .running && decidedChanges.map(\.status) == [.running],
                 "刘海里定了：不再等你")
        t.expect(decided.store.approvalCount == 0 && decided.waitingDigest(of: "d") == nil, "占位审批结掉")
        changes = m.receive(parsed("Stop"), at: sec(10))
        t.expect(m.status(of: "s-1") == .completed && changes.map(\.status) == [.completed], "Stop：做完了")
        changes = m.receive(parsed("UserPromptSubmit"), at: sec(11))
        t.expect(m.status(of: "s-1") == .running, "下一轮又在跑")

        t.section("H-06", "等你过期、没消息、换目录")
        _ = m.receive(parsed("PermissionRequest", tool: "Edit"), at: sec(12))
        t.expect(m.nextWake == sec(12).adding(AgentSessions.maximumApprovalLifetime), "期限就是下一次唤醒")
        changes = m.tick(at: sec(12).adding(AgentSessions.maximumApprovalLifetime))
        t.expect(m.status(of: "s-1") == .running && changes.map(\.status) == [.running], "两分钟没回应：不再显示等你")
        _ = m.tick(at: sec(2000))
        t.expect(m.status(of: "s-1") == .stale, "十分钟没消息：状态待确认")
        let epoch = m.sessions.first?.context.epoch ?? 0
        _ = m.receive(parsed("UserPromptSubmit", cwd: "/Users/me/Code/Other"), at: sec(2001))
        t.expect(m.sessions.first.map { $0.context.epoch > epoch && $0.summary == "Other" && $0.status == .running } == true,
                 "同一会话换了目录：新代次，重新开始")
        var other = WS2HookSessions()
        _ = other.receive(parsed("Stop", session: "a"), at: sec(1)); _ = other.receive(parsed("Stop", session: "b"), at: sec(1))
        t.expect(other.sessions.count == 2, "不同会话分开记")

        t.section("H-07", "会话满了只留最近的，在跑和等你的不丢")
        var full = WS2HookSessions()
        _ = full.receive(parsed("PermissionRequest", session: "keep-waiting", tool: "Bash"), at: sec(1))
        for i in 0..<70 { _ = full.receive(parsed("Stop", session: "done-\(i)"), at: sec(Double(2 + i))) }
        t.expect(full.store.sessions.count <= AgentSessions.maximumSessions, "不超上限")
        t.expect(full.status(of: "done-69") == .completed, "最新的一个进来了")
        t.expect(full.status(of: "keep-waiting") == .waiting && full.store.approvalCount == 1, "等你的还在")
        t.expect(full.status(of: "done-0") == nil, "最旧做完的让位")

        t.section("H-08", "socket：0600、父目录 0700、收事件、拒畸形和超长、关掉后删文件")
        var template = Array("/tmp/wshk.XXXXXX".utf8CString)
        guard let made = mkdtemp(&template) else { t.expect(false, "临时目录"); t.finish(); return }
        let root = String(cString: made)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/WindowShade/hooks.sock"
        let server = WS2HookServer(path: path, clock: WS2ContinuousClock())
        var seen: [WS2HookSessions.Change] = []
        server.onChange = { seen += $0 }
        // 有人在看卡：PermissionRequest 的连接要挂着，等决定。
        server.onPermissionAsk = { _ in }
        t.expect(server.state == .off && !FileManager.default.fileExists(atPath: path), "默认关：不监听")
        server.setEnabled(true)
        t.expect(spin { server.state == .listening }, "打开后在听")
        var st = stat()
        t.expect(lstat(path, &st) == 0 && st.st_mode & 0o170000 == 0o140000 && st.st_mode & 0o777 == 0o600, "socket 是 0600")
        t.expect(lstat(root + "/WindowShade", &st) == 0 && st.st_mode & 0o777 == 0o700, "父目录按 0700 建")
        t.expect(send(line(event("UserPromptSubmit", session: "live")), to: path) == Data("{}".utf8), "回“{}”：不替 Claude Code 决定")
        t.expect(spin { server.model.status(of: "live") == .running }, "事件进了会话表")
        final class ReplyBox: @unchecked Sendable {
            private let lock = NSLock()
            private var stored: Data?
            var value: Data? { lock.lock(); defer { lock.unlock() }; return stored }
            func set(_ value: Data?) { lock.lock(); stored = value; lock.unlock() }
        }
        let permission = ReplyBox()
        let permissionLine = line(event("PermissionRequest", session: "live", tool: "Bash"))
        DispatchQueue.global().async { permission.set(send(permissionLine, to: path)) }
        t.expect(spin { server.model.status(of: "live") == .waiting } && seen.contains { $0.status == .waiting }, "要权限：等你")
        _ = spin(until: { false }, seconds: 0.2)
        t.expect(permission.value == nil, "决定之前连接挂着，不先回“{}”")
        t.expect(server.decide(sessionID: "live", allow: true), "审批：允许这一次")
        t.expect(spin { permission.value != nil }, "挂住的连接收到应答")
        t.expect(permission.value == Data(#"{"decision":"allow"}"#.utf8), "应答是 allow")
        t.expect(spin { server.model.status(of: "live") == .running }, "允许后不再显示等你")
        let count = seen.count
        t.expect(send(Data("garbage".utf8), to: path) == Data("{}".utf8), "畸形：回“{}”")
        b = event("PreToolUse", session: "live", tool: "Bash"); b["tool_input"] = ["command": String(repeating: "z", count: 70_000)]
        t.expect(send(line(b), to: path) == nil, "超长：不读完、不应答")
        _ = spin(until: { false }, seconds: 0.2)
        t.expect(seen.count == count && server.model.status(of: "live") == .running, "畸形和超长都没改状态")

        t.expect(send(line(event("UserPromptSubmit", session: "deny-me")), to: path) == Data("{}".utf8), "第二件：在跑")
        let deniedAsk = ReplyBox()
        let deniedLine = line(event("PermissionRequest", session: "deny-me", tool: "Write"))
        DispatchQueue.global().async { deniedAsk.set(send(deniedLine, to: path)) }
        t.expect(spin { server.model.status(of: "deny-me") == .waiting }, "第二件要权限")
        t.expect(server.decide(sessionID: "deny-me", allow: false), "审批：不允许")
        t.expect(spin { deniedAsk.value != nil }, "第二件收到应答")
        t.expect(deniedAsk.value == Data(#"{"decision":"deny"}"#.utf8), "应答是 deny")
        t.expect(spin { server.model.status(of: "deny-me") == .running }, "不允许后也不再等你")

        server.onPermissionAsk = nil
        let noCard = ReplyBox()
        let noCardLine = line(event("PermissionRequest", session: "no-card", tool: "Bash"))
        DispatchQueue.global().async { noCard.set(send(noCardLine, to: path)) }
        t.expect(spin { noCard.value == Data("{}".utf8) }, "没有卡可挂：立刻回“{}”")
        t.expect(spin { server.model.status(of: "no-card") == .idle }, "没有卡：也不留在等你")
        server.onPermissionAsk = { _ in }
        t.expect(server.model.nextWake != nil, "有期限时才排唤醒")
        let held = ReplyBox()
        let heldLine = line(event("PermissionRequest", session: "held", tool: "Edit"))
        DispatchQueue.global().async { held.set(send(heldLine, to: path)) }
        t.expect(spin { server.isWaiting(sessionID: "held") }, "关掉前还有一件挂住")
        let closed = DispatchSemaphore(value: 0)
        server.setEnabled(false) { closed.signal() }
        t.expect(closed.wait(timeout: .now() + 3) == .success, "停听完成")
        t.expect(lstat(path, &st) != 0 && errno == ENOENT, "关掉后 socket 文件被删除")
        t.expect(server.state == .off && server.model.sessions.isEmpty, "关掉后忘掉会话")
        t.expect(spin { held.value == Data("{}".utf8) }, "关掉时挂住的连接回“{}”")

        t.section("H-09", "崩溃留下的 socket 文件被换掉；父目录是符号链接时不开")
        leaveStaleSocket(at: path)
        t.expect(lstat(path, &st) == 0, "留下一个没人在听的 socket")
        let again = WS2HookServer(path: path, clock: WS2ContinuousClock())
        again.setEnabled(true)
        t.expect(spin { again.state == .listening }, "删掉旧的再听")
        t.expect(send(line(event("Stop", session: "x")), to: path) == Data("{}".utf8), "新的能收")
        let second = WS2HookServer(path: path, clock: WS2ContinuousClock())
        second.setEnabled(true)
        t.expect(spin { second.state == .failed }, "有人在听时不抢")
        second.setEnabled(false)
        let done = DispatchSemaphore(value: 0)
        again.setEnabled(false) { done.signal() }
        _ = done.wait(timeout: .now() + 3)
        t.expect(lstat(path, &st) != 0, "关掉后删除")
        try? FileManager.default.createDirectory(atPath: root + "/real", withIntermediateDirectories: false,
                                                 attributes: [.posixPermissions: 0o700])
        _ = symlink(root + "/real", root + "/link")
        let linked = WS2HookServer(path: root + "/link/hooks.sock", clock: WS2ContinuousClock())
        linked.setEnabled(true)
        t.expect(spin { linked.state == .failed }, "父目录是符号链接：不开")
        t.expect(!FileManager.default.fileExists(atPath: root + "/real/hooks.sock"), "没在链接目标里留下 socket")
        linked.setEnabled(false)


        t.section("H-10", "多会话：两件同时挂，只批一件；断线的那件批不动")
        let both = WS2HookServer(path: root + "/both.sock", hold: 119, clock: WS2ContinuousClock())
        var bothSeen: [WS2HookSessions.Change] = []
        both.onChange = { bothSeen += $0 }
        both.onPermissionAsk = { _ in }
        both.setEnabled(true)
        t.expect(spin { both.state == .listening }, "开听")
        let first = ReplyBox(), replyB = ReplyBox()
        DispatchQueue.global().async { first.set(send(line(event("PermissionRequest", session: "a", tool: "Bash")), to: root + "/both.sock")) }
        DispatchQueue.global().async { replyB.set(send(line(event("PermissionRequest", session: "b", tool: "Write")), to: root + "/both.sock")) }
        t.expect(spin { both.isWaiting(sessionID: "a") && both.isWaiting(sessionID: "b") }, "两件都挂着")
        t.expect(both.decide(sessionID: "a", allow: true), "批 a：允许")
        t.expect(spin { first.value == Data(#"{"decision":"allow"}"#.utf8) }, "a 收到 allow")
        _ = spin(until: { false }, seconds: 0.2)
        t.expect(replyB.value == nil, "b 仍挂着，没被 a 的决定带走")
        t.expect(spin { both.model.status(of: "b") == .waiting } && both.model.status(of: "a") != .waiting, "账上只剩 b 在等")
        both.decide(sessionID: "b", allow: false)
        t.expect(spin { replyB.value == Data(#"{"decision":"deny"}"#.utf8) }, "b 收到 deny")

        // 断线的那件：批了也送不出去，completion 如实报 false。
        let goneClient = try! WS2UnixSocket.connect(to: root + "/both.sock")
        try! goneClient.sendLine(line(event("PermissionRequest", session: "gone", tool: "Bash")),
                                 deadline: ProcessInfo.processInfo.systemUptime + 1)
        t.expect(spin { both.isWaiting(sessionID: "gone") }, "gone 挂上了")
        goneClient.closeSocket()
        // completion 会跳回主队列：主线程必须转 runloop 等，不能拿信号量堵住自己。
        final class DeadVerdict: @unchecked Sendable {
            private let lock = NSLock(); private var stored: Bool?
            var value: Bool? { lock.lock(); defer { lock.unlock() }; return stored }
            func set(_ v: Bool) { lock.lock(); stored = v; lock.unlock() }
        }
        let deadVerdict = DeadVerdict()
        t.expect(both.decide(sessionID: "gone", allow: true, completion: { sent in
            deadVerdict.set(sent)
        }), "批断线的那件")
        // 半关的本地 socket 上 write 可能照样成功（送到已无人读的缓冲），送达与否本来就读不出来；
        // 这里只保证 completion 一定回、账一定结。
        t.expect(spin { deadVerdict.value != nil },
                 "断线那件的 completion 一定回（sent=\(deadVerdict.value.map { String($0) } ?? "nil")）")
        t.expect(spin { both.model.status(of: "gone") != .waiting }, "账上不再等 gone")

        let bothClosed = DispatchSemaphore(value: 0)
        both.setEnabled(false) { bothClosed.signal() }
        t.expect(bothClosed.wait(timeout: .now() + 3) == .success, "both 停听完成")
        try? FileManager.default.removeItem(atPath: root + "/both.sock")

        t.section("H-11", "挂期到点：没批的那件回“{}”，不替 Claude Code 决定")
        let shortHold = WS2HookServer(path: root + "/short.sock", hold: 0.5, clock: WS2ContinuousClock())
        shortHold.onPermissionAsk = { _ in }
        shortHold.setEnabled(true)
        t.expect(spin { shortHold.state == .listening }, "开听（短挂期）")
        let expired = ReplyBox()
        DispatchQueue.global().async { expired.set(send(line(event("PermissionRequest", session: "slow", tool: "Edit")), to: root + "/short.sock")) }
        t.expect(spin { shortHold.isWaiting(sessionID: "slow") }, "挂上了")
        t.expect(spin(until: { expired.value != nil }, seconds: 5), "到点收到应答")
        t.expect(expired.value == Data("{}".utf8), "到点回“{}”，不是 allow 也不是 deny")
        t.expect(spin { shortHold.model.status(of: "slow") != .waiting }, "账上不再等 slow")
        let shortClosed = DispatchSemaphore(value: 0)
        shortHold.setEnabled(false) { shortClosed.signal() }
        _ = shortClosed.wait(timeout: .now() + 3)
        try? FileManager.default.removeItem(atPath: root + "/short.sock")

        t.finish()
    }
}
