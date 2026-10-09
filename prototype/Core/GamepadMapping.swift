// WindowShade 2 · 原创映射。只计算意图，不发送系统输入。
import Foundation
struct GamepadMapping: Sendable {
    struct Vector: Equatable, Sendable { var x: Double; var y: Double; static let zero = Vector(x: 0, y: 0) }
    enum Effect: Equatable, Sendable { case pointer(Vector), scroll(Vector), desktop(Int), releaseTriggers }
    static let deadZone = 0.15
    static let maximumPointerSpeed = 1000.0
    static let maximumScrollSpeed = 800.0
    static let triggerThreshold = 0.6
    static let triggerReset = 0.2
    private(set) var enabled = false
    private var leftArmed = true
    private var rightArmed = true
    private var lastTime: Double?
    mutating func configure(enabled: Bool, gameInFront: Bool) -> [Effect] {
        let next = enabled && !gameInFront
        if next != self.enabled { lastTime = nil; leftArmed = true; rightArmed = true }
        let had = self.enabled; self.enabled = next
        return had && !next ? [.releaseTriggers] : []
    }
    static func axis(_ v: Vector) -> Vector {
        guard v.x.isFinite, v.y.isFinite else { return .zero }
        let x = min(1,max(-1,v.x)), y = min(1,max(-1,v.y))
        let length = hypot(x,y)
        guard length > deadZone else { return .zero }
        let magnitude = pow((min(1,length)-deadZone)/(1-deadZone),2)
        return Vector(x:x/length*magnitude,y:y/length*magnitude)
    }
    mutating func sample(left: Vector, right: Vector, at now: Double) -> [Effect] {
        guard enabled, now.isFinite, now >= 0 else { return [] }
        if let lastTime, now < lastTime { return [] }
        defer { lastTime = now }
        guard let previous = lastTime else { return [] }
        // 唤醒或卡帧不补发整段运动；最大推进 50ms。所有档位是本轮推荐值。
        let dt = min(0.05,now-previous), p = Self.axis(left), s = Self.axis(right)
        var effects: [Effect] = []
        if p != .zero { effects.append(.pointer(Vector(x:p.x*Self.maximumPointerSpeed*dt,y:p.y*Self.maximumPointerSpeed*dt))) }
        if s != .zero { effects.append(.scroll(Vector(x:s.x*Self.maximumScrollSpeed*dt,y:s.y*Self.maximumScrollSpeed*dt))) }
        return dt > 0 ? effects : []
    }
    mutating func trigger(left: Bool, value: Double, desktopEnabled: Bool) -> [Effect] {
        guard enabled, desktopEnabled, value.isFinite, (0...1).contains(value) else { return [] }
        if value <= Self.triggerReset {
            if left { leftArmed = true } else { rightArmed = true }; return []
        }
        let armed = left ? leftArmed : rightArmed
        guard armed, value >= Self.triggerThreshold else { return [] }
        if left { leftArmed = false } else { rightArmed = false }
        return [.desktop(left ? -1 : 1)]
    }
    mutating func disconnect() -> [Effect] { configure(enabled:false,gameInFront:false) }
}

// MARK: - 按键表（R09）
// 十字键、×、○、△、Options 到“刘海那一排”的动作。纯逻辑：不读手柄、不发事件、不开定时器；
// 按住多久由调用方用一次性定时器或时间戳喂进来，不轮询。PS 键（home）永远不占，系统自己用它。
enum PadButtonIntent: Equatable, Sendable {
    case focusUp, focusDown, focusLeft, focusRight
    case activate, back, returnToRow, launchpad, mediaPlayPause
}

struct GamepadButtonTable: Sendable {
    /// △ 按住到这个时间就是“启动台”，不到就是“回到那一排”。
    static let holdSeconds = 0.5
    private var heldSince: [String: Double] = [:]
    private var fired: Set<String> = []

    /// 按下就生效的键。△（y）要等松开或按满 0.5 秒才知道，所以不在这里。
    static func immediateIntent(_ name: String) -> PadButtonIntent? {
        switch name {
        case "up": return .focusUp
        case "down": return .focusDown
        case "left": return .focusLeft
        case "right": return .focusRight
        case "a": return .activate        // ×
        case "b": return .back            // ○
        case "menu": return .mediaPlayPause   // Options
        default: return nil               // x（□）、肩键、home（PS 键）都不占
        }
    }
    static func isHoldKey(_ name: String) -> Bool { name == "y" }   // △

    mutating func press(_ name: String, at now: Double) -> PadButtonIntent? {
        guard now.isFinite else { return nil }
        if Self.isHoldKey(name) {
            if heldSince[name] == nil { heldSince[name] = now; fired.remove(name) }
            return nil
        }
        return Self.immediateIntent(name)
    }
    /// 一次性定时器到点：△ 还按着、还没触发过，且确实满了 0.5 秒才给启动台。
    mutating func holdElapsed(_ name: String, at now: Double) -> PadButtonIntent? {
        guard Self.isHoldKey(name), let since = heldSince[name], !fired.contains(name),
              now.isFinite, now >= since, now - since >= Self.holdSeconds - 0.001 else { return nil }
        fired.insert(name)
        return .launchpad
    }
    mutating func release(_ name: String, at now: Double) -> PadButtonIntent? {
        guard Self.isHoldKey(name), let since = heldSince.removeValue(forKey: name) else { return nil }
        let wasFired = fired.remove(name) != nil
        guard !wasFired, now.isFinite, now >= since else { return nil }
        // 定时器晚到时，松开这一下补上长按；否则是短按。
        return now - since >= Self.holdSeconds ? .launchpad : .returnToRow
    }
    mutating func cancelAll() { heldSince.removeAll(); fired.removeAll() }
    var holding: Bool { !heldSince.isEmpty }
}

// MARK: - 游戏在前台就整个让开（R09）
enum GameFrontPolicy {
    /// 前台 App 在 Info.plist 里的分类。`unreadable` 是连 App 都读不到。
    enum Category: Equatable, Sendable { case game, other, uncategorized, unreadable }

    static func classify(bundleReadable: Bool, category: String?) -> Category {
        guard bundleReadable else { return .unreadable }
        guard let raw = category?.lowercased(), !raw.isEmpty else { return .uncategorized }
        let prefix = "public.app-category."
        guard raw.hasPrefix(prefix) else { return .other }
        let tail = raw.dropFirst(prefix.count)
        // public.app-category.games 以及 action-games、board-games ……
        return tail == "games" || tail.hasSuffix("-games") ? .game : .other
    }

    /// 为真就让开：手柄不读、不改、不震。读不到的一律当游戏。
    /// - fullScreen: 前台 App 有没有一扇铺满屏幕的窗口；nil 是读不到。
    /// - controllerInUse: GCController.current 是否有值；nil 是读不到。
    ///   GameController 不告诉我们是哪个 App 在用手柄，所以这一项只能尽力而为，宁可多让开。
    static func yields(category: Category, fullScreen: Bool?, controllerInUse: Bool?) -> Bool {
        switch category {
        case .game, .unreadable: return true
        case .other, .uncategorized:
            guard let fullScreen, let controllerInUse else { return true }
            return fullScreen && controllerInUse
        }
    }
}

// MARK: - 每台手柄单独开关，同一时间只有一台能操作（R09）
struct GamepadSeats: Sendable {
    enum Access: Equatable, Sendable { case off, controls, viewOnly }
    struct Pad: Equatable, Sendable { let id: UUID; let key: String }
    private(set) var owner: UUID?

    /// GameController 没有跨重连的持久 ID，只有厂商名和类别：这个键是尽力而为的，
    /// 两台同厂同型号的手柄会共用一个键（一起开、一起关），但同一时间仍只有一台能操作。
    static func key(vendor: String?, category: String?) -> String {
        let v = (vendor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let c = (category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(v.isEmpty ? "?" : v)|\(c.isEmpty ? "?" : c)"
    }

    /// pads 按接入先后排。原来操作的那台还在、还开着就继续由它操作，不因新接入的手柄换手。
    mutating func update(pads: [Pad], enabledKeys: Set<String>) -> [UUID: Access] {
        let enabled = pads.filter { enabledKeys.contains($0.key) }
        if let current = owner, !enabled.contains(where: { $0.id == current }) { owner = nil }
        if owner == nil { owner = enabled.first?.id }
        var result: [UUID: Access] = [:]
        for pad in pads {
            result[pad.id] = !enabledKeys.contains(pad.key) ? .off : (pad.id == owner ? .controls : .viewOnly)
        }
        return result
    }
}

// MARK: - 同一台手柄的回调同一时间只归一处
/// 桌面控制（设置里的“控制这台 Mac”）和指挥页 / 选模型页都要用手柄的 valueChangedHandler。
/// 谁先装上谁占着：后来的不抢、不覆盖，占着的一方松手后才轮到别人。
struct GamepadHandlerLedger<Key: Hashable & Sendable>: Sendable {
    enum Holder: Equatable, Sendable { case desktop, page }
    private var holders: [Key: Holder] = [:]

    func holder(of key: Key) -> Holder? { holders[key] }

    /// 空着或本来就是自己占着才给；别人占着返回 false，什么都不改。
    mutating func claim(_ key: Key, by holder: Holder) -> Bool {
        if let current = holders[key] { return current == holder }
        holders[key] = holder
        return true
    }

    /// 只有占着的人能放。
    mutating func release(_ key: Key, by holder: Holder) {
        if holders[key] == holder { holders[key] = nil }
    }

    func anyHeld(by holder: Holder) -> Bool { holders.values.contains(holder) }
}
