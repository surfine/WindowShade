// 1.0.18 N1（这一版新开了这几样）只列真变了的，和启动时走哪条引导路（A1 / U1 → N1 / N1）。
import Foundation

@main
struct WhatsNew1018Tests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; print("FAIL \(what)") }
    }

    typealias C = WhatsNew1018Changes

    static func main() {
        // 13 个键，每个都在总账里、1.0.18 起没设过是开。
        expect(C.keys.count == 13 && Set(C.keys).count == 13, "13 个键不重复")
        for key in C.keys {
            expect(ReleaseDefaults.ledger.contains { $0.key == key && $0.ownerDecided }, "总账里拍板开：\(key)")
            expect(ReleaseDefaults.value(key), "没设过是开：\(key)")
        }
        expect(C.dockHoverKey == WindowBrowserSettingsKeyMirror.dockEnabledKey, "Dock 悬停键名和窗口浏览设置一致")
        expect(C.dockClickKey == "Dock.clickToHide", "让开键名")

        // 全没设过（从 1.0.17 升上来、一个开关都没动过）：三组都列。
        let none: (String) -> Bool? = { _ in nil }
        let all = C.changedKeys(stored: none, dockClickNow: true, previewInstall: false)
        expect(all == C.keys, "全没设过：13 个都算变了")
        expect(C.groups(changed: all, notchOn: true) == [.notch, .dockHover, .shelfAndDock], "三组按顺序")

        // 显式存过值的不算，不论存的是开还是关。
        let explicit: [String: Bool] = ["Notch.teach": true, "WindowBrowserDockEnabled": false]
        let some = C.changedKeys(stored: { explicit[$0] }, dockClickNow: true, previewInstall: false)
        expect(!some.contains("Notch.teach") && !some.contains("WindowBrowserDockEnabled"), "显式存过的不算")
        expect(C.groups(changed: some, notchOn: true) == [.notch, .shelfAndDock], "Dock 悬停自己关过：不出那一行")

        // 他自己关过刘海：刘海那一行不出，放在刘海里的文件架也不算；“再点 Dock 让开”照算。
        let notchOff: [String: Bool] = ["Notch.enabled": false]
        let suite = "WhatsNew1018Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for (k, v) in notchOff { defaults.set(v, forKey: k) }
        expect(C.groups(in: defaults, dockClickNow: true, previewInstall: false) == [.dockHover, .shelfAndDock], "关过刘海：没有刘海行，让开还在")
        expect(C.groups(in: defaults, dockClickNow: false, previewInstall: false) == [.dockHover], "关过刘海、从 Windows 来（让开仍关）：只剩 Dock 悬停")
        defaults.set(false, forKey: C.dockHoverKey)
        expect(C.groups(in: defaults, dockClickNow: false, previewInstall: false).isEmpty, "全都不变：不弹 N1")
        // 显式开过刘海、子项没动：子项新开了，刘海那一行照列。
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "Notch.enabled")
        expect(C.groups(in: defaults, dockClickNow: true, previewInstall: false).first == .notch, "显式开着刘海：子项新开了也列刘海")
        // 刘海全部子项都显式存过：刘海行不出。
        defaults.removePersistentDomain(forName: suite)
        for key in C.notchKeys { defaults.set(true, forKey: key) }
        expect(!C.groups(in: defaults, dockClickNow: true, previewInstall: false).contains(.notch), "刘海全显式：不列刘海")
        // 脏数据（存的不是 Bool）按没设过算。
        defaults.removePersistentDomain(forName: suite)
        defaults.set("yes", forKey: C.fileShelfKey)
        expect(C.changedKeys(stored: { defaults.object(forKey: $0) as? Bool }, dockClickNow: false, previewInstall: false).contains(C.fileShelfKey),
               "脏数据按没设过算")

        // 用过 1.0.16 测试版的：让开那时就开着，不算变。
        expect(!C.changedKeys(stored: none, dockClickNow: true, previewInstall: true).contains(C.dockClickKey), "测试版用户：让开不算变")
        // 从 Windows / iPad 来的：让开现在仍关，不算变。
        expect(!C.changedKeys(stored: none, dockClickNow: false, previewInstall: false).contains(C.dockClickKey), "换机的：让开不算变")
        // 总账没开的（假设某一行撤回）：不算变。
        expect(C.changedKeys(stored: none, releaseValue: { _ in false }, dockClickNow: false, previewInstall: false).isEmpty, "总账关着：什么都不算")

        // 启动时走哪条路。
        typealias R = LaunchOnboardingRoute
        func route(upgrade: Bool, shown: Bool = true, ax: Bool, again: Bool = false, seen: Bool = false, changes: Bool = true) -> R {
            R.decide(upgrade: upgrade, onboardingShown: shown, accessibilityTrusted: ax,
                     permissionsAgainShown: again, whatsNewShown: seen, hasWhatsNew: changes)
        }
        expect(route(upgrade: false, shown: false, ax: false) == .welcome, "新装：A1")
        expect(route(upgrade: false, shown: false, ax: true) == .welcome, "新装、已有授权：照样 A1")
        expect(route(upgrade: false, shown: true, ax: false) == .none, "新装看过欢迎：不看 U1、N1")
        expect(route(upgrade: true, ax: false) == .permissionsAgain(thenWhatsNew: true), "从 1.0.16 手动装上来缺授权：U1 → N1")
        expect(route(upgrade: true, ax: false, changes: false) == .permissionsAgain(thenWhatsNew: false), "缺授权、没变化：只 U1")
        expect(route(upgrade: true, ax: false, seen: true) == .permissionsAgain(thenWhatsNew: false), "缺授权、N1 看过：只 U1")
        expect(route(upgrade: true, ax: false, again: true) == .whatsNew, "U1 看过了还缺授权：不再弹 U1，N1 照弹")
        expect(route(upgrade: true, ax: false, again: true, seen: true) == .none, "两样都看过：不弹")
        expect(route(upgrade: true, ax: true) == .whatsNew, "从 1.0.17 升上来授权都在：只 N1")
        expect(route(upgrade: true, ax: true, changes: false) == .none, "没变化：不弹")
        expect(route(upgrade: true, ax: true, seen: true) == .none, "N1 只弹一次")
        expect(route(upgrade: true, shown: false, ax: true, changes: false) == .welcome, "老安装没看完欢迎：照旧从第一页")
        expect(route(upgrade: true, shown: false, ax: false, again: true, seen: true) == .welcome, "老安装没看完欢迎、缺授权、U1 看过：欢迎")

        if failures == 0 { print("WhatsNew1018Tests ok") } else { print("\(failures) failures"); exit(1) }
    }
}

/// 不把整个窗口浏览设置编进来，只对键名：和 WindowBrowser/WindowBrowserSettings.swift 的 dockEnabledKey 相同（脚本里 grep 核对）。
enum WindowBrowserSettingsKeyMirror { static let dockEnabledKey = "WindowBrowserDockEnabled" }
