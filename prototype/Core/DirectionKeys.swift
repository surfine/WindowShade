// 方向键换成字母：让用惯 Swish 键位的人不用重新记。
// Swish 的方向快捷键有几套：方向键、WASD、IJKL、Vim 的 HJKL，还有 Dvorak 的 ,AOE。
// 系统热键认的是键在键盘上的位置，不管当前用哪种键盘布局；Dvorak 布局下 W A S D 那几个位置
// 打出来的正是 , A O E，所以 Swish 的 Dvorak 那套和这里的 WASD 是同一组键——设置页按当前布局显示键名，
// 用 Dvorak 的人看到的就是 ,AOE（AZERTY 上是 ZQSD）。
// 这里只管账：四个方向各用哪个组合、撞上别的动作时怎么办、怎么换回来。纯逻辑，不读盘、不注册热键。

import Foundation

/// 排布当前窗口的四个方向（往上变小一级、往下变大一级、左半屏、右半屏）。
enum DirectionSlot: String, CaseIterable {
    case up, down, left, right
}

/// 四个方向用的组合；没有的方向就是关着。
typealias DirectionBindings = [DirectionSlot: KeyCombo]

enum DirectionKeySet: String, CaseIterable {
    /// ⌃⌘ 加方向键：一直以来的默认。
    case arrows
    /// 左手那一簇（Dvorak 上是 ,AOE）。
    case wasd
    /// 右手那一簇。
    case ijkl
    /// Vim 的四个键。
    case hjkl

    // Carbon 修饰键位，照着写下来，不 import Carbon。
    static let controlCommand: UInt32 = 0x1000 | 0x0100
    static let controlOption: UInt32 = 0x1000 | 0x0800

    /// 方向键沿用 ⌃⌘；字母用 ⌃⌥：⌃⌘W、⌃⌘S、⌃⌘L、⌃⌘D 不是系统在用（关窗、查词），就是已经给了侧拉、启动台。
    var modifiers: UInt32 {
        self == .arrows ? Self.controlCommand : Self.controlOption
    }

    /// 虚拟键码（键在键盘上的位置）。
    func keyCode(_ slot: DirectionSlot) -> UInt32 {
        switch (self, slot) {
        case (.arrows, .up): return 126
        case (.arrows, .down): return 125
        case (.arrows, .left): return 123
        case (.arrows, .right): return 124
        case (.wasd, .up): return 13     // W
        case (.wasd, .down): return 1    // S
        case (.wasd, .left): return 0    // A
        case (.wasd, .right): return 2   // D
        case (.ijkl, .up): return 34     // I
        case (.ijkl, .down): return 40   // K
        case (.ijkl, .left): return 38   // J
        case (.ijkl, .right): return 37  // L
        case (.hjkl, .up): return 40     // K
        case (.hjkl, .down): return 38   // J
        case (.hjkl, .left): return 4    // H
        case (.hjkl, .right): return 37  // L
        }
    }

    func combo(_ slot: DirectionSlot) -> KeyCombo {
        KeyCombo(keyCode: keyCode(slot), carbonModifiers: modifiers)
    }

    var bindings: DirectionBindings {
        var out: DirectionBindings = [:]
        for slot in DirectionSlot.allCases { out[slot] = combo(slot) }
        return out
    }

    /// 名字里几个键的先后：WASD、IJKL 是上左下右，HJKL 是左下上右。
    var labelOrder: [DirectionSlot] {
        self == .hjkl ? [.left, .down, .up, .right] : [.up, .left, .down, .right]
    }

    /// 四个方向正好是哪一套；对不上（自己录过、只换了一部分）返回 nil。
    static func matching(_ bindings: DirectionBindings) -> DirectionKeySet? {
        allCases.first { $0.bindings == bindings }
    }
}

/// 换一次要怎么改：最后四个方向各是什么、实际改了哪几个、哪几个因为撞上别的动作没换。
struct DirectionKeyPlan: Equatable {
    struct Clash: Equatable {
        let slot: DirectionSlot
        let combo: KeyCombo
        /// 占着这个组合的动作（用户看得懂的名字）。
        let holder: String
    }

    var result: DirectionBindings
    var changed: Set<DirectionSlot>
    var clashes: [Clash]
}

enum DirectionKeys {
    /// 想换成 `desired`（缺的方向表示关掉）。别的动作已经在用的组合，它们先来的算数：这个方向不换，记下是谁占着。
    /// 没换的方向还占着自己原来的组合，别的方向也不能换过去（一轮一轮查，直到不再有新的不换）。
    /// `holders`：本应用别的动作（不含这四个方向）现在用着的组合 → 名字。`titles`：四个方向自己的名字。
    static func plan(desired: DirectionBindings, current: DirectionBindings,
                     holders: [KeyCombo: String], titles: [DirectionSlot: String]) -> DirectionKeyPlan {
        var kept: [DirectionSlot: DirectionKeyPlan.Clash] = [:]
        while true {
            var taken = holders
            for slot in DirectionSlot.allCases where kept[slot] != nil {
                if let combo = current[slot] { taken[combo] = titles[slot] ?? slot.rawValue }
            }
            var newlyKept = false
            for slot in DirectionSlot.allCases where kept[slot] == nil {
                guard let combo = desired[slot] else { continue }
                if let holder = taken[combo] {
                    kept[slot] = .init(slot: slot, combo: combo, holder: holder)
                    newlyKept = true
                } else {
                    // 同一轮里前面的方向先占上，后面想要同一个组合的不换。
                    taken[combo] = titles[slot] ?? slot.rawValue
                }
            }
            if !newlyKept { break }
        }
        var result = current
        var changed: Set<DirectionSlot> = []
        for slot in DirectionSlot.allCases where kept[slot] == nil {
            guard desired[slot] != current[slot] else { continue }
            result[slot] = desired[slot]
            changed.insert(slot)
        }
        let clashes = DirectionSlot.allCases.compactMap { kept[$0] }
        return DirectionKeyPlan(result: result, changed: changed, clashes: clashes)
    }

    /// 照 `plan` 换完，`refused` 这几个方向注册不上（被别的 App 占着）：它们退回原来的组合。
    /// 原来的组合已经换给了另一个方向（IJKL ⇄ HJKL 互换 J K），那个方向也退回它原来的，一个带一个，
    /// 直到没有两个方向用同一个组合——宁可少换几个，也不把哪个方向关掉。
    /// 跟着退回的方向记成撞车：想换的组合留给了谁（和 `plan` 里“没换的方向还占着自己原来的组合”是同一个说法）。
    static func fallBack(_ plan: DirectionKeyPlan, current: DirectionBindings, refused: Set<DirectionSlot>,
                         titles: [DirectionSlot: String]) -> DirectionKeyFallback {
        var pending = DirectionSlot.allCases.filter { refused.contains($0) && plan.changed.contains($0) }
        var returned = Set(pending)
        var kept: [DirectionSlot: DirectionKeyPlan.Clash] = [:]
        while !pending.isEmpty {
            let slot = pending.removeFirst()
            guard let original = current[slot] else { continue }
            for other in DirectionSlot.allCases
            where !returned.contains(other) && plan.changed.contains(other) && plan.result[other] == original {
                returned.insert(other)
                pending.append(other)
                kept[other] = .init(slot: other, combo: original, holder: titles[slot] ?? slot.rawValue)
            }
        }
        var result = plan.result
        for slot in returned { result[slot] = current[slot] }
        return DirectionKeyFallback(result: result, returned: returned,
                                    clashes: DirectionSlot.allCases.compactMap { kept[$0] })
    }
}

/// 注册不上时退回之后：最后四个方向各是什么、退回了哪几个（含注册不上的）、跟着退回的方向是被谁拦下的。
struct DirectionKeyFallback: Equatable {
    var result: DirectionBindings
    var returned: Set<DirectionSlot>
    var clashes: [DirectionKeyPlan.Clash]
}

/// 换回来要用的账：第一次换之前四个方向是什么，最近一次换完是什么。
struct DirectionKeyRecord: Equatable {
    var previous: DirectionBindings
    var applied: DirectionBindings

    /// 换了一次之后记账：第一次换时记下原来的；接着换别的一套，原来的那份不动，只更新“换完是什么”——
    /// 中间自己又录过的方向，自己录的那个才是“原来的”。
    static func updated(_ record: DirectionKeyRecord?, before: DirectionBindings,
                        after: DirectionBindings) -> DirectionKeyRecord {
        DirectionKeyRecord(previous: record?.restoring(before) ?? before, applied: after)
    }

    /// 换回原来的：还是换完那个样子的方向回到原来的；换完后自己又录过的方向，听自己的。
    func restoring(_ current: DirectionBindings) -> DirectionBindings {
        var out = current
        for slot in DirectionSlot.allCases where current[slot] == applied[slot] {
            out[slot] = previous[slot]
        }
        return out
    }

    /// 有没有能换回来的方向。
    func canRestore(_ current: DirectionBindings) -> Bool {
        restoring(current) != current
    }

    /// 点了一套之后账怎么记（nil 是清账）：换回了原来的就清账——有方向注册不上、还停在换完的样子，账留着下次再换；
    /// 点“方向键”时本来就是方向键，清账；真的改了什么就记一笔——点“方向键”盖掉了自己录的组合也记，
    /// 再点一次“方向键”能换回来；什么都没变，账不动。
    static func afterChoosing(_ set: DirectionKeySet, restoring: Bool, saved: DirectionKeyRecord?,
                              before: DirectionBindings, after: DirectionBindings) -> DirectionKeyRecord? {
        if restoring { return saved.flatMap { $0.canRestore(after) ? $0 : nil } }
        if set == .arrows && after == before { return nil }
        return after == before ? saved : updated(saved, before: before, after: after)
    }

    // 存进偏好设置的样子：["previous": ["up": [keyCode, modifiers]], "applied": …]，缺的方向就是关着。
    var plist: [String: [String: [Int]]] {
        func encode(_ bindings: DirectionBindings) -> [String: [Int]] {
            var out: [String: [Int]] = [:]
            for (slot, combo) in bindings { out[slot.rawValue] = [Int(combo.keyCode), Int(combo.carbonModifiers)] }
            return out
        }
        return ["previous": encode(previous), "applied": encode(applied)]
    }

    init(previous: DirectionBindings, applied: DirectionBindings) {
        self.previous = previous
        self.applied = applied
    }

    /// 读回来；不是这个样子（坏了、别的版本写的）返回 nil，当作没换过。
    init?(plist: Any?) {
        guard let root = plist as? [String: Any],
              let previous = root["previous"] as? [String: Any],
              let applied = root["applied"] as? [String: Any] else { return nil }
        func decode(_ raw: [String: Any]) -> DirectionBindings? {
            var out: DirectionBindings = [:]
            for (key, value) in raw {
                guard let slot = DirectionSlot(rawValue: key), let pair = value as? [Any], pair.count == 2,
                      let code = (pair[0] as? NSNumber)?.intValue ?? pair[0] as? Int,
                      let modifiers = (pair[1] as? NSNumber)?.intValue ?? pair[1] as? Int,
                      code >= 0, modifiers >= 0 else { return nil }
                out[slot] = KeyCombo(keyCode: UInt32(code), carbonModifiers: UInt32(modifiers))
            }
            return out
        }
        guard let before = decode(previous), let after = decode(applied) else { return nil }
        self.previous = before
        self.applied = after
    }
}
