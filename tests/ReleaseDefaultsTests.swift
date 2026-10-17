// 默认值总账：1.0.15 已有的键不在表里、默认值不变（Dock 悬停查看窗口例外，1.0.18 拍板开）；
// 没验过也没拍板的一律关；拍板的（Aaron 2026-10-17）开；表里的键和代码里的键对得上。
import Foundation

@main
struct ReleaseDefaultsTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; print("FAIL \(what)") }
    }

    /// 1.0.15 已经有的键（v1.0.15 标签里就有），不得动它们的默认值，所以不许出现在总账里。
    /// WindowBrowserDockEnabled 不在这里：Aaron 2026-10-17 拍板 1.0.18 起默认开，进了总账。
    static let shipped115Keys = [
        "TrackpadGesturesEnabled", "ShadeTranslucent",
        "WindowBrowserKeyboardPanelEnabled", "WindowBrowserLivePreviewEnabled",
    ]

    static func main() {
        let ledger = ReleaseDefaults.ledger
        expect(Set(ledger.map(\.key)).count == ledger.count, "总账里键不重复")
        for key in shipped115Keys { expect(!ledger.contains { $0.key == key }, "1.0.15 的键不进总账：\(key)") }

        // 没验过也没拍板的：不论设计上默认开还是关，一律关。
        for entry in ledger where !entry.deviceVerified && !entry.ownerDecided {
            expect(entry.release == false && ReleaseDefaults.value(entry.key) == false, "没验过没拍板默认关：\(entry.key)")
        }
        // 验过的：按设计值发。
        for entry in ledger where entry.deviceVerified {
            expect(ReleaseDefaults.value(entry.key) == entry.designed, "验过按设计值：\(entry.key)")
        }
        // 拍板的：按设计值发；deviceVerified 照实留着，不因拍板改成 true。
        for entry in ledger where entry.ownerDecided {
            expect(ReleaseDefaults.value(entry.key) == entry.designed, "拍板按设计值：\(entry.key)")
        }
        // 拍板只开设计上开的：designed false 的行拍板也关。
        expect(ReleaseDefaults.Entry(key: "x", designed: false, deviceVerified: false, ownerDecided: true).release == false, "设计上关的拍板也关")
        expect(ReleaseDefaults.Entry(key: "x", designed: true, deviceVerified: false).release == false, "ownerDecided 默认 false")
        // 不在表里的新键默认关。
        expect(ReleaseDefaults.value("Some.New.Key") == false, "新键默认关")
        // 点名：Aaron 2026-10-17 拍板 1.0.18 起默认开的 13 个键，账上记的是拍板、不是验过。
        let decided1018 = ["Notch.enabled", "Notch.changeAlerts", "Notch.teach", "Notch.activitiesEnabled",
                           "Notch.activities.musicEnabled", "Notch.activities.nowPlayingStream", "Notch.mergedRow",
                           "Notch.minimalPresentation", "Notch.deviceBattery.enabled", "Notch.levelKeys.enabled",
                           "FileShelf.enabled", "Dock.clickToHide", "WindowBrowserDockEnabled"]
        for key in decided1018 {
            let entry = ledger.first { $0.key == key }
            expect(entry?.ownerDecided == true && entry?.deviceVerified == false, "拍板开、照实记没验过：\(key)")
            expect(ReleaseDefaults.value(key), "1.0.18 起默认开：\(key)")
        }
        expect(ReleaseDefaults.value("Launchpad.uninstall.enabled") == false, "启动台卸载没验过没拍板：仍关")

        // 读设置的实际出口：键里没有值时跟总账走，显式设过的原样用。
        let suite = "ReleaseDefaultsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        expect(NotchLevelSetting.isEnabled(in: defaults), "音量亮度开关没设过 → 开（1.0.18 拍板）")
        NotchLevelSetting.setEnabled(false, in: defaults)
        expect(NotchLevelSetting.isEnabled(in: defaults) == false, "显式关过 → 关")
        expect(NotchNowPlayingDefaults.musicEnabled(in: defaults) && NotchNowPlayingDefaults.streamEnabled(in: defaults),
               "正在播放两个开关没设过 → 开（1.0.18 拍板）")
        defaults.set(false, forKey: NotchNowPlayingDefaults.musicKey)
        expect(NotchNowPlayingDefaults.musicEnabled(in: defaults) == false, "正在播放显式关过 → 关")
        expect(NotchMergedRowPreference.isEnabled(in: defaults), "合成一排没设过 → 开（1.0.18 拍板）")
        expect(NotchMinimalPresentation.isEnabled(in: defaults), "最小呈现没设过 → 开（1.0.18 拍板）")
        defaults.set(false, forKey: NotchMergedRowPreference.defaultsKey)
        expect(NotchMergedRowPreference.isEnabled(in: defaults) == false, "合成一排显式关过 → 关")
        // 键名和代码里的常量对得上（改名漏改总账会在这里报）。
        for key in [NotchLevelSetting.key, NotchMergedRowPreference.defaultsKey, NotchMinimalPresentation.defaultsKey,
                    NotchNowPlayingDefaults.musicKey, NotchNowPlayingDefaults.streamKey] {
            expect(ledger.contains { $0.key == key }, "总账里有这个键：\(key)")
        }
        // 让开这个 App
        expect(DockClickHideDefault.isOn(previewInstall: false, origin: .mac), "让开这个 App：1.0.18 拍板 → 开")
        expect(DockClickHideDefault.isOn(previewInstall: false, origin: .unanswered), "让开这个 App：没答的 → 开")
        expect(DockClickHideDefault.isOn(previewInstall: false, origin: .windows) == false, "让开这个 App：换机的照旧关")
        expect(DockClickHideDefault.isOn(previewInstall: true, origin: .mac), "用过测试版的照旧")

        if failures == 0 { print("ReleaseDefaultsTests ok") } else { print("\(failures) failures"); exit(1) }
    }
}
