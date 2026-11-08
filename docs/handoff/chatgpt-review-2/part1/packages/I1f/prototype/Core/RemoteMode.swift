import Foundation

/// 所有来源共用的模式路由。长按播放键只切换模式，最后的 up 不再发媒体或提交。
struct RemoteMode: Sendable {
    enum Mode: String, Equatable, Sendable { case remote, conductor }
    enum Effect: Equatable, Sendable {
        case action(WS2.Action)
        case forward(WS2.ButtonEvent)
        case cancelConductorInput
        case modeChanged(Mode)
        case dictationRequested
    }
    private struct Press: Sendable { let id: UInt64; var consumed = false }
    private var presses: [WS2.Button: Press] = [:]
    private var time = WS2.TimeGate()
    private var lastPressID: UInt64 = 0
    private(set) var enabled = false
    private(set) var mode: Mode = .remote

    mutating func setEnabled(_ value: Bool) -> [Effect] {
        guard enabled != value else { return [] }
        enabled = value; presses.removeAll(keepingCapacity: true)
        if !value { mode = .remote; return [.cancelConductorInput, .modeChanged(.remote)] }
        return []
    }
    mutating func handle(_ event: WS2.ButtonEvent) -> [Effect] {
        guard enabled, event.at >= event.beganAt, time.accept(event.at) else { return [] }
        if event.phase == .clickOnly {
            guard event.pressID > lastPressID else { return [] }
            lastPressID = event.pressID
            return mode == .conductor ? [.forward(event)] : short(event.button)
        }
        if event.phase == .down {
            guard presses[event.button] == nil, event.pressID > lastPressID else { return [] }
            lastPressID = event.pressID; presses[event.button] = Press(id: event.pressID)
            if mode == .conductor { return [.forward(event)] }
            switch event.button {
            case .up: presses[event.button]?.consumed = true; return [.action(.focusUp)]
            case .down: presses[event.button]?.consumed = true; return [.action(.focusDown)]
            case .left: presses[event.button]?.consumed = true; return [.action(.focusLeft)]
            case .right: presses[event.button]?.consumed = true; return [.action(.focusRight)]
            default: return []
            }
        }
        guard var p = presses[event.button], p.id == event.pressID else { return [] }
        if event.phase == .cancel {
            presses.removeValue(forKey: event.button)
            return mode == .conductor && !p.consumed ? [.forward(event)] : []
        }
        if event.button == .playPause, event.phase == .heldOneSecond, !p.consumed {
            p.consumed = true; presses[event.button] = p
            mode = mode == .remote ? .conductor : .remote
            // 其它仍按住的键也不把尾端 up 带入新模式。
            for key in presses.keys { presses[key]?.consumed = true }
            return [.cancelConductorInput, .modeChanged(mode), .action(mode == .conductor ? .enterConductor : .leaveConductor)]
        }
        if event.phase == .up {
            presses.removeValue(forKey: event.button)
            guard !p.consumed else { return [] }
            return mode == .conductor ? [.forward(event)] : short(event.button)
        }
        guard !p.consumed else { return [] }
        if mode == .conductor { return [.forward(event)] }
        if event.phase == .heldHalfSecond && event.button == .tv {
            p.consumed = true; presses[event.button] = p; return [.action(.notchShelf)]
        }
        if event.phase == .heldHalfSecond && event.button == .side {
            p.consumed = true; presses[event.button] = p; return [.dictationRequested]
        }
        return []
    }
    private func short(_ button: WS2.Button) -> [Effect] {
        switch button {
        case .up: return [.action(.focusUp)]
        case .down: return [.action(.focusDown)]
        case .left: return [.action(.focusLeft)]
        case .right: return [.action(.focusRight)]
        case .select: return [.action(.activateFocused)]
        case .back: return [.action(.back)]
        case .tv: return [.action(.launchpad)]
        case .playPause: return [.action(.mediaPlayPause)]
        case .mute: return [.action(.mediaMute)]
        case .volumeUp: return [.action(.volumeUp)]
        case .volumeDown: return [.action(.volumeDown)]
        case .power: return [.action(.displaySleepRequest)]
        case .side: return [] // 未证实按住录音前，短按不盲发系统听写快捷键。
        }
    }
}
