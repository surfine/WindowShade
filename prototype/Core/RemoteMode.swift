import Foundation

/// 所有来源共用的遥控器键位（四层键位：第 0、1 层归这里，第 2、3 层归 ConductorSession）。
///
/// 没有“模式”可切：宿主按眼前在哪一层调用 `setLayer`，按键就按那一层翻译。
/// - 第 0 层：刘海收着。第 1 层：刘海展开，焦点在那一排上。
/// - 第 2 层以上（走进一个会话之后）：按键原样交给 ConductorSession。“走进会话”由宿主负责，这里不判断也不切换。
///
/// 每个短按都是松开那一下才算；按住的动作（电视键 ≥0.5 s、侧边键 ≥0.5 s）在到点时发一次，之后的松开不再补发短按。
struct RemoteMode: Sendable {
    enum Layer: Equatable, Sendable {
        /// 第 0 层：刘海收着。
        case collapsed
        /// 第 1 层：刘海展开，焦点在会话那一排。
        case row
        /// 第 2 层以上：在一个会话里，按键原样交给 ConductorSession。
        case session
    }
    enum Effect: Equatable, Sendable {
        case action(WS2.Action)
        case forward(WS2.ButtonEvent)
        case cancelConductorInput
        /// 电视键点一下：第 0 层展开那一排，第 1 层回到最前面。
        case returnToRow
        /// 电视键按住 ≥0.5 s。
        case launchpad
        /// 电源：全部收回第 0 层，会话照跑，Mac 不睡。
        case wrapUp
        /// 静音键：WindowShade 自己的提示音开关（第 0 层提示“提示音已关”或“提示音已开”），不动系统静音。
        case togglePromptSound
        /// 第 0 层往下：展开那一排。
        case expandRow
        /// 侧边键按住，且焦点在会话格上：走进这个会话并开始听。
        case enterSessionAndListen
        /// 音量键，每层一样。
        case volume(Int)
    }
    private struct Press: Sendable { let id: UInt64; var consumed = false }
    private var presses: [WS2.Button: Press] = [:]
    private var time = WS2.TimeGate()
    private var lastPressID: UInt64 = 0
    private(set) var enabled = false
    private(set) var layer: Layer = .collapsed
    /// 焦点是否落在会话格上（宿主告知）。侧边键按住只在这时才走进会话。
    private(set) var focusOnSession = false

    mutating func setEnabled(_ value: Bool) -> [Effect] {
        guard enabled != value else { return [] }
        enabled = value; presses.removeAll(keepingCapacity: true)
        if !value { layer = .collapsed; focusOnSession = false; return [.cancelConductorInput] }
        return []
    }
    /// 宿主换层。离开会话层时撤掉交给 ConductorSession 的输入；还按着的键不把尾端 up 带到新一层。
    mutating func setLayer(_ value: Layer) -> [Effect] {
        guard layer != value else { return [] }
        let leavingSession = layer == .session
        layer = value; presses.removeAll(keepingCapacity: true)
        if value != .row { focusOnSession = false }
        return leavingSession ? [.cancelConductorInput] : []
    }
    mutating func setFocusOnSession(_ value: Bool) { focusOnSession = layer == .row && value }

    mutating func handle(_ event: WS2.ButtonEvent) -> [Effect] {
        guard enabled, event.at >= event.beganAt, time.accept(event.at) else { return [] }
        if event.phase == .clickOnly {
            guard event.pressID > lastPressID else { return [] }
            lastPressID = event.pressID
            return layer == .session ? [.forward(event)] : short(event.button)
        }
        if event.phase == .down {
            guard presses[event.button] == nil, event.pressID > lastPressID else { return [] }
            lastPressID = event.pressID; presses[event.button] = Press(id: event.pressID)
            return layer == .session ? [.forward(event)] : []
        }
        guard var p = presses[event.button], p.id == event.pressID else { return [] }
        if event.phase == .cancel {
            presses.removeValue(forKey: event.button)
            return layer == .session && !p.consumed ? [.forward(event)] : []
        }
        if event.phase == .up {
            presses.removeValue(forKey: event.button)
            guard !p.consumed else { return [] }
            return layer == .session ? [.forward(event)] : short(event.button)
        }
        guard !p.consumed else { return [] }
        if layer == .session { return [.forward(event)] }
        guard event.phase == .heldHalfSecond else { return [] }
        switch event.button {
        case .tv:
            p.consumed = true; presses[event.button] = p; return [.launchpad]
        case .side:
            // 按住只在焦点落在会话格上才算；别处忽略，松开也不补短按。
            p.consumed = true; presses[event.button] = p
            return focusOnSession ? [.enterSessionAndListen] : []
        default:
            return []
        }
    }
    private func short(_ button: WS2.Button) -> [Effect] {
        switch button {
        case .up: return [.action(.focusUp)]
        case .down: return layer == .collapsed ? [.expandRow] : [.action(.focusDown)]
        case .left: return [.action(.focusLeft)]
        case .right: return [.action(.focusRight)]
        case .select: return [.action(.activateFocused)]
        case .back: return [.action(.back)] // 退一层
        case .tv: return [.returnToRow]
        case .playPause: return [.action(.mediaPlayPause)] // 开始或停下眼前这件事
        case .mute: return [.togglePromptSound]
        case .volumeUp: return [.volume(1)]
        case .volumeDown: return [.volume(-1)]
        case .power: return [.wrapUp]
        case .side: return [] // 短按不发系统听写快捷键；按住才走进会话。
        }
    }
}
