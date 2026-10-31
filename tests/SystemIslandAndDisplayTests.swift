import Foundation

@main
struct SystemIslandAndDisplayTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; print("FAIL \(what)") }
    }
    static func main() {
        // 系统岛：名单现在是空的，任何机型都不让开。
        check(SystemIslandPolicy.modelIdentifiers.isEmpty, "list empty until device measurement")
        check(!SystemIslandPolicy.hasSystemIsland(modelIdentifier: "Mac16,1"), "unknown model does not yield")
        check(!SystemIslandPolicy.hasSystemIsland(modelIdentifier: ""), "empty model does not yield")
        let list: Set<String> = ["Mac99,1"]
        check(SystemIslandPolicy.yields(isBuiltin: true, modelIdentifier: "Mac99,1", in: list), "listed model builtin yields")
        check(!SystemIslandPolicy.yields(isBuiltin: false, modelIdentifier: "Mac99,1", in: list), "external never yields")
        check(!SystemIslandPolicy.yields(isBuiltin: true, modelIdentifier: "Mac16,1", in: list), "unlisted model builtin stays")
        check(!SystemIslandPolicy.yields(isBuiltin: true, modelIdentifier: "Mac99,1"), "default empty list never yields")

        // 摄像头安静：自己长大被压住，你点的照常。
        check(!CameraQuietPolicy.allowsAutoGrowth(cameraInUse: true, userInitiated: false), "camera on: no auto growth")
        check(CameraQuietPolicy.allowsAutoGrowth(cameraInUse: true, userInitiated: true), "camera on: user click opens")
        check(CameraQuietPolicy.allowsAutoGrowth(cameraInUse: false, userInitiated: false), "camera off: unchanged")

        // 活动屏：单屏不变；指针换屏就跟；焦点换屏也跟；都没动留在原处。
        var t = ActiveDisplayTracker()
        check(t.update(displays: [1], builtin: 1, pointer: 1, key: 1) == 1, "single display")
        check(t.update(displays: [1, 2], builtin: 1, pointer: 1, key: 1) == 1, "two displays, stays")
        check(t.update(displays: [1, 2], builtin: 1, pointer: 2, key: 1) == 2, "pointer moves to 2")
        check(t.update(displays: [1, 2], builtin: 1, pointer: 2, key: 1) == 2, "nothing moved: stays 2")
        check(t.update(displays: [1, 2], builtin: 1, pointer: 2, key: 1) == 2, "still 2")
        check(t.update(displays: [1, 2], builtin: 1, pointer: 2, key: 2) == 2, "focus moves to 2: 2")
        check(t.update(displays: [1, 2], builtin: 1, pointer: 2, key: 1) == 1, "focus back to 1 wins")
        // 合盖：内建屏没了，活动挪到外接屏。
        check(t.update(displays: [2], builtin: nil, pointer: nil, key: nil) == 2, "lid closed: moves to external")
        // 让开的内建屏不在候选里：活动只会在外接屏。
        var u = ActiveDisplayTracker()
        check(u.update(displays: [2, 3], builtin: nil, pointer: 1, key: 1) == 2, "yielded builtin: first external")
        check(u.update(displays: [2, 3], builtin: nil, pointer: 3, key: 1) == 3, "pointer to second external")
        // 没有屏
        check(u.update(displays: [], builtin: nil, pointer: nil, key: nil) == nil, "no displays")
        // 启动时：焦点屏优先于内建屏
        var v = ActiveDisplayTracker()
        check(v.update(displays: [1, 2], builtin: 1, pointer: nil, key: 2) == 2, "start: key display")
        var w = ActiveDisplayTracker()
        check(w.update(displays: [2, 1], builtin: 1, pointer: nil, key: nil) == 1, "start: builtin fallback")
        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("PASS system-island-and-display")
    }
}
