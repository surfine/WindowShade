// 1.0.16 默认值总账：1.0.15 已有的键不在表里、默认值不变；新键没验过一律关；表里的键和代码里的键对得上。
import Foundation

@main
struct ReleaseDefaultsTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; print("FAIL \(what)") }
    }

    /// 1.0.15 已经有的键（v1.0.15 标签里就有），1.0.16 不得动它们的默认值，所以不许出现在总账里。
    static let shipped115Keys = [
        "TrackpadGesturesEnabled", "ShadeTranslucent", "WindowBrowserDockEnabled",
        "WindowBrowserKeyboardPanelEnabled", "WindowBrowserLivePreviewEnabled",
    ]

    static func main() {
        let ledger = ReleaseDefaults.ledger
        expect(Set(ledger.map(\.key)).count == ledger.count, "总账里键不重复")
        for key in shipped115Keys { expect(!ledger.contains { $0.key == key }, "1.0.15 的键不进总账：\(key)") }

        // 没验过的：不论设计上默认开还是关，1.0.16 都关。
        for entry in ledger where !entry.deviceVerified {
            expect(entry.release == false && ReleaseDefaults.value(entry.key) == false, "没验过默认关：\(entry.key)")
        }
        // 验过的：按设计值发。
        for entry in ledger where entry.deviceVerified {
            expect(ReleaseDefaults.value(entry.key) == entry.designed, "验过按设计值：\(entry.key)")
        }
        // 不在表里的新键默认关。
        expect(ReleaseDefaults.value("Some.New.Key") == false, "新键默认关")
        // 点名几个：第六轮压过之前“默认开”的裁定。
        for key in ["Notch.enabled", "Notch.activities.musicEnabled", "Notch.activities.nowPlayingStream", "Notch.mergedRow",
                    "Notch.levelKeys.enabled", "Notch.minimalPresentation", "FileShelf.enabled", "Dock.clickToHide"] {
            expect(ReleaseDefaults.value(key) == false, "之前裁定默认开、没验过的现在关：\(key)")
        }

        // 读设置的实际出口：键里没有值时跟总账走，显式设过的原样用。
        let suite = "ReleaseDefaultsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        expect(NotchLevelSetting.isEnabled(in: defaults) == false, "音量亮度开关没设过 → 关")
        NotchLevelSetting.setEnabled(true, in: defaults)
        expect(NotchLevelSetting.isEnabled(in: defaults), "显式开过 → 开")
        expect(NotchNowPlayingDefaults.musicEnabled(in: defaults) == false && NotchNowPlayingDefaults.streamEnabled(in: defaults) == false,
               "正在播放两个开关没设过 → 关")
        defaults.set(true, forKey: NotchNowPlayingDefaults.musicKey)
        expect(NotchNowPlayingDefaults.musicEnabled(in: defaults), "正在播放显式开过 → 开")
        expect(NotchMergedRowPreference.isEnabled(in: defaults) == false, "合成一排没设过 → 关")
        expect(NotchMinimalPresentation.isEnabled(in: defaults) == false, "最小呈现没设过 → 关")
        // 键名和代码里的常量对得上（改名漏改总账会在这里报）。
        for key in [NotchLevelSetting.key, NotchMergedRowPreference.defaultsKey, NotchMinimalPresentation.defaultsKey,
                    NotchNowPlayingDefaults.musicKey, NotchNowPlayingDefaults.streamKey] {
            expect(ledger.contains { $0.key == key }, "总账里有这个键：\(key)")
        }
        // 让开这个 App
        expect(DockClickHideDefault.isOn(previewInstall: false, origin: .mac) == false, "让开这个 App：没验过 → 关")
        expect(DockClickHideDefault.isOn(previewInstall: true, origin: .mac), "用过测试版的照旧")

        if failures == 0 { print("ReleaseDefaultsTests ok") } else { print("\(failures) failures"); exit(1) }
    }
}
