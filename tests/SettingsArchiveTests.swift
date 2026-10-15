import Foundation

// 规格 R5：导出只导设置；导入合并、不写排除类别；迁移前备份的文件名。
@main
struct SettingsArchiveTests {
    static func main() {
        var failures = 0
        func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FAIL \(what)") } }
        let domain: [String: Any] = [
            "Notch.enabled": true, "Dock.swipeGestures": false, "Launchpad.layout": Data([1, 2]),
            "SULastCheckTime": Date(), "NSWindow Frame WindowShade.Settings": "0 0 1 1",
            "ShadeJournalEntries": [1], "InstallHistory": "x", "ShadeOnboardingShown": true,
            "ShadeSoundMigrationVersion": 2, "Presence.lock.device": "AA:BB", "Silent.phrases.v1": ["a"],
            "WindowBrowserFirstRunHintShown": true, "SlideOver.allDesktopsTipShown": true,
            "DockMineffectOriginal": "genie", "WindowShade.Settings.LastViewedSection": "privacy",
        ]
        let out = SettingsArchive.exportable(domain)
        check(Set(out.keys) == ["Notch.enabled", "Dock.swipeGestures", "Launchpad.layout"],
              "只导设置：\(out.keys.sorted())")
        let plan = SettingsArchive.importPlan(file: ["Notch.enabled": false, "Future.newSetting": 3,
                                                     "Presence.lock.device": "evil", "SULastCheckTime": Date()])
        check(Set(plan.write.keys) == ["Notch.enabled", "Future.newSetting"], "导入写设置，新版本多出的键也收")
        check(plan.skipped == ["Presence.lock.device", "SULastCheckTime"], "隐私与状态键即使在文件里也不写")
        check(SettingsArchive.backupFileName(label: "sound-v2") == "pre-sound-v2.plist", "备份文件名")
        check(SettingsArchive.backupFileName(label: "a/b c") == "pre-a-b-c.plist", "备份文件名里不留路径字符")
        if failures > 0 { exit(1) }
        print("PASS settings-archive: export settings only, merge import skips state and private keys, backup names")
    }
}
