// 界面语言（第27批）：解析规则、偏好存取、立即生效。
// 只碰测试专属 suite：不写产品偏好键到任何真实域；测试二进制自己的域也不落盘。
import Foundation

@main
struct InterfaceLanguageTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        // 明确偏好优先于系统。
        expect(InterfaceLanguagePreference.resolve(.zh, systemPreferred: ["en-US"]) == .zh,
               "zh overrides an English system")
        expect(InterfaceLanguagePreference.resolve(.zhHant, systemPreferred: ["en-US"]) == .zhHant,
               "zhHant overrides an English system")
        expect(InterfaceLanguagePreference.resolve(.en, systemPreferred: ["zh-Hans-CN"]) == .en,
               "en overrides a Chinese system")

        // 跟随系统：简体各种写法都算简体。
        for language in ["zh", "zh-Hans", "zh-Hans-CN", "ZH-hans", "zh-CN", "zh-SG"] {
            expect(InterfaceLanguagePreference.resolve(.system, systemPreferred: [language]) == .zh,
                   "system \(language) → Simplified")
        }
        // 台湾、香港、澳门与带 Hant 的标签都算繁体。
        for language in ["zh-Hant", "zh-TW", "zh-Hant-TW", "ZH-HANT", "zh-HK", "zh-MO"] {
            expect(InterfaceLanguagePreference.resolve(.system, systemPreferred: [language]) == .zhHant,
                   "system \(language) → Traditional")
        }
        // 其它语言一律英文；只认首个首选语言。
        for language in ["en", "en-US", "ja-JP", "de-DE", "fr"] {
            expect(InterfaceLanguagePreference.resolve(.system, systemPreferred: [language]) == .en,
                   "system \(language) → English")
        }
        expect(InterfaceLanguagePreference.resolve(.system, systemPreferred: ["en-US", "zh-Hans"]) == .en,
               "only the first preferred language decides")
        expect(InterfaceLanguagePreference.resolve(.system, systemPreferred: []) == .en,
               "no preferred language → English")

        // 存取：没存过/坏值都当跟随系统；set 写键、system 删键。只碰测试 suite。
        let suiteName = "WindowShade.InterfaceLanguageTests"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            print("FAIL cannot open the test suite"); exit(1)
        }
        func cleanup() { suite.removePersistentDomain(forName: suiteName) }
        cleanup()

        expect(InterfaceLanguagePreference.stored(in: suite) == .system, "no stored value → system")
        suite.set("klingon", forKey: InterfaceLanguagePreference.defaultsKey)
        expect(InterfaceLanguagePreference.stored(in: suite) == .system, "an unknown stored value → system")
        // 这两行之后 suite 里有一个坏值，继续测 set。
        InterfaceLanguagePreference.set(.en, in: suite)
        expect(InterfaceLanguagePreference.stored(in: suite) == .en, "set(.en) stores the choice")
        expect(WSL10n.language == .en, "set(.en) applies immediately")
        InterfaceLanguagePreference.set(.system, in: suite)
        expect(suite.string(forKey: InterfaceLanguagePreference.defaultsKey) == nil,
               "set(.system) removes the stored key")
        expect(WSL10n.language == InterfaceLanguagePreference.resolve(.system),
               "set(.system) re-resolves against the system")

        // 切换通知：主线程同步发，恰好一次。
        var notified = 0
        let token = NotificationCenter.default.addObserver(
            forName: InterfaceLanguagePreference.didChangeNotification, object: nil, queue: nil) { _ in notified += 1 }
        InterfaceLanguagePreference.set(.zh, in: suite)
        expect(notified == 1, "set posts the change notification exactly once")
        NotificationCenter.default.removeObserver(token)

        // applyAtLaunch 只读偏好：存 en 就定英文，存 system 就按系统解析。
        InterfaceLanguagePreference.set(.en, in: suite)
        WSL10n.language = .zh
        InterfaceLanguagePreference.applyAtLaunch(defaults: suite)
        expect(WSL10n.language == .en, "applyAtLaunch reads the stored choice")
        InterfaceLanguagePreference.set(.system, in: suite)
        WSL10n.language = .en
        InterfaceLanguagePreference.applyAtLaunch(defaults: suite)
        expect(WSL10n.language == InterfaceLanguagePreference.resolve(.system),
               "applyAtLaunch re-resolves a system choice")

        // 收尾：还原进程语言到默认（夹具/测试都从 .zh 出发），清掉测试 suite。
        WSL10n.language = .zh
        cleanup()
        if failures == 0 { print("PASS: interface language — resolution, storage, immediate apply") }
        else { print("FAILED \(failures)"); exit(1) }
    }
}
