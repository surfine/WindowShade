// 在刘海上教手势：看准时机（因势利导）教一下，不烦人。纯逻辑，可单测；刘海里的小动画见 App/NotchCoach.swift。
//
// 什么时候教：第一次碰到一样新东西的那一刻——第一次让开 Dock 上的 App、第一次接成卷轴、第一次指针停到刘海上、
// 第一次出现侧拉的把手或分屏的把手。他用自己的办法做成了（手动拖成半屏、用系统的 ⌘Tab、双击收起）就不反过来教我们的做法
// （docs/direction.md：顺利的时候一声不吐）；卡住时才开口的那一套在 HabitRules。
// 规则：同一条最多三次；用户自己用过这个手势就永远不再教；两条之间至少隔五分钟；点一下提示就不再出这一条；设置里能关。
// 卡住时的提示（旧习惯，规则见 Core/HabitRules.swift、docs/stuck-habits.md）和这里共用一本账：同样的次数和“用过就不再说”，
// 五分钟的间隔按两边里最近的那一次算（CoachPacing）；两边的记录各存各的（Notch.coach、Notch.habits），不互相覆盖。

import Foundation

enum CoachTip: String, CaseIterable, Codable {
    /// 标题栏上两指左右滑：半屏。
    case halves
    /// 两指张开：魔法平铺。
    case magic
    /// 拖着标题栏晃一晃：别的窗口让开。
    case shake
    /// 按住 ⌥ 连按 Tab：按窗口切换。
    case switcher
    /// 点一下刘海：回主屏幕；往上推：全部收进刘海。
    case notchHome
    /// 卷轴里标题栏上左右滑：整条跟着走。
    case stripScroll
    /// 再点一下 Dock 图标：回来。
    case dockHide
    /// 标题栏上两指往上推：收起；往下拉：展开。
    case shade
    /// 分屏：拖分屏把手，两扇一起变。
    case splitBar
    /// 侧拉：拖角上的弧（把手）改大小，拖玻璃边框挪位置。界面上不叫这两个名字，只说看得见的样子。
    case slideOverHandle
    /// 用过 Rectangle 的人：设置里一键换上它的快捷键。
    case rectangle
    /// 画中画：把标题栏拖到屏幕角落停一下。
    case pip
    /// 卡住时的提示（旧习惯）：说什么、演什么由那条规则给（HabitRules），这里只给刘海一个放演示的位置。
    /// 不走这本账的 canShow：它的次数和“会了”记在 HabitLedger 里。
    case habit

    /// 刘海里那句话。
    var text: String {
        switch self {
        case .halves: return "下次试试：在标题栏上两指往左滑，就是左半屏"
        case .magic: return "下次试试：在标题栏上两指张开，整块屏一下排好"
        case .shake: return "下次试试：拖着标题栏晃一晃，别的窗口一下让开"
        case .switcher: return "按住 ⌥ 连按 Tab，一扇一扇窗口地挑，收着的也在里面"
        case .notchHome: return "点一下刘海回主屏幕；两指往上推，这块屏的窗口全收进来"
        case .stripScroll: return "在这几扇的标题栏上两指左右滑，整条卷轴跟着走"
        case .dockHide: return "它让开了。再点一下 Dock 图标就回来"
        case .shade: return "也可以在标题栏上两指往上推收起，往下拉展开"
        case .splitBar: return "拖中间的分屏把手，两扇一起变；推到屏幕边，那一扇进侧拉"
        case .slideOverHandle: return "拖角上那段弧改大小；拖窗口外面那一圈挪位置，往屏幕边一甩就收起"
        case .rectangle: return "用过 Rectangle？设置 → 快捷键 → 更多排法，一键换上它的快捷键"
        case .pip: return "把标题栏拖到屏幕角落停一下，窗口缩成画中画，推到边上还能藏起来"
        case .habit: return ""
        }
    }
}

struct GestureCoach: Codable, Equatable {
    static let maxShows = 3
    static let cooldown: TimeInterval = 300
    /// 手动挪窗口：一分钟里第几次开始教魔法平铺。
    static let fiddleCount = 3
    static let fiddleWindow: TimeInterval = 60

    var shown: [CoachTip: Int] = [:]
    var used: Set<CoachTip> = []
    var dismissed: Set<CoachTip> = []
    var lastShownAt: TimeInterval?

    /// 这条现在能不能教。卡住时的提示正在看一件事的那十几秒里，会和它抢的几条先压着（CoachPacing.hold）。
    func canShow(_ tip: CoachTip, at now: TimeInterval) -> Bool {
        guard tip != .habit, !CoachPacing.isHeld(tip) else { return false }
        guard !used.contains(tip), !dismissed.contains(tip), (shown[tip] ?? 0) < Self.maxShows else { return false }
        if let last = CoachPacing.latest(lastShownAt), now - last < Self.cooldown { return false }
        return true
    }

    mutating func didShow(_ tip: CoachTip, at now: TimeInterval) {
        shown[tip, default: 0] += 1
        lastShownAt = now
        CoachPacing.note(now)
    }

    /// 用户自己用过了：这条永远不再教。
    mutating func used(_ tip: CoachTip) { used.insert(tip) }

    /// 点了一下提示：这条不再出。
    mutating func dismiss(_ tip: CoachTip) { dismissed.insert(tip) }
}

/// 手势提示和卡住时的提示共用的节奏：任意两条之间（不管哪一边的）至少隔五分钟。
/// 两边的记录各自存着自己上一次开口的时间；这里是进程里的那一份“最近一次”，启动时各自读回记录后把自己那次报进来。
/// 卡住时的提示要优先：它正在看一件事的那十几秒里（例如从 iPad 来的人刚双击标题栏收起了一扇，看他是不是想铺满），
/// 把会抢在它前面的普通提示（收起后的 .shade、.shake）压住。压住有时限，到点自己放开，不会一直压着。
/// 哪个线程都能读写（手势提示在主线程，卡住判断在自己的队列）。
enum CoachPacing {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var last: TimeInterval?
    nonisolated(unsafe) private static var held: Set<CoachTip> = []
    /// 压到什么时候（开机后的秒数）。
    nonisolated(unsafe) private static var heldUntil: TimeInterval = 0

    /// 两边里最近的一次开口。
    static var lastShownAt: TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        return last
    }

    /// 自己记的那次和共用的那次里较晚的一个。
    static func latest(_ own: TimeInterval?) -> TimeInterval? {
        let shared = lastShownAt
        switch (own, shared) {
        case let (a?, b?): return max(a, b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return nil
        }
    }

    /// 某一边开口了（或启动时读回了上一次）：只往后挪，不往前挪。
    static func note(_ at: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        last = max(last ?? at, at)
    }

    /// 卡住时的提示正在看一件事：这几条普通提示压 duration 秒。再压一次只往后延，不会把还没到点的提前放开。
    static func hold(_ tips: Set<CoachTip>, for duration: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        held = tips
        heldUntil = max(heldUntil, ProcessInfo.processInfo.systemUptime + duration)
    }

    /// 马上放开。
    static func release() {
        lock.lock(); defer { lock.unlock() }
        held = []
        heldUntil = 0
    }

    static func isHeld(_ tip: CoachTip) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return held.contains(tip) && ProcessInfo.processInfo.systemUptime < heldUntil
    }

    /// 测试和探针用：清掉共用的那份（不碰任何记录）。
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        last = nil
        held = []
        heldUntil = 0
    }
}

/// 卡住时的提示那本账（按规则的名字记，见 Core/HabitRules.swift）：规矩和手势提示一样——
/// 同一条最多三次；他自己用过 Mac 上那一下、或者点提示让刘海替他做了，这条永远不再说；点小叉关掉的不再出；
/// 和手势提示共用五分钟的间隔（CoachPacing）。存在 Notch.habits 里，和手势提示的记录分开，互不覆盖。
struct HabitLedger: Codable, Equatable {
    var shown: [String: Int] = [:]
    var used: Set<String> = []
    var dismissed: Set<String> = []
    var lastShownAt: TimeInterval?

    init() {}

    /// 这条已经不用再说了：会了、点掉了、或者说满了三次。
    func isDone(_ id: String) -> Bool {
        used.contains(id) || dismissed.contains(id) || (shown[id] ?? 0) >= GestureCoach.maxShows
    }

    /// 这条现在能不能说：没说完，而且离上一条提示（不管是哪一边的）已经隔了五分钟。
    func canShow(_ id: String, at now: TimeInterval) -> Bool {
        guard !isDone(id) else { return false }
        if let last = CoachPacing.latest(lastShownAt), now - last < GestureCoach.cooldown { return false }
        return true
    }

    mutating func didShow(_ id: String, at now: TimeInterval) {
        shown[id, default: 0] += 1
        lastShownAt = now
        CoachPacing.note(now)
    }

    /// 他自己用了 Mac 上那一下（或者点提示让刘海替他做了）：这条永远不再说。
    mutating func learned(_ id: String) { used.insert(id) }

    /// 点了小叉：这条不再出。
    mutating func dismiss(_ id: String) { dismissed.insert(id) }

    private enum CodingKeys: String, CodingKey { case shown, used, dismissed, lastShownAt }

    /// 读回来时缺哪一项就当空的（以后加字段、老版本写的记录都读得回来，不会因为少一项整本作废）。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        shown = try values.decodeIfPresent([String: Int].self, forKey: .shown) ?? [:]
        used = try values.decodeIfPresent(Set<String>.self, forKey: .used) ?? []
        dismissed = try values.decodeIfPresent(Set<String>.self, forKey: .dismissed) ?? []
        lastShownAt = try values.decodeIfPresent(TimeInterval.self, forKey: .lastShownAt)
    }
}
