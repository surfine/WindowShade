import Foundation

/// 「提示音」总开关的迁移账（拍板 2026-10-29 第 1 条）：
/// 三个旧键（ShadeSoundEnabled、Timer.chimeEnabled、WindowShade.Conductor.Sound）→ 一个新键。
/// 纯 Foundation，不碰 AppKit。
@main struct AlertSoundPreferenceTests {
    static func main() {
        var failures = 0
        var assertions = 0
        func expect(_ ok: Bool, _ label: String) {
            assertions += 1
            if ok { print("ok   \(label)") } else { failures += 1; print("FAIL \(label)") }
        }
        func fresh() -> UserDefaults {
            let suite = "alert-sound-\(UUID().uuidString)"
            let d = UserDefaults(suiteName: suite)!
            d.removePersistentDomain(forName: suite)
            return d
        }

        print("CASE AS1 | 全新安装：三个旧键都没存过，照默认开（计时器到点原本就默认响）")
        expect(AlertSoundPreference.isEnabled(in: fresh()), "fresh install is on")

        print("CASE AS2 | 任一旧键显式开着就开（三种旧组合）")
        var d = fresh()
        d.set(true, forKey: "Timer.chimeEnabled")
        expect(AlertSoundPreference.isEnabled(in: d), "timer chime on -> on")
        d = fresh()
        d.set(true, forKey: "WindowShade.Conductor.Sound")
        expect(AlertSoundPreference.isEnabled(in: d), "conductor sound on -> on")
        d = fresh()
        d.set(true, forKey: "ShadeSoundEnabled")
        expect(AlertSoundPreference.isEnabled(in: d), "pomodoro's borrowed switch on -> on")

        print("CASE AS3 | 存过但全关就关（不照默认）")
        d = fresh()
        d.set(false, forKey: "Timer.chimeEnabled")
        d.set(false, forKey: "WindowShade.Conductor.Sound")
        expect(!AlertSoundPreference.isEnabled(in: d), "all legacy off -> off")

        print("CASE AS4 | 新键存过之后迁移不再参与；人改的值原样保留")
        d = fresh()
        d.set(true, forKey: "Timer.chimeEnabled")
        d.set(false, forKey: "WindowShade.AlertSound")
        expect(!AlertSoundPreference.isEnabled(in: d), "explicit off wins over legacy on")
        d.set(true, forKey: "WindowShade.AlertSound")
        expect(AlertSoundPreference.isEnabled(in: d), "explicit on stays on")

        print("CASE AS5 | 只关过收起音效、没碰过计时器：计时器当年默认响，照旧开（帕累托）")
        d = fresh()
        d.set(false, forKey: "ShadeSoundEnabled")
        expect(AlertSoundPreference.isEnabled(in: d), "fold sound off only -> still on")
        d.set(false, forKey: "Timer.chimeEnabled")
        expect(!AlertSoundPreference.isEnabled(in: d), "fold sound off + timer off -> off")

        print("CASE AS6 | 启动时落盘一次，之后卷帘那一行不再牵动提示音")
        d = fresh()
        AlertSoundPreference.migrateIfNeeded(in: d)
        expect(d.object(forKey: AlertSoundPreference.key) as? Bool == true, "fresh install persists on")
        d.set(false, forKey: "ShadeSoundEnabled")
        d.set(false, forKey: "Timer.chimeEnabled")
        expect(AlertSoundPreference.isEnabled(in: d), "legacy changes after migration are ignored")
        AlertSoundPreference.set(false, in: d)
        AlertSoundPreference.migrateIfNeeded(in: d)
        expect(!AlertSoundPreference.isEnabled(in: d), "migration never overwrites a stored value")

        print(failures == 0 ? "PASS AlertSoundPreferenceTests: \(assertions) assertions, \(failures) failures"
                            : "FAIL AlertSoundPreferenceTests: \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
