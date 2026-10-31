// A2 连接/断开的往返（临时 HOME，不碰用户的 ~/.claude）：
// 连接加自己的行并备份；断开只删自己的行、别的 hook 原样；陌生结构拒改；文件保持 0600。
import Foundation

@main
struct HookConfigStoreTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func makeHome() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ws-hook-config-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                 attributes: [.posixPermissions: 0o700])
        return root
    }

    static func write(_ text: String, to url: URL) {
        try! Data(text.utf8).write(to: url)
    }

    @MainActor static func main() {
        // 1. 没有文件 → 连接创建，含六个事件；备份不生成（原本没有文件）。
        let home1 = makeHome(); defer { try? FileManager.default.removeItem(at: home1) }
        let store1 = WS2HookConfigStore(home: home1, helper: "/Applications/WindowShade.app/Contents/Helpers/WindowShadeHook")
        expect(store1.currentStatus().writable && !store1.currentStatus().connected, "空 HOME：未连接、可写")
        expect(store1.connect() == nil, "连接成功")
        let saved = try! String(contentsOf: store1.settingsURL, encoding: .utf8)
        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "PermissionRequest"] {
            expect(saved.contains(event), "写入包含 \(event)")
        }
        expect(store1.currentStatus().connected, "连接后状态为已连接")
        let backupCount = (try! FileManager.default.contentsOfDirectory(atPath: home1.appendingPathComponent(".claude").path))
            .filter { $0.contains("windowshade-backup") }.count
        expect(backupCount == 0, "原本没有文件：不生成备份")
        let attrs = try! FileManager.default.attributesOfItem(atPath: store1.settingsURL.path)
        expect((attrs[.posixPermissions] as? Int) == 0o600, "权限 0600")

        // 2. 断开：自己的行删干净，文件回到没有 hooks 的样子。
        expect(store1.disconnect() == nil, "断开成功")
        let after = try! String(contentsOf: store1.settingsURL, encoding: .utf8)
        let json = try! JSONSerialization.jsonObject(with: Data(after.utf8)) as! [String: Any]
        expect(json["hooks"] == nil, "断开后 hooks 清空")
        expect(!store1.currentStatus().connected, "断开后状态为未连接")

        // 3. 已有别人的 hook：连接保留它们，断开也保留。
        let home2 = makeHome(); defer { try? FileManager.default.removeItem(at: home2) }
        let store2 = WS2HookConfigStore(home: home2, helper: "/Applications/WindowShade.app/Contents/Helpers/WindowShadeHook")
        try! FileManager.default.createDirectory(at: home2.appendingPathComponent(".claude"),
                                                 withIntermediateDirectories: true)
        let foreign = """
        {"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"/usr/local/bin/other-hook"}]}]},"model":"opus"}
        """
        write(foreign, to: store2.settingsURL)
        expect(store2.connect() == nil, "有别人 hook：连接成功")
        let merged = try! JSONSerialization.jsonObject(with: Data(try! String(contentsOf: store2.settingsURL, encoding: .utf8).utf8)) as! [String: Any]
        let pre = (merged["hooks"] as! [String: Any])["PreToolUse"] as! [[String: Any]]
        expect(pre.contains { ($0["hooks"] as? [[String: Any]])?.first?["command"] as? String == "/usr/local/bin/other-hook" },
               "别人的 hook 保留")
        expect((merged["model"] as? String) == "opus", "别的设置保留")
        expect(store2.disconnect() == nil, "断开成功")
        let restored = try! JSONSerialization.jsonObject(with: Data(try! String(contentsOf: store2.settingsURL, encoding: .utf8).utf8)) as! [String: Any]
        let preAfter = (restored["hooks"] as! [String: Any])["PreToolUse"] as! [[String: Any]]
        expect(preAfter.count == 1 && (preAfter[0]["hooks"] as! [[String: Any]])[0]["command"] as? String == "/usr/local/bin/other-hook",
               "断开后只剩别人的 hook")
        expect((restored["model"] as? String) == "opus", "断开后别的设置仍在")

        // 4. 陌生结构拒改、文件不动。
        let home3 = makeHome(); defer { try? FileManager.default.removeItem(at: home3) }
        let store3 = WS2HookConfigStore(home: home3, helper: "/Applications/WindowShade.app/Contents/Helpers/WindowShadeHook")
        try! FileManager.default.createDirectory(at: home3.appendingPathComponent(".claude"),
                                                 withIntermediateDirectories: true)
        write(#"{"hooks":{"PreToolUse":"not-an-array"}}"#, to: store3.settingsURL)
        let before = try! String(contentsOf: store3.settingsURL, encoding: .utf8)
        expect(store3.connect() != nil, "陌生结构：拒绝")
        expect(try! String(contentsOf: store3.settingsURL, encoding: .utf8) == before, "拒改时文件原样")
        expect(!store3.currentStatus().writable, "状态如实标不可写")

        // 5. App 搬走或删掉：文件里留着的辅助程序路径不存在了，状态要如实说。
        let home4 = makeHome(); defer { try? FileManager.default.removeItem(at: home4) }
        let oldHelper = "/Volumes/Old Mac/WindowShade.app/Contents/Helpers/WindowShadeHook"
        let writer = WS2HookConfigStore(home: home4, helper: oldHelper)
        expect(writer.connect() == nil, "旧位置连接")
        let moved = WS2HookConfigStore(home: home4, helper: "/Applications/WindowShade.app/Contents/Helpers/WindowShadeHook",
                                       isExecutable: { _ in false })
        expect(moved.currentStatus().helperMissing && !moved.currentStatus().connected, "配置指向的 App 不在了：helperMissing，当前这份也没连上")
        let present = WS2HookConfigStore(home: home4, helper: oldHelper, isExecutable: { _ in true })
        expect(!present.currentStatus().helperMissing && present.currentStatus().connected, "路径还在：不报找不到")
        expect(!store1.currentStatus().helperMissing, "没连过的 HOME 不报找不到")
        let others = makeHome(); defer { try? FileManager.default.removeItem(at: others) }
        try! FileManager.default.createDirectory(at: others.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        write(#"{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"/usr/local/bin/other-hook"}]}]}}"#,
              to: others.appendingPathComponent(".claude/settings.json"))
        expect(!WS2HookConfigStore(home: others, helper: oldHelper, isExecutable: { _ in false }).currentStatus().helperMissing,
               "别人的 hook 路径不算")

        print("\(failures == 0 ? "PASS" : "FAIL") HookConfigStore: \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
