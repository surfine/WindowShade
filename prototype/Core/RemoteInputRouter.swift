import Foundation

/// 遥控器按键进已有的状态机。没有焦点格子、没有麦克风、没有指挥页面时，动作不算已经做完。
struct RemoteInputRouter: Sendable {
    private var buttons = SiriRemoteButtons()
    private var mode = RemoteMode()
    private var focus = FocusNavigator()
    private var lastFocusID: String?

    struct Outcome: Equatable, Sendable {
        var effects: [RemoteMode.Effect]
        var focusMove: FocusNavigator.Result?
        /// 只有真的把焦点交到调用方给的格子上，才是 true。
        var focusDelivered: Bool
    }

    mutating func setEnabled(_ enabled: Bool, at now: WS2.Instant) -> Outcome {
        if !enabled {
            _ = buttons.cancelAll(at: now)
        }
        let effects = mode.setEnabled(enabled)
        if !enabled { lastFocusID = nil; focus.clear() }
        return Outcome(effects: effects, focusMove: nil, focusDelivered: false)
    }

    mutating func report(page: UInt32, usage: UInt32, value: Int, at now: WS2.Instant,
                         focusItems: [FocusNavigator.Item]?) -> Outcome {
        guard mode.enabled else { return Outcome(effects: [], focusMove: nil, focusDelivered: false) }
        let events = buttons.report(page: page, usage: usage, value: value, at: now)
        var effects: [RemoteMode.Effect] = []
        var focusMove: FocusNavigator.Result?
        var delivered = false
        for event in events {
            let produced = mode.handle(event)
            effects.append(contentsOf: produced)
            for effect in produced {
                guard case .action(let action) = effect, let direction = Self.direction(action) else { continue }
                guard let focusItems, !focusItems.isEmpty else { continue }
                let display = focusItems[0].display
                let result = focus.move(from: lastFocusID, direction: direction, display: display, items: focusItems)
                focusMove = result
                if case .focused(let id) = result {
                    lastFocusID = id
                    delivered = true
                }
            }
        }
        return Outcome(effects: effects, focusMove: focusMove, focusDelivered: delivered)
    }

    private static func direction(_ action: WS2.Action) -> FocusNavigator.Direction? {
        switch action {
        case .focusUp: return .up
        case .focusDown: return .down
        case .focusLeft: return .left
        case .focusRight: return .right
        default: return nil
        }
    }
}
