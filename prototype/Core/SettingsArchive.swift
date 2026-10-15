import Foundation

// 设置的导出、导入与迁移前备份（规格 R5）：纯逻辑。
// OmniWM 的教训：升级把设置整体换回默认，配置就「不再生效」，只能靠用户手动恢复。纪律：
// - 改设置格式（迁移）前先把整个设置域原样存一份在本机（不过滤：它不离开这台 Mac）；
// - 导出只导「设置」，不导状态与记录（恢复日志、更新器状态、窗口位置、引导看过没、迁移版本号），
//   也不导隐私（随身设备、口令词库、接收器地址）——导出的文件是要离开这台 Mac 的；
// - 导入是合并：文件里有的设置写进来，文件里没有的不动；被排除的类别即使出现在文件里也不写。
enum SettingsArchive {
    /// 不导出也不导入的键：前缀或完整键名。
    static let excludedPrefixes = [
        "SU",                         // Sparkle 更新器自己的状态
        "NSStatusItem", "NSWindow Frame", "NSNavPanel", "NSSplitView",  // AppKit 记的窗口与图标位置
        "ShadeJournal", "InstallHistory", "Diagnostics.", "UpdateMove", "WindowShadeUpdate", "Update.",
        "DockMineffect",              // 程序坞最小化效果的恢复会话（R31）
        "Presence.lock.device",       // 随身设备的标识（隐私）
        "Silent.phrases",             // 口令词库（隐私）
        "CarPlay.receiver.endpoint",  // 接收器地址（隐私）
        "WindowShade.Settings.LastViewedSection",
    ]
    static let excludedSuffixes = ["Shown", "MigrationVersion", "FirstRunHintShown", "TipShown"]

    static func isExportable(_ key: String) -> Bool {
        !excludedPrefixes.contains { key.hasPrefix($0) } && !excludedSuffixes.contains { key.hasSuffix($0) }
    }

    /// 要导出的那一部分。
    static func exportable(_ domain: [String: Any]) -> [String: Any] {
        domain.filter { isExportable($0.key) }
    }

    /// 导入计划：哪些键要写、哪些被跳过（排除类别）。文件里没有的键不动。
    static func importPlan(file: [String: Any]) -> (write: [String: Any], skipped: [String]) {
        var write: [String: Any] = [:]
        var skipped: [String] = []
        for (key, value) in file {
            if isExportable(key) { write[key] = value } else { skipped.append(key) }
        }
        return (write, skipped.sorted())
    }

    /// 迁移前备份的文件名，例如 pre-sound-v2.plist；同一次迁移只留第一份（不被后来覆盖）。
    static func backupFileName(label: String) -> String {
        let safe = label.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }
        return "pre-\(String(safe)).plist"
    }
}
