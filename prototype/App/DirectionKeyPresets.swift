// 方向键换成字母（Swish 的 WASD / IJKL / HJKL，Dvorak 上就是 ,AOE 那一簇）：
// 变小一级、变大一级、左半屏、右半屏这四个方向一下换成 ⌃⌥ 加字母，选“方向键”换回原来的。
// 别的动作已经在用的组合，它们先来的算数：那个方向不换，并说出是谁占着；被别的 App 占着、注册不上的，也退回原来的。
// 四个方向是自己录的时点“方向键”，换成 ⌃⌘ 方向键并记下自己录的，再点一次换回来。
// 只在设置里点一下时做一次，不常驻、不监听。算法见 Core/DirectionKeys.swift。

import Cocoa

enum DirectionKeyPresets {
    /// 四个方向对应的动作。
    static let shortcuts: [DirectionSlot: GlobalShortcut] = [
        .up: .stepSmaller, .down: .stepLarger, .left: .leftHalf, .right: .rightHalf,
    ]

    static func shortcut(_ slot: DirectionSlot) -> GlobalShortcut {
        shortcuts[slot] ?? .leftHalf
    }

    static func hotKey(_ combo: KeyCombo) -> GlobalShortcutSettings.HotKey {
        GlobalShortcutSettings.HotKey(keyCode: combo.keyCode, modifiers: combo.carbonModifiers)
    }

    static func combo(_ hotKey: GlobalShortcutSettings.HotKey) -> KeyCombo {
        KeyCombo(keyCode: hotKey.keyCode, carbonModifiers: hotKey.modifiers)
    }

    /// 四个方向现在用的组合。
    static func current() -> DirectionBindings {
        var out: DirectionBindings = [:]
        for slot in DirectionSlot.allCases {
            if let hotKey = GlobalShortcutSettings.hotKey(for: shortcut(slot)) { out[slot] = combo(hotKey) }
        }
        return out
    }

    /// 现在正好是哪一套（设置页上选中哪一格）。
    static var currentSet: DirectionKeySet? { DirectionKeySet.matching(current()) }

    static var record: DirectionKeyRecord? {
        get { DirectionKeyRecord(plist: GlobalShortcutSettings.defaults.object(forKey: GlobalShortcutSettings.directionKeysRecordKey)) }
        set {
            if let newValue {
                GlobalShortcutSettings.defaults.set(newValue.plist, forKey: GlobalShortcutSettings.directionKeysRecordKey)
            } else {
                GlobalShortcutSettings.defaults.removeObject(forKey: GlobalShortcutSettings.directionKeysRecordKey)
            }
        }
    }

    /// 设置页和提示里这一套叫什么：按当前键盘布局显示键名（Dvorak 上 WASD 那一簇显示 ,AOE）。
    static func label(for set: DirectionKeySet) -> String {
        guard set != .arrows else { return "方向键" }
        return set.labelOrder.map {
            WindowBrowserSettings.displayName(for: GlobalShortcutSettings.HotKey(keyCode: set.keyCode($0), modifiers: 0))
        }.joined()
    }

    struct Outcome {
        /// 换成了哪一套；换回原来的是 nil。
        let set: DirectionKeySet?
        let restored: Bool
        let changed: [DirectionSlot]
        /// 没换的方向：组合、为什么（“已用于左三分之一”“被其他应用占用”）。
        let skipped: [(slot: DirectionSlot, combo: KeyCombo, reason: String)]
        /// 点“方向键”盖掉了原来的组合（多半是自己录的）：再点一次“方向键”能换回来。
        let canSwitchBack: Bool
    }

    /// 换成某一套。选“方向键”且换过字母时，换回换之前的样子。
    /// `register`：写完设置后重新注册全局快捷键，返回注册不上的热键编号。
    static func choose(_ set: DirectionKeySet, register: () -> Set<UInt32>) -> Outcome {
        let before = current()
        let saved = record
        let restoring = set == .arrows && saved?.canRestore(before) == true
        let desired = restoring ? (saved?.restoring(before) ?? before) : set.bindings

        var holders: [KeyCombo: String] = [:]
        let targets = Set(shortcuts.values)
        for other in GlobalShortcut.allCases where !targets.contains(other) {
            if let hotKey = GlobalShortcutSettings.hotKey(for: other) { holders[combo(hotKey)] = other.title }
        }
        if GlobalShortcutSettings.numberedExpandEnabled {
            for keyCode in GlobalShortcutSettings.numberedKeyCodes {
                holders[KeyCombo(keyCode: keyCode, carbonModifiers: GlobalShortcutSettings.numberedModifiers)] = "按编号展开已收起的窗口"
            }
        }
        var titles: [DirectionSlot: String] = [:]
        for slot in DirectionSlot.allCases { titles[slot] = shortcut(slot).title }

        let plan = DirectionKeys.plan(desired: desired, current: before, holders: holders, titles: titles)
        for slot in plan.changed {
            GlobalShortcutSettings.setHotKey(plan.result[slot].map(hotKey), for: shortcut(slot))
        }
        var skipped = plan.clashes.map { (slot: $0.slot, combo: $0.combo, reason: "已用于“\($0.holder)”") }
        var changed = plan.changed
        // 被别的 App 占着、注册不上的方向：退回原来的组合，不留一个按了没反应的快捷键。
        // 原来的组合已经换给了另一个方向（IJKL ⇄ HJKL 互换 J K），那个方向也跟着不换，不把谁关掉。
        let failed = register()
        let refused = Set(plan.changed.filter { failed.contains(shortcut($0).hotKeyID) && plan.result[$0] != nil })
        if !refused.isEmpty {
            let fallback = DirectionKeys.fallBack(plan, current: before, refused: refused, titles: titles)
            for slot in DirectionSlot.allCases where fallback.returned.contains(slot) {
                GlobalShortcutSettings.setHotKey(fallback.result[slot].map(hotKey), for: shortcut(slot))
            }
            for slot in DirectionSlot.allCases where refused.contains(slot) {
                if let combo = plan.result[slot] { skipped.append((slot, combo, "被其他应用占用")) }
            }
            skipped += fallback.clashes.map { (slot: $0.slot, combo: $0.combo, reason: "已用于“\($0.holder)”") }
            changed.subtract(fallback.returned)
            _ = register()
        }
        let after = current()
        record = DirectionKeyRecord.afterChoosing(set, restoring: restoring, saved: saved, before: before, after: after)
        let order = DirectionSlot.allCases
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return Outcome(set: restoring ? nil : set, restored: restoring,
                       changed: order.filter { changed.contains($0) },
                       skipped: skipped.sorted { (rank[$0.slot] ?? 0) < (rank[$1.slot] ?? 0) },
                       canSwitchBack: set == .arrows && !restoring && after != before)
    }

    /// 刘海上说的话：标题说换成了什么，下面一行说每个方向现在按什么、哪几个没换。
    static func message(for outcome: Outcome) -> (title: String, detail: String) {
        func name(_ combo: KeyCombo) -> String { WindowBrowserSettings.displayName(for: hotKey(combo)) }
        let now = current()
        // 中文和字母之间空一格：“换成了 WASD”“换回了方向键”。
        let setName = outcome.set.map { $0 == .arrows ? label(for: $0) : " \(label(for: $0))" } ?? ""
        let title: String
        if outcome.restored {
            title = "换回了原来的快捷键"
        } else if outcome.changed.isEmpty {
            let already = outcome.skipped.isEmpty && outcome.set != nil && DirectionKeySet.matching(now) == outcome.set
            title = already ? "已经是\(setName)" : "快捷键没有换"
        } else if outcome.set == .arrows {
            title = "换回了方向键"
        } else {
            title = "换成了\(setName)"
        }
        let changed = DirectionSlot.allCases.compactMap { slot -> String? in
            guard outcome.changed.contains(slot), let combo = now[slot] else { return nil }
            return "\(name(combo)) \(shortcut(slot).title)"
        }
        let skipped = outcome.skipped.map { "\(name($0.combo)) \($0.reason)，\(shortcut($0.slot).title)没换" }
        let back = outcome.canSwitchBack ? "再点一次“方向键”换回原来的" : ""
        let detail = [changed.joined(separator: " · "), skipped.joined(separator: "；"), back]
            .filter { !$0.isEmpty }.joined(separator: "；")
        return (title, detail)
    }
}

extension AppDelegate {
    /// 设置里“方向键换成字母”的分段按钮。
    @MainActor @objc func prefSelectDirectionKeys(_ sender: NSSegmentedControl) {
        let sets = DirectionKeySet.allCases
        guard sets.indices.contains(sender.selectedSegment) else { return }
        let set = sets[sender.selectedSegment]
        let outcome = DirectionKeyPresets.choose(set) {
            registerGlobalShortcuts()
            return unavailableHotKeyIDs
        }
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
        wlog("direction-keys: \(set.rawValue) restored=\(outcome.restored) changed=\(outcome.changed.map(\.rawValue)) skipped=\(outcome.skipped.map { "\($0.slot.rawValue):\($0.reason)" })")
        let text = DirectionKeyPresets.message(for: outcome)
        notch.announce(text.title, detail: text.detail, tone: outcome.skipped.isEmpty ? .done : .info)
    }
}
