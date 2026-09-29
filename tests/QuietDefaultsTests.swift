// “少做”的默认值（docs/direction.md 最后一张表）：⌃⌘ 快捷键新装的不占、升级的照旧；“让开这个 App”的守卫和默认值。
// 纯逻辑，用单独的偏好域，不碰用户的设置、不碰任何窗口。
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// 窗口浏览那一份设置只用到快捷键这几样：换成内存里的，省得把窗口浏览整套编进来。
enum WindowBrowserSettings {
    struct HotKey: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
    }
    static var hotKey: HotKey?
    static func displayName(for hotKey: HotKey) -> String { "key \(hotKey.keyCode)" }
}

@main
struct QuietDefaultsTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    typealias HotKey = WindowBrowserSettings.HotKey
    static let controlCommand = UInt32(controlKey | cmdKey)
    static func ctrlCmd(_ code: Int) -> HotKey { HotKey(keyCode: UInt32(code), modifiers: controlCommand) }

    /// 在一个新的偏好域里跑一段，跑完删掉；prepare 先写好“以前的版本留下的”键。
    static func withDefaults(_ prepare: (UserDefaults) -> Void = { _ in }, _ body: (UserDefaults) -> Void) {
        let suite = "WindowShade.QuietDefaultsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let saved = GlobalShortcutSettings.defaults
        GlobalShortcutSettings.defaults = defaults
        WindowBrowserSettings.hotKey = nil
        defer {
            defaults.removePersistentDomain(forName: suite)
            GlobalShortcutSettings.defaults = saved
        }
        prepare(defaults)
        body(defaults)
    }

    static let shipped: [GlobalShortcut: HotKey] = [
        .toggleShade: ctrlCmd(kVK_ANSI_C), .arrangeOrFocus: ctrlCmd(kVK_ANSI_0), .pinPreview: ctrlCmd(kVK_ANSI_P),
        .carry: ctrlCmd(kVK_ANSI_G), .stepSmaller: ctrlCmd(kVK_UpArrow), .stepLarger: ctrlCmd(kVK_DownArrow),
        .leftHalf: ctrlCmd(kVK_LeftArrow), .rightHalf: ctrlCmd(kVK_RightArrow),
    ]
    static let previewOnly: [GlobalShortcut: HotKey] = [
        .slideOver: ctrlCmd(kVK_ANSI_S), .launchpad: ctrlCmd(kVK_ANSI_L), .magicTile: ctrlCmd(kVK_ANSI_M),
        .nextDisplay: ctrlCmd(kVK_ANSI_N), .tuckAll: ctrlCmd(kVK_ANSI_H),
    ]

    static func main() {
        installHistory()
        shortcuts()
        dockClickDefault()
        dockClickGuard()
        print(failures == 0 ? "all quiet-defaults tests passed" : "\(failures) quiet-defaults test(s) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: 新装还是升级

    static func installHistory() {
        withDefaults { defaults in
            // 启动第一步就认：这时新装的偏好里什么都没有。
            expect(InstallHistory.detect(in: defaults) == .fresh, "a brand-new install (nothing written yet) is fresh")
            expect(InstallHistory.settled(in: defaults) == .fresh, "settling a fresh install says fresh")
            // 认过之后，这一次启动写下声音迁移版本号、欢迎窗口关了写下“看过了”、答了来处：还是新装，下一次启动也不变。
            defaults.set(2, forKey: "ShadeSoundMigrationVersion")
            defaults.set(true, forKey: "ShadeOnboardingShown")
            defaults.set("windows", forKey: "SwitcherOrigin")
            expect(InstallHistory.settled(in: defaults) == .fresh, "once settled, what this launch writes does not turn it into an upgrade")
        }
        // 1.0.15 用过、欢迎窗口点红色按钮关掉、从没改过设置、升级时没有收着的窗口：只剩每次启动都写的那个键。
        withDefaults({ $0.set(2, forKey: "ShadeSoundMigrationVersion") }) { defaults in
            expect(InstallHistory.settled(in: defaults) == .shipped,
                   "a Mac with only the sound-migration key every earlier launch wrote is an upgrade")
        }
        withDefaults({ $0.set(1, forKey: "ShadeSoundMigrationVersion") }) { defaults in
            expect(InstallHistory.detect(in: defaults) == .shipped, "an older sound-migration value counts too")
        }
        withDefaults({ $0.set(true, forKey: "ShadeOnboardingShown") }) { defaults in
            expect(InstallHistory.settled(in: defaults) == .shipped, "a Mac that saw the welcome window before is an upgrade")
            expect(defaults.integer(forKey: InstallHistory.defaultsKey) == InstallHistory.shipped.rawValue, "the answer is stored")
        }
        withDefaults({ $0.set([Int](), forKey: "GlobalShortcut.carry") }) { defaults in
            expect(InstallHistory.detect(in: defaults) == .shipped, "someone who only ever changed a shortcut is an upgrade")
        }
        withDefaults({ $0.set([["id": 1]], forKey: "ShadeJournalEntries") }) { defaults in
            expect(InstallHistory.detect(in: defaults) == .shipped, "someone with collapsed windows on record is an upgrade")
        }
        withDefaults({
            $0.set(true, forKey: "ShadeOnboardingShown")
            $0.set(true, forKey: InstallHistory.previewMarker)
        }) { defaults in
            expect(InstallHistory.detect(in: defaults) == .preview, "a Mac that ran the 1.0.16 preview is recognised as such")
        }
        withDefaults({ $0.set(99, forKey: InstallHistory.defaultsKey) }) { defaults in
            expect(InstallHistory.settled(in: defaults) == .fresh, "a value from a later version reads as fresh")
        }
    }

    // MARK: ⌃⌘ 快捷键

    static func shortcuts() {
        withDefaults { _ in
            expect(GlobalShortcut.allCases.allSatisfy { GlobalShortcutSettings.hotKey(for: $0) == nil },
                   "a new install occupies no shortcut at all")
            expect(!GlobalShortcutSettings.numberedExpandEnabled, "a new install does not take ⌃⌘1…9 either")
            expect(GlobalShortcutSettings.isAllDefault, "nothing recorded yet counts as the defaults")
            let ctrlCmd3 = ctrlCmd(kVK_ANSI_3)
            expect(GlobalShortcutSettings.conflictName(for: ctrlCmd3, excluding: .toggleShade) == nil,
                   "⌃⌘3 is free to record on a new install")

            // 自己录一个，照常生效；清掉就是没有；再录回同一个也不占别人的。
            GlobalShortcutSettings.setHotKey(ctrlCmd(kVK_ANSI_C), for: .toggleShade)
            expect(GlobalShortcutSettings.hotKey(for: .toggleShade) == ctrlCmd(kVK_ANSI_C) && !GlobalShortcutSettings.isAllDefault,
                   "recording ⌃⌘C on a new install works and counts as a change")
            expect(GlobalShortcutSettings.conflictName(for: ctrlCmd(kVK_ANSI_C), excluding: .pinPreview) == GlobalShortcut.toggleShade.title,
                   "a recorded combination is reported as taken")
            GlobalShortcutSettings.setHotKey(nil, for: .toggleShade)
            expect(GlobalShortcutSettings.hotKey(for: .toggleShade) == nil && GlobalShortcutSettings.isAllDefault,
                   "clearing it on a new install goes back to the default: nothing")
            GlobalShortcutSettings.numberedExpandEnabled = true
            expect(GlobalShortcutSettings.numberedExpandEnabled && !GlobalShortcutSettings.isAllDefault,
                   "⌃⌘1…9 can be switched on in Settings")
            GlobalShortcutSettings.setHotKey(ctrlCmd(kVK_ANSI_M), for: .magicTile)
            GlobalShortcutSettings.resetAll()
            expect(GlobalShortcut.allCases.allSatisfy { GlobalShortcutSettings.hotKey(for: $0) == nil }
                    && !GlobalShortcutSettings.numberedExpandEnabled && GlobalShortcutSettings.isAllDefault,
                   "restore defaults on a new install clears everything again")
        }

        withDefaults({ $0.set(true, forKey: "ShadeOnboardingShown") }) { defaults in
            let kept = GlobalShortcut.allCases.allSatisfy { GlobalShortcutSettings.hotKey(for: $0) == shipped[$0] }
            expect(kept, "an upgrade from 1.0.15 keeps exactly its ⌃⌘C / 0 / P / G / arrows and nothing new")
            expect(GlobalShortcutSettings.numberedExpandEnabled, "an upgrade keeps ⌃⌘1…9")
            expect(GlobalShortcutSettings.isAllDefault, "an untouched upgrade still counts as the defaults (restore button stays off)")
            expect(defaults.object(forKey: "GlobalShortcut.toggleShade") == nil, "nothing is copied into the per-shortcut settings")
            // 他关掉一个、改掉一个：照他的；恢复默认回到他原来的那一套，而不是清空。
            GlobalShortcutSettings.setHotKey(nil, for: .leftHalf)
            GlobalShortcutSettings.setHotKey(ctrlCmd(kVK_ANSI_K), for: .toggleShade)
            GlobalShortcutSettings.numberedExpandEnabled = false
            expect(GlobalShortcutSettings.hotKey(for: .leftHalf) == nil && GlobalShortcutSettings.hotKey(for: .toggleShade) == ctrlCmd(kVK_ANSI_K)
                    && !GlobalShortcutSettings.numberedExpandEnabled,
                   "an upgrade can still clear or re-record its shortcuts")
            GlobalShortcutSettings.resetAll()
            expect(GlobalShortcut.allCases.allSatisfy { GlobalShortcutSettings.hotKey(for: $0) == shipped[$0] }
                    && GlobalShortcutSettings.numberedExpandEnabled,
                   "restore defaults on an upgrade brings back the combinations it shipped with")
        }

        // 1.0.15 时关掉过 ⌃⌘1…9、清掉过一个：升级后照旧关着。
        withDefaults({
            $0.set(false, forKey: GlobalShortcutSettings.numberedExpandKey)
            $0.set([Int](), forKey: "GlobalShortcut.pinPreview")
        }) { _ in
            expect(!GlobalShortcutSettings.numberedExpandEnabled && GlobalShortcutSettings.hotKey(for: .pinPreview) == nil
                    && GlobalShortcutSettings.hotKey(for: .toggleShade) == shipped[.toggleShade],
                   "what an upgrade had switched off stays off, the rest keep working")
        }

        withDefaults({ $0.set(true, forKey: InstallHistory.previewMarker) }) { _ in
            let expected = shipped.merging(previewOnly) { a, _ in a }
            expect(GlobalShortcut.allCases.allSatisfy { GlobalShortcutSettings.hotKey(for: $0) == expected[$0] },
                   "a Mac that ran the 1.0.16 preview also keeps ⌃⌘S / L / M / N / H")
        }
        withDefaults({
            $0.set(true, forKey: InstallHistory.previewMarker)
            $0.set([Int](), forKey: "GlobalShortcut.magicTile")
        }) { _ in
            expect(GlobalShortcutSettings.hotKey(for: .magicTile) == nil,
                   "a preview default that was left off because it clashed stays off")
        }
    }

    // MARK: 让开这个 App

    static func dockClickDefault() {
        expect(!DockClickHideDefault.isOn(previewInstall: false, origin: .windows), "off for people who came from Windows")
        expect(!DockClickHideDefault.isOn(previewInstall: false, origin: .ipad), "off for people who came from iPad")
        expect(DockClickHideDefault.isOn(previewInstall: false, origin: .mac), "on for people who always used a Mac")
        expect(DockClickHideDefault.isOn(previewInstall: false, origin: .unanswered), "on when nobody answered")
        expect(DockClickHideDefault.isOn(previewInstall: true, origin: .windows), "people who already had it on keep it on")
    }

    static func dockClickGuard() {
        typealias W = DockClickGuard.Window
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1107)
        let side = CGRect(x: 1710, y: 0, width: 1920, height: 1080)
        func window(_ id: CGWindowID, _ rect: CGRect, onScreen: Bool = true, layer: Int = 0, alpha: Double = 1) -> W {
            W(id: id, bounds: rect, onScreen: onScreen, layer: layer, alpha: alpha)
        }
        let front = window(1, CGRect(x: 100, y: 100, width: 800, height: 600))
        func survey(_ windows: [W], managed: Set<CGWindowID> = [], minimized: [CGWindowID] = [], standard: Set<CGWindowID>? = nil,
                    spaces: [CGWindowID: UInt64] = [:], current: Set<UInt64> = [7]) -> DockClickGuard.Survey {
            // 没特别说时，每扇都是辅助功能列出来的标准窗口。
            DockClickGuard.survey(windows: windows, screens: [screen, side], managed: managed, minimized: minimized,
                                  standard: standard ?? Set(windows.map(\.id)), spaceOf: { spaces[$0] }, currentSpaces: current)
        }

        let plain = survey([front, window(9, CGRect(x: 0, y: 0, width: 40, height: 30)), window(8, screen, layer: 25)])
        expect(DockClickGuard.action(for: plain) == .hide, "one window in view, nothing hidden: step aside as before")

        let nothing = survey([window(1, front.bounds, onScreen: false)], minimized: [1])
        expect(DockClickGuard.action(for: nothing) == .leave, "no window in view: leave the click to the system")

        let tiny = survey([window(2, CGRect(x: 0, y: 0, width: 60, height: 40))])
        expect(DockClickGuard.action(for: tiny) == .leave, "only a tiny window counts as nothing in view (same rule as before)")

        let withMinimized = survey([front, window(2, front.bounds, onScreen: false), window(3, front.bounds, onScreen: false)],
                                   minimized: [3, 2])
        expect(DockClickGuard.action(for: withMinimized) == .bringBack(3),
               "a minimized window: don't step aside, bring the first one back")

        let collapsed = survey([front, window(2, front.bounds, onScreen: false)], managed: [2], minimized: [2])
        expect(DockClickGuard.action(for: collapsed) == .hide,
               "a window WindowShade itself collapsed does not count and is never unminimized here")

        let otherDesktop = survey([front, window(4, front.bounds, onScreen: false)], spaces: [4: 12])
        expect(otherDesktop.elsewhere == [4] && DockClickGuard.action(for: otherDesktop) == .bringBack(nil),
               "a window on another desktop: don't step aside (nothing to unminimize)")

        let sameDesktop = survey([front, window(4, front.bounds, onScreen: false)], spaces: [4: 7])
        expect(DockClickGuard.action(for: sameDesktop) == .hide, "an ordered-out window on this desktop is not a lost window")

        let noSpaceInfo = survey([front, window(4, front.bounds, onScreen: false)], spaces: [4: 12], current: [])
        expect(DockClickGuard.action(for: noSpaceInfo) == .hide, "without desktop info nothing is guessed to be elsewhere")

        let unknownSpace = survey([front, window(4, front.bounds, onScreen: false)])
        expect(DockClickGuard.action(for: unknownSpace) == .hide, "a window that belongs to no desktop is ignored")

        let farAway = window(5, CGRect(x: -3000, y: 200, width: 800, height: 600))
        let offscreen = survey([front, farAway])
        expect(offscreen.offscreen == [5] && DockClickGuard.action(for: offscreen) == .bringBack(nil),
               "a standard window entirely outside every screen: don't step aside")
        expect(DockClickGuard.outsideScreens(windows: [front, farAway], screens: [screen, side], managed: []) == [5],
               "only then is the app asked whether it is a standard window")

        let helper = survey([front, farAway], standard: [1])
        expect(helper.offscreen.isEmpty && DockClickGuard.action(for: helper) == .hide,
               "a window parked off screen that the app does not list as a standard window is ignored (step aside as before)")

        let unanswered = survey([front, farAway], standard: [])
        expect(DockClickGuard.action(for: unanswered) == .hide,
               "when the app does not answer, nothing off screen is guessed to be a lost window")

        expect(DockClickGuard.outsideScreens(windows: [front, farAway], screens: [screen, side], managed: [5]).isEmpty,
               "a window WindowShade itself parked off screen is never asked about")

        let onSecondScreen = survey([front, window(6, CGRect(x: 1800, y: 100, width: 800, height: 600))])
        expect(DockClickGuard.action(for: onSecondScreen) == .hide, "a window on the other display is in view")

        let partly = survey([front, window(6, CGRect(x: -700, y: 100, width: 800, height: 600))])
        expect(DockClickGuard.action(for: partly) == .hide, "a window with a sliver on screen is not counted as lost")

        let transparent = survey([front, window(7, CGRect(x: -3000, y: 200, width: 800, height: 600), alpha: 0)])
        expect(DockClickGuard.action(for: transparent) == .hide, "an invisible off-screen helper window is ignored")
    }
}
