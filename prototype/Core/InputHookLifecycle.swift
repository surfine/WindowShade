import Foundation

/// 钩子的装、拆和回调次数。关着或被系统停掉时，回调直接拒绝，次数不增加。
struct InputHookLifecycle: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case absent
        case installed
        case stoppedBySystem
    }

    private(set) var phase: Phase = .absent
    private(set) var installs = 0
    private(set) var removals = 0
    private(set) var callbacks = 0

    /// 用户把开关拨到这个位置。拨开只会从「没装」变成「装上」；停在「被系统停掉」时不会再装。
    mutating func userSet(enabled: Bool) {
        if !enabled {
            if phase == .installed { removals += 1 }
            phase = .absent
            return
        }
        if phase == .absent {
            phase = .installed
            installs += 1
        }
    }

    /// 系统停掉已经装上的钩子。拆掉，留在「被系统停掉」，同一次不会再装。
    mutating func systemDisabled() {
        guard phase == .installed else { return }
        phase = .stoppedBySystem
        removals += 1
    }

    /// 端口没创建出来。算一次没有留下的安装，并停住，避免立刻重试。
    mutating func openFailed() {
        guard phase == .installed else { return }
        phase = .stoppedBySystem
        removals += 1
    }

    /// 只有「装上」才算一次回调。
    mutating func receive() -> Bool {
        guard phase == .installed else { return false }
        callbacks += 1
        return true
    }
}

enum HookAction: Equatable, Sendable {
    case open
    case close
    case keep
}

/// 把开关翻译成「打开端口 / 关掉端口 / 不动」。端口本身不在这里创建。
struct HookDriver: Equatable, Sendable {
    private(set) var life = InputHookLifecycle()

    mutating func plan(wanted: Bool, isOpen: Bool) -> HookAction {
        life.userSet(enabled: wanted)
        switch life.phase {
        case .installed:
            return isOpen ? .keep : .open
        case .absent, .stoppedBySystem:
            return isOpen ? .close : .keep
        }
    }

    mutating func openFailed() { life.openFailed() }

    mutating func systemDisabled(isOpen: Bool) -> HookAction {
        life.systemDisabled()
        return isOpen ? .close : .keep
    }

    mutating func onEvent() -> Bool { life.receive() }

    var phase: InputHookLifecycle.Phase { life.phase }
    var installs: Int { life.installs }
    var removals: Int { life.removals }
    var callbacks: Int { life.callbacks }
}
