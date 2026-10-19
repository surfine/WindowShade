// End-to-end: the real hook helper process talks to the real server over a temp socket.
// Covers the helper's wire payload, the held PermissionRequest, allow/deny, plain events and
// the no-card fallback. No real Claude model request is made.
import Foundation

@main
struct HookHelperTests {
    static func spin(until done: () -> Bool, seconds: Double = 8) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !done() && Date() < end {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return done()
    }

    static func payload(_ event: String, session: String, tool: String? = nil) -> Data {
        var body: [String: Any] = [
            "hook_event_name": event,
            "session_id": session,
            "cwd": "/Users/me/Code/WindowShade",
        ]
        if let tool { body["tool_name"] = tool; body["tool_input"] = ["command": "echo test"] }
        return try! JSONSerialization.data(withJSONObject: body) + Data([10])
    }

    static func run(_ helper: String, socket: String, input: Data) -> (status: Int32, text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helper)
        process.arguments = ["--provider", "claude", "--socket", socket]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, "") }
        stdin.fileHandleForWriting.write(input)
        try? stdin.fileHandleForWriting.close()
        if !spin(until: { !process.isRunning }) {
            process.terminate()
            process.waitUntilExit()
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    @MainActor static func main() {
        var t = TestSuite("HookHelper")
        guard CommandLine.arguments.count == 2 else {
            print("usage: hook-helper-tests <WindowShadeHook>")
            exit(64)
        }
        let helper = CommandLine.arguments[1]
        var template = Array("/tmp/wshh.XXXXXX".utf8CString)
        guard let made = mkdtemp(&template) else {
            t.expect(false, "temp directory")
            t.finish()
            return
        }
        let root = String(cString: made)
        let socket = root + "/hooks.sock"
        let server = WS2HookServer(path: socket, clock: WS2ContinuousClock())
        server.setEnabled(true)
        t.section("HH-01", "helper and server share one socket")
        t.expect(spin { server.state == .listening }, "server listening")
        guard server.state == .listening else { t.finish(); return }

        t.section("HH-02", "PermissionRequest: allow only after the human decision")
        server.onPermissionAsk = { ask in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                _ = server.decide(sessionID: ask.sessionID, allow: true)
            }
        }
        let allow = run(helper, socket: socket, input: payload("PermissionRequest", session: "helper-allow", tool: "Bash"))
        t.expect(allow.status == 0, "allow: helper exits 0")
        t.expect(allow.text.contains(#""behavior":"allow""#), "allow: helper prints allow")
        t.expect(allow.text.contains(#""hookEventName":"PermissionRequest""#), "allow: hook event name")
        t.expect(spin { server.model.status(of: "helper-allow") == .idle }, "allow: server left waiting")

        t.section("HH-03", "PermissionRequest: deny")
        server.onPermissionAsk = { ask in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                _ = server.decide(sessionID: ask.sessionID, allow: false)
            }
        }
        let deny = run(helper, socket: socket, input: payload("PermissionRequest", session: "helper-deny", tool: "Write"))
        t.expect(deny.status == 0, "deny: helper exits 0")
        t.expect(deny.text.contains(#""behavior":"deny""#), "deny: helper prints deny")
        t.expect(spin { server.model.status(of: "helper-deny") == .idle }, "deny: server left waiting")

        t.section("HH-04", "plain event and no card: no decision")
        server.onPermissionAsk = { _ in }
        let plain = run(helper, socket: socket, input: payload("PreToolUse", session: "helper-plain", tool: "Bash"))
        t.expect(plain.status == 0 && plain.text == "{}\n", "plain: {} exactly")
        server.onPermissionAsk = nil
        let none = run(helper, socket: socket, input: payload("PermissionRequest", session: "helper-none", tool: "Read"))
        t.expect(none.status == 0 && none.text == "{}\n", "no card: {} exactly")

        let done = DispatchSemaphore(value: 0)
        server.setEnabled(false) { done.signal() }
        _ = done.wait(timeout: .now() + 3)
        try? FileManager.default.removeItem(atPath: root)
        t.finish()
    }
}
