// 编程会话成为持续活动（M08）：权重排序、等你只开口一次、做完 2.6 秒后移除、菜单行出现和消失、
// 同一会话 60 秒内只说一次完成、“过去”认终端窗口。只通过公开 API 观察；纯 Foundation，无权限、无 UI。

import Foundation

@main struct SessionActivityTests {
    nonisolated(unsafe) static var assertions = 0

    static func expect(_ condition: Bool, _ message: String) {
        assertions += 1
        precondition(condition, "断言失败: \(message)")
    }

    typealias Change = CodingSessionActivities.Change
    static func change(_ status: CodingSessionActivities.Status, project: String = "WindowShade",
                       cwd: String = "/Users/a/WindowShade", summary: String = "", files: Int? = nil) -> Change {
        change("s1", status, project: project, cwd: cwd, summary: summary, files: files)
    }
    static func change(_ id: String, _ status: CodingSessionActivities.Status, project: String = "WindowShade",
                       cwd: String = "/Users/a/WindowShade", summary: String = "", files: Int? = nil) -> Change {
        Change(id: id, project: project, cwd: cwd, assistant: "Claude Code", status: status, summary: summary, changedFiles: files)
    }

    static func main() {
        testWeights()
        testSessionOutranksOthersButKeepsLimits()
        testBloomOnlyOncePerWaitingEpisode()
        testCompletionLifecycleInStore()
        testCompletionSubtitleNeverInventsNumbers()
        testCompletionCooldown()
        testCompactAndCount()
        testMenuRowsAppearAndDisappear()
        testWaitingDirectoriesAndTarget()
        testWindowMatch()
        print("PASS session activity (\(assertions) assertions)")
    }

    // 1) 权重按稿重排。
    static func testWeights() {
        let table: [(NotchActivityKind, Int)] = [
            (.session, 95), (.recording, 90), (.download, 80), (.copy, 80), (.airDrop, 80), (.focus, 70),
            (.route, 60), (.music, 40), (.remote, 30), (.airPods, 20),
        ]
        for (kind, weight) in table { expect(kind.priority == weight, "\(kind) 权重 \(weight)") }
        expect(NotchActivityKind.carPlayPriority == 100, "CarPlay 权重 100")
        expect(NotchActivityKind.allCases.allSatisfy { $0.priority < NotchActivityKind.carPlayPriority }, "没有哪个种类压过 CarPlay")
        expect(Set(NotchActivityKind.allCases.map(\.priority)).count == NotchActivityKind.allCases.count - 2,
               "只有下载、拷贝与隔空投送同为进度类的 80")
    }

    static func activity(_ id: String, _ kind: NotchActivityKind, at start: Double = 0, title: String = "t") -> NotchActivity {
        NotchActivity(id: id, generation: 1, kind: kind, title: title, startedAt: start)
    }

    // 2) 排序：会话在录音之前；可见上限仍是 3；内容更新不打乱选中项。
    static func testSessionOutranksOthersButKeepsLimits() {
        var store = NotchActivityStore()
        _ = store.upsert(activity("m", .music, at: 1), now: 5)
        _ = store.upsert(activity("f", .focus, at: 2), now: 5)
        _ = store.upsert(activity("r", .recording, at: 3), now: 5)
        _ = store.upsert(activity("s", .session, at: 4), now: 5)
        _ = store.upsert(activity("d", .download, at: 0), now: 5)
        expect(store.activities.map(\.id) == ["s", "r", "d", "f", "m"], "会话 95 > 录音 90 > 下载 80 > 番茄钟 70 > 音乐，实际 \(store.activities.map(\.id))")
        expect(NotchActivityStore.visibleLimit == 3 && store.visible.map(\.id) == ["s", "r", "d"], "可见仍是前三")
        expect(store.select(id: "r"), "选中录音")
        var updated = activity("s", .session, at: 4, title: "改了标题")
        updated.updatedAt = 6
        _ = store.upsert(updated, now: 6)
        expect(store.selectedID == "r", "会话内容更新不打乱选中项")
        expect(store.activities.map(\.id) == ["s", "r", "d", "f", "m"], "内容更新不重排")
    }

    // 3) 等你只开口一次；离开等你再等才再开口。
    static func testBloomOnlyOncePerWaitingEpisode() {
        var model = CodingSessionActivities()
        expect(model.apply(change(.running), now: 1).bloom == nil, "在跑不开口")
        let first = model.apply(change(.waiting, summary: "Bash"), now: 2)
        expect(first.bloom == CodingSessionActivities.Bloom(sessionID: "s1", headline: "WindowShade在等你", detail: "Claude Code想执行 Bash"),
               "进入等你开口：主句“项目在等你”，副句“助手想执行 摘要”")
        expect(model.apply(change(.waiting, summary: "Bash"), now: 3).bloom == nil, "同一次等你不重复")
        expect(model.apply(change(.waiting, summary: "Edit"), now: 4).bloom == nil, "摘要换了也不重复")
        expect(model.apply(change(.running), now: 5).bloom == nil, "回到在跑不开口")
        expect(model.apply(change(.waiting, summary: "Write"), now: 6).bloom?.detail == "Claude Code想执行 Write", "下一次等你再开口一次")
        let placeholder = model.apply(change("s2", .waiting, summary: "需要你确认"), now: 7)
        expect(placeholder.bloom?.detail == "Claude Code在等你确认", "占位说明不当作要执行的东西念出来")
        let noProject = model.apply(change("s3", .waiting, project: "", cwd: ""), now: 8)
        expect(noProject.bloom?.headline == "Claude Code在等你", "没有项目名时用助手名")
    }

    // 4) 做完：✓ 留 4 秒（《实时活动晋级》生命周期表的默认收场），之后活动消失；store 里确实移除。
    static func testCompletionLifecycleInStore() {
        var model = CodingSessionActivities()
        var store = NotchActivityStore()
        _ = model.apply(change(.running), now: 10)
        // 持续那一条收场立即：做完那一条就是最后的样子（控制器也这么给）。
        _ = store.upsert(NotchActivity(id: CodingSessionActivities.activityID, generation: 1, kind: .session, title: "WindowShade",
                                       startedAt: 10, sessionPhase: .running, closing: .immediate), now: 10)
        let out = model.apply(change(.completed), now: 20)
        expect(out.completed, "第一次做完要提醒")
        expect(model.liveSpec == nil, "做完后持续那一条没了")
        guard let spec = model.doneSpec(at: 20) else { return expect(false, "做完提醒存在") }
        expect(spec.title == "完成" && spec.subtitle == "WindowShade" && spec.phase == .done, "主句“完成”，副句是项目名")
        expect(spec.expiresAt == 20 + CodingSessionActivities.completionLifetime && CodingSessionActivities.completionLifetime == 4, "4 秒")
        expect(store.end(id: CodingSessionActivities.activityID, generation: 1, now: 20), "持续那条收掉")
        expect(store.upsert(NotchActivity(id: CodingSessionActivities.completionID, generation: 2, kind: .session, title: spec.title,
                                          subtitle: spec.subtitle, startedAt: 20, expiresAt: spec.expiresAt, sessionPhase: .done,
                                          closing: .immediate), now: 20),
               "做完提醒进 store")
        expect(store.activities.count == 1, "只剩做完这一条")
        expect(model.doneSpec(at: 23.9) != nil && store.activities.count == 1, "3.9 秒时还在")
        store.prune(now: 24)
        expect(store.activities.isEmpty, "4 秒后活动消失")
        expect(model.doneSpec(at: 24) == nil, "模型也不再给出做完那一条")
    }

    // 5) 副句：拿得到改了几个文件才写，拿不到写项目名，不编数字。
    static func testCompletionSubtitleNeverInventsNumbers() {
        var model = CodingSessionActivities()
        _ = model.apply(change("a", .running), now: 1)
        _ = model.apply(change("a", .completed, files: 3), now: 2)
        expect(model.doneSpec(at: 2)?.subtitle == "改了 3 个文件", "拿到个数就写")
        _ = model.apply(change("b", .completed, project: "blog"), now: 3)
        expect(model.doneSpec(at: 3)?.subtitle == "blog", "拿不到就写项目名")
        expect(!(model.doneSpec(at: 3)?.subtitle.contains("个文件") ?? true), "不编个数")
        _ = model.apply(change("c", .completed, project: "", cwd: ""), now: 4)
        expect(model.doneSpec(at: 4)?.subtitle == "Claude Code", "项目名也没有就写助手名")
    }

    // 6) 同一会话完成提醒 60 秒内只说一次；别的会话不受影响。
    static func testCompletionCooldown() {
        var model = CodingSessionActivities()
        expect(model.apply(change(.completed), now: 100).completed, "第一次说")
        _ = model.apply(change(.running), now: 110)
        expect(!model.apply(change(.completed), now: 120).completed, "60 秒内的第二次 Stop 不说")
        _ = model.apply(change(.running), now: 130)
        expect(!model.apply(change(.completed), now: 159.9).completed, "还差一点也不说")
        _ = model.apply(change(.running), now: 160)
        expect(model.apply(change(.completed), now: 160).completed, "满 60 秒再说")
        expect(model.apply(change("other", .completed), now: 161).completed, "别的会话各算各的")
        expect(CodingSessionActivities.completionCooldown == 60, "冷却 60 秒（暂定）")
    }

    // 7) 紧凑：一个会话写项目名，两个以上写“n 个会话”；右耳在跑是转圈（无字）、等你是“等你”。
    static func testCompactAndCount() {
        var model = CodingSessionActivities()
        expect(model.liveSpec == nil, "没有会话就没有活动")
        _ = model.apply(change("a", .running), now: 1)
        var spec = model.liveSpec
        expect(spec?.title == "WindowShade" && spec?.symbol == "terminal" && spec?.trailing == "" && spec?.phase == .running,
               "在跑：左耳项目名，右耳是转圈（没有字）")
        expect(spec?.subtitle == "Claude Code在跑", "在跑的副句")
        _ = model.apply(change("a", .waiting, summary: "Bash"), now: 2)
        spec = model.liveSpec
        expect(spec?.trailing == "等你" && spec?.phase == .waiting, "等你：右耳“等你”")
        expect(spec?.subtitle == "Claude Code想执行 Bash", "等你的副句")
        _ = model.apply(change("b", .running, project: "blog", cwd: "/Users/a/blog"), now: 3)
        spec = model.liveSpec
        expect(spec?.title == "2 个会话", "两个会话写“2 个会话”")
        expect(spec?.phase == .waiting && spec?.trailing == "等你" && spec?.cwd == "/Users/a/WindowShade", "有人等你时右耳仍是等你，去等你的那个")
        _ = model.apply(change("a", .running), now: 4)
        expect(model.liveSpec?.phase == .running && model.liveSpec?.subtitle == "2 个在跑", "都在跑：转圈")
        _ = model.apply(change("a", .gone), now: 5)
        expect(model.liveSpec?.title == "blog", "回到一个会话写项目名")
        _ = model.apply(change("b", .gone, project: "blog", cwd: "/Users/a/blog"), now: 6)
        expect(model.liveSpec == nil, "都结束了活动就没了")
        // 频率与转圈参数
        let rate = NotchSessionEar.spinnerFrameRate
        expect(rate.minimum == 10 && rate.maximum == 20 && rate.preferred == 15, "转圈帧率 10…20，首选 15")
    }

    // 8) 菜单行：有会话等你才出现，结束就消失。
    static func testMenuRowsAppearAndDisappear() {
        var model = CodingSessionActivities()
        _ = model.apply(change(.running), now: 1)
        expect(model.menuRows.isEmpty, "在跑没有菜单行")
        _ = model.apply(change(.waiting, summary: "Bash"), now: 2)
        expect(model.menuRows == [CodingSessionActivities.MenuRow(sessionID: "s1", title: "Claude Code · 等你")], "等你时出现一行“助手 · 等你”")
        _ = model.apply(change(.running), now: 3)
        expect(model.menuRows.isEmpty, "不等了就消失")
        _ = model.apply(change(.waiting), now: 4)
        _ = model.apply(change(.completed), now: 5)
        expect(model.menuRows.isEmpty, "做完了就消失")
        _ = model.apply(change(.waiting), now: 6)
        _ = model.apply(change(.gone), now: 7)
        expect(model.menuRows.isEmpty, "会话没了就消失")
        _ = model.apply(change("a", .waiting, project: "one"), now: 8)
        _ = model.apply(change("b", .waiting, project: "two"), now: 9)
        expect(model.menuRows.map(\.title) == ["Claude Code · one · 等你", "Claude Code · two · 等你"], "几个同时等，用项目名分开，先来的在前")
        for n in 0..<6 { _ = model.apply(change("x\(n)", .waiting, project: "p\(n)"), now: Double(10 + n)) }
        expect(model.menuRows.count == CodingSessionActivities.menuRowLimit, "最多 3 行")
        model.reset()
        expect(model.menuRows.isEmpty && model.liveSpec == nil && model.doneSpec(at: 0) == nil, "整个关掉后什么都不剩")
    }

    // 9) 给 NotchTile 读的接口，和“过去”去哪个会话。
    static func testWaitingDirectoriesAndTarget() {
        var model = CodingSessionActivities()
        _ = model.apply(change("a", .waiting), now: 1)
        _ = model.apply(change("b", .running, project: "blog", cwd: "/Users/a/blog"), now: 2)
        expect(model.isWaiting(cwd: "/Users/a/WindowShade") && !model.isWaiting(cwd: "/Users/a/blog"), "只有在等你的目录算等你")
        expect(model.waitingDirectories == ["/Users/a/WindowShade"], "等你的目录集合")
        expect(!model.isWaiting(cwd: ""), "空目录不算")
        expect(model.target(forActivity: CodingSessionActivities.activityID, at: 3)?.cwd == "/Users/a/WindowShade", "持续那条去等你的会话")
        _ = model.apply(change("a", .completed), now: 4)
        expect(model.target(forActivity: CodingSessionActivities.completionID, at: 4)?.cwd == "/Users/a/WindowShade", "做完那条去做完的会话")
        expect(model.target(forActivity: CodingSessionActivities.completionID, at: 8) == nil, "过期后没有去处")
        expect(model.target(forActivity: "other", at: 4) == nil, "别的活动不归这里")
    }

    // 10) “过去”认终端窗口：文档或标题里对上目录。
    static func testWindowMatch() {
        typealias M = AgentSessionWindowMatch
        let home = "/Users/a"
        expect(M.terminalBundleIDs == ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable"],
               "四个终端的 bundle ID")
        expect(M.strength(cwd: "/Users/a/proj", title: nil, document: "file:///Users/a/proj/", home: home) == .strong, "AXDocument 是 file 地址")
        expect(M.strength(cwd: "/Users/a/proj", title: nil, document: "file://localhost/Users/a/proj", home: home) == .strong, "带 localhost 的 file 地址")
        expect(M.strength(cwd: "/Users/a/proj", title: nil, document: "/Users/a/proj", home: home) == .strong, "AXDocument 直接是路径")
        expect(M.strength(cwd: "/Users/a/proj", title: nil, document: "file:///Users/a/other", home: home) == nil, "别的目录不算")
        expect(M.strength(cwd: "/Users/a/My Proj", title: nil, document: "file:///Users/a/My%20Proj", home: home) == .strong, "百分号转义")
        expect(M.strength(cwd: "/Users/a/proj", title: "claude — /Users/a/proj — 80x24", document: nil, home: home) == .strong, "标题里有完整路径")
        expect(M.strength(cwd: "/Users/a/proj", title: "~/proj", document: nil, home: home) == .strong, "标题里是 ~ 写法")
        expect(M.strength(cwd: "/Users/a/proj", title: "a@mac: ~/proj", document: nil, home: home) == .strong, "冒号后的 ~ 写法")
        expect(M.strength(cwd: "/Users/a/proj", title: "~/proj-two", document: nil, home: home) == nil, "更长的目录名不算")
        expect(M.strength(cwd: "/Users/a/proj", title: "~/proj/sub", document: nil, home: home) == nil, "子目录里的终端不算")
        expect(M.strength(cwd: "/Users/a/proj", title: "/Users/a/project", document: nil, home: home) == nil, "前缀相同的路径不算")
        expect(M.strength(cwd: "/Users/a", title: "~", document: nil, home: home) == .strong, "家目录写成 ~")
        expect(M.strength(cwd: "/Users/a/proj", title: "proj", document: nil, home: home) == .weak, "只有目录名是弱匹配")
        expect(M.strength(cwd: "/Users/a/proj", title: "✳ proj · claude", document: nil, home: home) == .weak, "按分隔符拆出目录名")
        expect(M.strength(cwd: "/Users/a/proj", title: "project", document: nil, home: home) == nil, "目录名只作整段匹配")
        expect(M.strength(cwd: "", title: "x", document: "y", home: home) == nil && M.strength(cwd: "relative", title: "relative", document: nil, home: home) == nil,
               "没有绝对路径就不找")
        expect(M.strength(cwd: "/", title: "/", document: nil, home: home) == nil, "根目录不找")
        let candidates: [M.Candidate] = [
            .init(windowID: 1, pid: 10, title: "proj", document: nil),
            .init(windowID: 2, pid: 11, title: "zsh", document: "file:///Users/a/proj"),
            .init(windowID: 3, pid: 12, title: "~/proj", document: nil),
        ]
        expect(M.best(cwd: "/Users/a/proj", among: candidates, home: home)?.windowID == 2, "完整匹配优先于弱匹配，同强度取前面的")
        expect(M.best(cwd: "/Users/a/none", among: candidates, home: home) == nil, "找不到是 nil，由调用方打开会话页")
        expect(M.best(cwd: "/Users/a/proj", among: [], home: home) == nil, "没有终端窗口是 nil")
    }
}
