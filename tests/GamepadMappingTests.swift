// R09：按钮到动作表、游戏在前台真值表、同一时间只有一台手柄操作。纯 Foundation。
import Foundation

@main struct GamepadMappingTests {
    static func main() {
        var s = TestSuite("GamepadMapping")

        s.section("R09-1", "按钮 → 动作表")
        var t = GamepadButtonTable()
        let immediate: [(String, PadButtonIntent)] = [("up",.focusUp),("down",.focusDown),("left",.focusLeft),("right",.focusRight),
                                                      ("a",.activate),("b",.back),("menu",.mediaPlayPause)]
        for (name, intent) in immediate { s.expect(t.press(name, at: 1) == intent, "\(name) 按下 → \(intent)") }
        for name in ["x","leftShoulder","rightShoulder","home","unknown"] { s.expect(t.press(name, at: 1) == nil, "\(name) 不占") }
        s.expect(t.release("a", at: 2) == nil, "普通键松开不产生动作")

        s.section("R09-2", "△ 短按回到那一排，按住 0.5 秒启动台")
        t = GamepadButtonTable()
        s.expect(t.press("y", at: 10) == nil, "△ 按下先不动")
        s.expect(t.holdElapsed("y", at: 10.2) == nil, "0.2 秒到点不算长按")
        s.expect(t.release("y", at: 10.3) == .returnToRow, "短按松开 → 回到那一排")
        s.expect(t.press("y", at: 20) == nil, "再按")
        s.expect(t.holdElapsed("y", at: 20.5) == .launchpad, "满 0.5 秒 → 启动台")
        s.expect(t.holdElapsed("y", at: 20.6) == nil, "只触发一次")
        s.expect(t.release("y", at: 21) == nil, "长按已触发，松开不再回到那一排")
        s.expect(t.press("y", at: 30) == nil, "晚到定时器")
        s.expect(t.release("y", at: 30.7) == .launchpad, "定时器没到点但松开时已满，补上启动台")
        s.expect(t.press("y", at: 40) == nil && t.holding, "按着时 holding")
        t.cancelAll()
        s.expect(!t.holding && t.release("y", at: 41) == nil && t.holdElapsed("y", at: 41) == nil, "取消后松开、到点都没有动作")
        s.expect(t.press("y", at: 50) == nil && t.release("y", at: 49) == nil, "时间倒退不出动作")

        s.section("R09-3", "游戏判断真值表")
        func cat(_ c: String?, readable: Bool = true) -> GameFrontPolicy.Category { GameFrontPolicy.classify(bundleReadable: readable, category: c) }
        s.expect(cat("public.app-category.games") == .game, "games")
        s.expect(cat("public.app-category.action-games") == .game, "action-games")
        s.expect(cat("Public.App-Category.Board-Games") == .game, "大小写不敏感")
        s.expect(cat("public.app-category.productivity") == .other, "效率 App")
        s.expect(cat("public.app-category.developer-tools") == .other, "开发工具")
        s.expect(cat("com.example.games") == .other, "不是系统分类前缀就不当游戏")
        s.expect(cat(nil) == .uncategorized && cat("") == .uncategorized, "没写分类")
        s.expect(cat("public.app-category.games", readable: false) == .unreadable, "App 读不到")
        let table: [(GameFrontPolicy.Category, Bool?, Bool?, Bool)] = [
            (.game, false, false, true), (.game, nil, nil, true), (.unreadable, false, false, true),
            (.other, false, false, false), (.other, true, false, false), (.other, false, true, false),
            (.other, true, true, true), (.other, nil, false, true), (.other, true, nil, true),
            (.uncategorized, false, false, false), (.uncategorized, true, true, true), (.uncategorized, nil, nil, true),
        ]
        for (c, fs, inUse, want) in table {
            s.expect(GameFrontPolicy.yields(category: c, fullScreen: fs, controllerInUse: inUse) == want,
                     "\(c) fs=\(String(describing: fs)) inUse=\(String(describing: inUse)) → \(want)")
        }

        s.section("R09-4", "同一时间只有一台")
        let a = GamepadSeats.Pad(id: UUID(), key: GamepadSeats.key(vendor: "Sony", category: "DualSense"))
        let b = GamepadSeats.Pad(id: UUID(), key: GamepadSeats.key(vendor: "Xbox", category: "Xbox One"))
        let c = GamepadSeats.Pad(id: UUID(), key: GamepadSeats.key(vendor: "Sony", category: "DualSense"))
        s.expect(GamepadSeats.key(vendor: nil, category: " ") == "?|?", "读不到名字也有键")
        var seats = GamepadSeats()
        var r = seats.update(pads: [a, b], enabledKeys: [])
        s.expect(r[a.id] == .off && r[b.id] == .off && seats.owner == nil, "默认都关")
        r = seats.update(pads: [a, b], enabledKeys: [b.key])
        s.expect(r[a.id] == .off && r[b.id] == .controls, "只开 b → b 操作")
        r = seats.update(pads: [a, b], enabledKeys: [a.key, b.key])
        s.expect(r[a.id] == .viewOnly && r[b.id] == .controls, "再开 a → a 只能看，b 不被抢")
        r = seats.update(pads: [a, b], enabledKeys: [a.key])
        s.expect(r[a.id] == .controls && r[b.id] == .off, "关掉 b → 换 a")
        r = seats.update(pads: [a], enabledKeys: [a.key, b.key])
        s.expect(r[a.id] == .controls && r[b.id] == nil, "b 拔掉不影响 a")
        r = seats.update(pads: [a, c], enabledKeys: [a.key])
        s.expect(r[a.id] == .controls && r[c.id] == .viewOnly, "同键两台：先来的操作，另一台只能看")
        r = seats.update(pads: [c], enabledKeys: [a.key])
        s.expect(r[c.id] == .controls, "操作的那台拔了，换另一台")

        s.section("R09-5", "处理权账本")
        var led = GamepadHandlerLedger<String>()
        s.expect(led.holder(of: "k") == nil && !led.anyHeld(by: .desktop), "一开始没人占")
        s.expect(led.claim("k", by: .desktop), "空键能占")
        s.expect(led.holder(of: "k") == .desktop && led.anyHeld(by: .desktop) && !led.anyHeld(by: .page), "占着的是桌面")
        s.expect(!led.claim("k", by: .page), "别人占着不能抢")
        s.expect(led.holder(of: "k") == .desktop, "抢失败不改占用者")
        s.expect(led.claim("k", by: .desktop), "自己再占返回 true")
        led.release("k", by: .page)
        s.expect(led.holder(of: "k") == .desktop, "非占用者放不掉")
        s.expect(led.claim("j", by: .page) && led.holder(of: "j") == .page && led.holder(of: "k") == .desktop, "不同键互不影响")
        s.expect(led.anyHeld(by: .page), "page 占着 j")
        led.release("k", by: .desktop)
        s.expect(led.holder(of: "k") == nil && !led.anyHeld(by: .desktop), "占用者放掉后空出")
        s.expect(led.claim("k", by: .page), "放掉后另一方能占")
        s.expect(led.holder(of: "j") == .page, "放 k 不动 j")
        s.finish()
    }
}
