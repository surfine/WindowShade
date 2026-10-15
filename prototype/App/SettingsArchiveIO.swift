import Foundation

// 设置的导出、导入与迁移前备份（规格 R5）：读写本机设置与文件。规则见 Core/SettingsArchive.swift。
// 入口目前只有命令行 --export-settings／--import-settings；界面上放哪等设计决定。
enum SettingsArchiveIO {
    static var domainName: String { Bundle.main.bundleIdentifier ?? "com.windowshade.prototype" }

    static var backupDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WindowShade/backup", isDirectory: true)
    }

    static func currentDomain() -> [String: Any] {
        UserDefaults.standard.persistentDomain(forName: domainName) ?? [:]
    }

    /// 导出成 XML plist（设置里有日期和二进制数据，plist 能原样保存）。返回导出了几个键。
    @discardableResult
    static func export(to url: URL) throws -> Int {
        let settings = SettingsArchive.exportable(currentDomain())
        let data = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
        wlog("settings: exported \(settings.count) key(s)")
        return settings.count
    }

    /// 合并导入。返回写入与跳过的键数。
    @discardableResult
    static func importSettings(from url: URL) throws -> (written: Int, skipped: Int) {
        let data = try Data(contentsOf: url)
        guard let file = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        let plan = SettingsArchive.importPlan(file: file)
        let defaults = UserDefaults.standard
        for (key, value) in plan.write { defaults.set(value, forKey: key) }
        wlog("settings: imported \(plan.write.count) key(s), skipped \(plan.skipped.count)")
        return (plan.write.count, plan.skipped.count)
    }

    /// 迁移前把整个设置域原样存一份（本机，不过滤）。同名备份已经在就不覆盖：留的是最早那份。
    static func backupBeforeMigration(label: String) {
        let url = backupDirectory.appendingPathComponent(SettingsArchive.backupFileName(label: label))
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: currentDomain(), format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
            wlog("settings: backed up before migration \(label)")
        } catch {
            wlog("settings: backup before migration \(label) failed \(error.localizedDescription)")
        }
    }
}
