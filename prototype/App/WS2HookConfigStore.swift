import Cocoa

/// A2「连接／断开」：把 WindowShade 的 hook 写进 ~/.claude/settings.json。
/// 规矩照 docs/agents-in-notch.md：先给用户看要改哪个文件、加哪几行；确认才写；
/// 写之前把原文件备份到旁边；断开只删自己那几行，别人的 hook 一律不碰。
/// 合并用已有的 WS2HookConfiguration（保守合并：结构不认识就整个拒绝）。
@MainActor final class WS2HookConfigStore {
    struct Status: Equatable {
        /// 文件里现在有我们的命令。
        var connected: Bool
        /// 我们认识这份文件、能安全改（没有陌生的 hook 结构）。
        var writable: Bool
        var path: String
    }

    let settingsURL: URL
    /// 备份放在同目录；找得到最近一份就在断开页上说明位置。
    static func backupURL(nextTo url: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let base = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".windowshade-backup-" + stamp)
        // 同一秒里连接又断开：名字撞了就往后加序号，绝不用覆盖当备份。
        var candidate = base
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = URL(fileURLWithPath: base.path + "-\(index)")
            index += 1
        }
        return candidate
    }

    private let helperPath: String

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         helper: String = WS2ConductorSettings.hookHelperPath) {
        settingsURL = home.appendingPathComponent(".claude/settings.json")
        helperPath = helper
    }

    func currentStatus() -> Status {
        let original = (try? Data(contentsOf: settingsURL)) ?? Data("{}".utf8)
        do {
            let connected = try WS2HookConfiguration.contains(original: original, executable: helperPath)
            return Status(connected: connected, writable: true, path: settingsURL.path)
        } catch {
            return Status(connected: false, writable: false, path: settingsURL.path)
        }
    }

    /// 给用户看的那份差异说明：要改哪个文件、加几行、每行长什么样。
    struct ChangePreview {
        let path: String
        let backupPath: String
        let command: String
        let events: [String]
        let hasOriginalFile: Bool
    }

    func previewConnect() -> ChangePreview? {
        let original = (try? Data(contentsOf: settingsURL)) ?? Data("{}".utf8)
        guard let merged = try? WS2HookConfiguration.preview(original: original,
                                                             executable: helperPath,
                                                             connected: true) else { return nil }
        return ChangePreview(path: settingsURL.path,
                             backupPath: Self.backupURL(nextTo: settingsURL).path,
                             command: merged.command,
                             events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "PermissionRequest"],
                             hasOriginalFile: FileManager.default.fileExists(atPath: settingsURL.path))
    }

    /// 确认之后才调。原文件存在就先备份；原子写入；权限 0600。
    /// 返回 nil 表示成功；失败原因给调用方写在界面上，文件不动。
    func connect() -> String? {
        apply(connected: true)
    }

    /// 断开：只删自己的那几行。同样备份、原子写。文件本来就没有我们的行就不动。
    func disconnect() -> String? {
        apply(connected: false)
    }

    private func apply(connected: Bool) -> String? {
        let manager = FileManager.default
        let original = (try? Data(contentsOf: settingsURL)) ?? Data("{}".utf8)
        guard let merged = try? WS2HookConfiguration.preview(original: original,
                                                             executable: helperPath,
                                                             connected: connected) else {
            return WSL10n.text("conductor.settings.hookForeign", zh: "这份配置里有别的工具的 hook，不敢自动改；可拷贝后手动粘贴")
        }
        if merged.original == merged.replacement { return nil }   // 已经是目标状态，不动文件
        do {
            try manager.createDirectory(at: settingsURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if manager.fileExists(atPath: settingsURL.path) {
                try manager.copyItem(at: settingsURL, to: Self.backupURL(nextTo: settingsURL))
            }
            try merged.replacement.write(to: settingsURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
            return nil
        } catch {
            return WSL10n.text("conductor.settings.hookWriteFailed", zh: "没写进去，原文件没动")
        }
    }
}
