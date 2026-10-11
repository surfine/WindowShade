import Foundation

// 自带的小断言器：不去拉整套 WS2 测试支持。
struct TestSuite {
    let name: String
    private(set) var assertions = 0
    private(set) var cases = 0
    private(set) var failures = 0
    init(_ name: String) { self.name = name }
    mutating func section(_ id: String, _ description: String) { cases += 1; print("CASE \(id) | \(description)") }
    mutating func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if condition() { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }
    func finish() {
        print("\(failures == 0 ? "PASS" : "FAIL") \(name): \(cases) cases, \(assertions) assertions, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}

// M13：最小呈现。纯逻辑：开关关着时的布局决策逐字不变（快照现有规则）、开关开着时最小形的选择与几何、
// 互换、读屏标签、进度弧、提醒撞上播放时的走法。画面（NotchMinimumView 的图层）在 AppKit 那一层，由整模块检查和真机验收看。

@main
struct NotchMinimalTests {
    static func item(_ id: String, _ kind: NotchActivityKind, title: String = "", progress: NotchActivity.Quantity = .unknown) -> NotchActivity {
        NotchActivity(id: id, kind: kind, title: title.isEmpty ? id : title, startedAt: 1, progress: progress)
    }

    static func main() {
        var t = TestSuite("M13")
        let music = item("m", .music, title: "夜航")
        let download = item("d", .download, title: "安装包", progress: .fraction(0.4))
        let session = item("s", .session, title: "Claude Code")
        let items = [session, download, music]

        t.section("M13-01", "开关默认关，键名固定")
        t.expect(NotchMinimalPresentation.defaultEnabled == false, "1.0.16 真机验过前默认关（ReleaseDefaults；设计上默认开）")
        for (stored, expected, label) in [(nil, false, "键为 nil"), (true, true, "显式开"), (false, false, "显式关")] as [(Bool?, Bool, String)] {
            let suite = "NotchMinimalTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            if let stored { defaults.set(stored, forKey: NotchMinimalPresentation.defaultsKey) }
            t.expect(NotchMinimalPresentation.isEnabled(in: defaults) == expected, "读值：\(label) → \(expected)")
            defaults.removePersistentDomain(forName: suite)
        }
        t.expect(NotchMinimalPresentation.defaultsKey == "Notch.minimalPresentation", "defaults 键是 Notch.minimalPresentation")

        t.section("M13-02", "显式关着：布局决策和旧版一模一样（快照）")
        // 现有规则：紧凑是选中的那件，选中的不在了就第一件；没有任何最小形。
        let offSelected = NotchMinimalPresentation.layout(items: items, selected: "d", enabled: false)
        t.expect(offSelected.compact?.id == "d" && offSelected.minimum.isEmpty, "选中 d：紧凑 d，没有最小形")
        let offStale = NotchMinimalPresentation.layout(items: items, selected: "gone", enabled: false)
        t.expect(offStale.compact?.id == "s" && offStale.minimum.isEmpty, "选中的不在了：退回第一件 s")
        let offNone = NotchMinimalPresentation.layout(items: items, selected: nil, enabled: false)
        t.expect(offNone.compact?.id == "s" && offNone.minimum.isEmpty, "没有选中：第一件 s")
        t.expect(NotchMinimalPresentation.layout(items: [], selected: nil, enabled: false) == .init(compact: nil, minimum: []),
                 "没有活动：什么都没有")
        for selected in [nil, "s", "d", "m", "gone"] as [String?] {
            let legacy = items.first(where: { $0.id == selected }) ?? items.first
            t.expect(NotchMinimalPresentation.compactItem(in: items, selected: selected)?.id == legacy?.id,
                     "紧凑那件与旧写法一致（选中 \(selected ?? "nil")）")
        }
        // 提醒撞上播放：关着时保持第二颗岛（split）的触发条件：有持续活动且没有音量亮度条。
        t.expect(NotchMinimalPresentation.alertPlan(hasActivities: true, meterShowing: false, enabled: false) == .split,
                 "关着 + 有活动 + 没有音量条：split")
        t.expect(NotchMinimalPresentation.alertPlan(hasActivities: true, meterShowing: true, enabled: false) == .bloom,
                 "关着 + 音量条在：和现在一样不 split")
        t.expect(NotchMinimalPresentation.alertPlan(hasActivities: false, meterShowing: false, enabled: false) == .bloom,
                 "关着 + 没有活动：和现在一样直接出提醒")

        t.section("M13-03", "开关开着：选中的是紧凑，其余退成最小")
        let on = NotchMinimalPresentation.layout(items: items, selected: "d", enabled: true)
        t.expect(on.compact?.id == "d", "紧凑还是选中的那件")
        t.expect(on.minimum.map(\.id) == ["s", "m"], "其余按原顺序退成最小")
        let single = NotchMinimalPresentation.layout(items: [music], selected: "m", enabled: true)
        t.expect(single.compact?.id == "m" && single.minimum.isEmpty, "只有一件：没有最小形")
        let two = NotchMinimalPresentation.layout(items: [music, download], selected: nil, enabled: true)
        t.expect(two.compact?.id == "m" && two.minimum.map(\.id) == ["d"], "两件、没有选中：第一件紧凑，另一件最小")

        t.section("M13-04", "点最小形：和紧凑互换")
        // 点最小形 = 选中那一件，下一次布局里原来的紧凑退成最小。
        let before = NotchMinimalPresentation.layout(items: [music, download], selected: "m", enabled: true)
        let tapped = before.minimum[0].id
        let after = NotchMinimalPresentation.layout(items: [music, download], selected: tapped, enabled: true)
        t.expect(before.compact?.id == "m" && before.minimum.map(\.id) == ["d"], "点之前：m 紧凑、d 最小")
        t.expect(after.compact?.id == "d" && after.minimum.map(\.id) == ["m"], "点之后：d 紧凑、m 最小")
        let swapBack = NotchMinimalPresentation.layout(items: [music, download], selected: after.minimum[0].id, enabled: true)
        t.expect(swapBack == before, "再点一次回到原样")

        t.section("M13-05", "提醒撞上正在播放：开着不出第二颗岛")
        t.expect(NotchMinimalPresentation.alertPlan(hasActivities: true, meterShowing: false, enabled: true) == .bloom,
                 "开着 + 有活动：这一颗岛 bloom 成提醒")
        t.expect(NotchMinimalPresentation.alertPlan(hasActivities: true, meterShowing: true, enabled: true) == .bloom,
                 "开着 + 音量条在：也是 bloom")
        t.expect(NotchMinimalPresentation.alertPlan(hasActivities: false, meterShowing: false, enabled: true) == .bloom,
                 "开着 + 没有活动：照旧直接出提醒")

        t.section("M13-06", "几何：有刘海 36×28，没有刘海 26×22")
        t.expect(NotchMinimalPresentation.size(for: .notched) == CGSize(width: 36, height: 28), "刘海屏 36×28")
        t.expect(NotchMinimalPresentation.size(for: .capsule) == CGSize(width: 26, height: 22), "无刘海胶囊 26×22")
        let island = CGRect(x: 100, y: 800, width: 200, height: 32)
        let one = NotchMinimalPresentation.frames(island: island, count: 1, placement: .notched)
        t.expect(one == [CGRect(x: 306, y: 802, width: 36, height: 28)], "贴着右边缘 + 6，竖直居中")
        let both = NotchMinimalPresentation.frames(island: island, count: 2, placement: .notched)
        t.expect(both.count == 2 && both[1].minX == both[0].maxX + NotchMinimalPresentation.gap, "两颗之间也是 6")
        t.expect(both.allSatisfy { $0.minX >= island.maxX }, "都在岛的右侧，不压到岛")
        let capsule = NotchMinimalPresentation.frames(island: CGRect(x: 0, y: 10, width: 200, height: 26), count: 1, placement: .capsule)
        t.expect(capsule == [CGRect(x: 206, y: 12, width: 26, height: 22)], "胶囊：26×22 居中")
        t.expect(NotchMinimalPresentation.frames(island: island, count: 0, placement: .notched).isEmpty, "0 颗没有外框")

        t.section("M13-07", "空位不够就不画，不压到菜单栏图标")
        let need1 = NotchMinimalPresentation.roomNeeded(count: 1, placement: .notched)
        let need2 = NotchMinimalPresentation.roomNeeded(count: 2, placement: .notched)
        t.expect(need1 == 54 + 6 + 36 && need2 == 54 + 6 + 36 + 6 + 36, "刘海屏：岛伸出 54 + 6 + 每颗 36（颗间 6）")
        t.expect(NotchMinimalPresentation.measuredReach(for: .notched) == need2, "量空位量到放得下两颗为止")
        t.expect(NotchMinimalPresentation.fittingCount(wanted: 2, room: need2, placement: .notched) == 2, "刚好放得下两颗")
        t.expect(NotchMinimalPresentation.fittingCount(wanted: 2, room: need2 - 1, placement: .notched) == 1, "差 1 点：只画一颗")
        t.expect(NotchMinimalPresentation.fittingCount(wanted: 2, room: need1 - 1, placement: .notched) == 0, "一颗也放不下：不画")
        t.expect(NotchMinimalPresentation.fittingCount(wanted: 2, room: nil, placement: .notched) == 0, "还没量到空位：不画")
        t.expect(NotchMinimalPresentation.fittingCount(wanted: 5, room: 1000, placement: .notched) == 2, "最多两颗")
        t.expect(NotchMinimalPresentation.fittingCount(wanted: 0, room: 1000, placement: .capsule) == 0, "没有要画的就是 0")
        t.expect(NotchMinimalPresentation.roomNeeded(count: 1, placement: .capsule) == 100 + 6 + 26, "胶囊：伸出 100 + 6 + 26")

        t.section("M13-08", "点中哪一颗")
        t.expect(NotchMinimalPresentation.index(at: CGPoint(x: 310, y: 810), in: both) == 0, "点在第一颗里")
        t.expect(NotchMinimalPresentation.index(at: CGPoint(x: both[1].midX, y: 810), in: both) == 1, "点在第二颗里")
        t.expect(NotchMinimalPresentation.index(at: CGPoint(x: both[0].maxX + 2, y: 810), in: both) == nil, "点在两颗之间的缝里：不算")
        t.expect(NotchMinimalPresentation.index(at: CGPoint(x: 200, y: 810), in: both) == nil, "点在岛上：不算")

        t.section("M13-09", "读屏标签：正在进行：标题")
        t.expect(NotchMinimalPresentation.label(for: music) == "正在进行：夜航", "标签带标题")
        t.expect(NotchMinimalPresentation.label(for: session) == "正在进行：Claude Code", "会话的标签")

        t.section("M13-10", "进度弧：只有比例画弧")
        t.expect(NotchMinimalPresentation.arcFraction(for: download) == 0.4, "比例 0.4 画 0.4 的弧")
        t.expect(NotchMinimalPresentation.arcFraction(for: item("x", .copy, progress: .fraction(1))) == 1, "满了是整圈")
        t.expect(NotchMinimalPresentation.arcFraction(for: item("x", .copy, progress: .count(2, 5))) == nil, "个数只画圆点")
        t.expect(NotchMinimalPresentation.arcFraction(for: item("x", .copy, progress: .indeterminate)) == nil, "不确定只画圆点")
        t.expect(NotchMinimalPresentation.arcFraction(for: music) == nil, "什么都不知道只画圆点")
        t.expect(NotchMinimalPresentation.arcFraction(for: item("x", .copy, progress: .fraction(.nan))) == nil, "非有限数不画弧")
        t.expect(NotchMinimalPresentation.arcLineWidth == 2, "弧线宽 2pt")
        t.expect(NotchMinimalPresentation.arcDiameter + NotchMinimalPresentation.arcLineWidth <= NotchMinimalPresentation.size(for: .capsule).height,
                 "弧放得进最小的胶囊")

        t.section("M13-11", "弹簧：最小形用 calm(0.34/1.0)")
        t.expect(MotionSpring.calm.response == 0.34 && MotionSpring.calm.dampingRatio == 1, "calm 令牌就是 0.34 / 1.0")

        t.finish()
    }
}
