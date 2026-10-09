// 刘海那一排的焦点导航（M07）：键盘、遥控器（M09）、手柄（R05）共用的一个出口。
//
// 这里只有纯逻辑：谁亮着、往哪挪、读屏念什么、亮着的格子画成什么样。不碰 AppKit、不读任何东西，
// 窗口、按键、弹簧都在 Notch.swift 里接上（NotchPanel / NotchController 的“键盘焦点”一节）。
// 四向移动交给 Core/FocusNavigator（到头不绕回）；一句话的截断交给 Core/NotchSentence。
//
// 规矩：
// - 焦点只在指针不在刘海里时出现；指针一进来就隐藏，交给指针；指针出去时那一排本来就收起了，焦点随之结束。
// - 默认落点：有“等你”的会话格就落在它上面，否则落在最近收进去的那一扇，再否则第一格。
// - 到头不动：朝那个方向轻轻顶一下再弹回，焦点不换。

import Foundation

struct NotchFocusController: Sendable {
    /// 一格。`tucked` 的格子由宿主按“最近收进去的在前”排好（NotchController.tiles() 就是这个顺序）。
    /// 窗口格在前、竖线右边正在进行的格在后（M11）：同一页、同一套索引，焦点可以跨过竖线。
    struct Cell: Equatable, Sendable {
        let id: UInt32
        let title: String
        var waiting = false
        var tucked = false
        /// 竖线右边正在进行的格（正在播放的、编程会话）。
        var ongoing = false
        /// 编程会话格：焦点落在它上面时要告诉遥控器（RemoteLayerHost.Focus.session）。
        var session = false
        /// 读屏念的整句（“项目，在等你”）。有它就不再按窗口标题截断。
        var spoken: String? = nil
    }

    typealias Direction = FocusNavigator.Direction

    /// 宿主要做的事。
    enum Effect: Equatable, Sendable {
        case none
        /// 开始：宿主确保那一排展开、面板可以接键盘；`announcement` 交给读屏。
        case begin(announcement: String)
        /// 焦点挪到了另一格。
        case moved(id: UInt32, announcement: String)
        /// 到头了：焦点不变，朝 `direction` 顶一下再弹回；`announcement` 重念当前这一格。
        case bump(direction: Direction, announcement: String)
        /// 打开亮着的那一格：走和指针点击同一条路（放回、去、还原，沿用 flyOut 弹簧）。
        case activate(id: UInt32)
        /// 收起这一排、交还键盘。
        case end
    }

    private(set) var cells: [Cell] = []
    private(set) var focusedID: UInt32?
    private(set) var isActive = false
    private(set) var pointerInside = false
    private var navigator = FocusNavigator()

    /// 这块屏上唯一一排；FocusNavigator 要一个屏幕标识，这里固定一个。
    private static let display = WS2.DisplayID(value: 0)

    // MARK: 样式（亮着的那一格）

    enum Style {
        static let scale = 1.1
        /// 往上抬多少点。
        static let lift = 4.0
        static let strokeWidth = 2.5
        /// 系统开了“增强对比度”时。
        static let strokeWidthIncreasedContrast = 4.5
        /// 到头时朝那个方向顶多少点。
        static let bump = 6.0

        static func stroke(increasedContrast: Bool) -> Double {
            increasedContrast ? strokeWidthIncreasedContrast : strokeWidth
        }

        /// 亮着的格子相对原位的变换：绕格子中心放大，再往上抬 `lift`（y 向上）。
        /// `pivot` 是图层的锚点换算到格子里的位置（NSView 的图层锚点在左下角，不是中心），所以平移要把它补回来。
        /// 结果按 “p' = pivot + translation + scale·(p − pivot)” 理解。
        static func transform(width: Double, height: Double, pivotX: Double, pivotY: Double,
                              focused: Bool, bump direction: Direction? = nil)
            -> (scale: Double, translationX: Double, translationY: Double) {
            guard focused else { return (1, 0, 0) }
            let s = scale
            var tx = (width / 2 - pivotX) * (1 - s)
            var ty = (height / 2 - pivotY) * (1 - s) + lift
            switch direction {
            case .up?: ty += bump
            case .down?: ty -= bump
            case .left?: tx -= bump
            case .right?: tx += bump
            case nil: break
            }
            return (s, tx, ty)
        }
    }

    // MARK: 读屏

    static func openAnnouncement(count: Int) -> String { "刘海那一排，\(count) 项" }

    /// “标题，第 k 个，共 n 个”。标题按 NotchSentence 从尾部截断（窗口标题一类），空标题念“窗口”。
    static func moveAnnouncement(title: String, index: Int, count: Int) -> String {
        "\(label(for: title))，第 \(index) 个，共 \(count) 个"
    }

    /// 同上，但整句已经备好（会话格的“项目，在等你”）：不再截断，状态一直念全。
    static func moveAnnouncement(cell: Cell, index: Int, count: Int) -> String {
        guard let spoken = cell.spoken, !spoken.isEmpty else { return moveAnnouncement(title: cell.title, index: index, count: count) }
        return "\(spoken)，第 \(index) 个，共 \(count) 个"
    }

    /// 格子上、读屏里用的标题：去掉首尾空白，超过副句上限就尾部省略。
    static func label(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "窗口" : NotchSentence.truncateTail(trimmed, limit: NotchSentence.detailLimit)
    }

    // MARK: 默认焦点

    static func defaultFocus(in cells: [Cell]) -> UInt32? {
        cells.first(where: \.waiting)?.id ?? cells.first(where: \.tucked)?.id ?? cells.first?.id
    }

    // MARK: 按键 → 动作

    /// 展开后面板接键盘：方向键、Return、Esc。带 ⌘⌃⌥ 的组合不拦，留给系统。
    static func action(forKeyCode code: UInt16, hasCommandModifiers: Bool) -> WS2.Action? {
        guard !hasCommandModifiers else { return nil }
        switch code {
        case 123: return .focusLeft
        case 124: return .focusRight
        case 125: return .focusDown
        case 126: return .focusUp
        case 36, 76: return .activateFocused
        case 53: return .back
        default: return nil
        }
    }

    /// 宿主要不要把这个动作交给这里：键盘、遥控器、手柄走同一个出口。
    static func handles(_ action: WS2.Action) -> Bool {
        switch action {
        case .focusUp, .focusDown, .focusLeft, .focusRight, .activateFocused, .back, .notchShelf: return true
        default: return false
        }
    }

    // MARK: 状态

    /// 亮着的格子的 id；指针在刘海里、或没开始时是 nil。
    var visibleFocusID: UInt32? { isActive && !pointerInside ? focusedID : nil }

    /// 亮着的那一格；没开始或不在列表里是 nil。
    var focusedCell: Cell? { focusedID.flatMap { id in cells.first { $0.id == id } } }
    /// 焦点此刻落在会话格上吗（不看指针：指针进来只是把焦点藏起来，它还在那一格）。
    var focusIsOnSession: Bool { isActive && focusedCell?.session == true }

    /// 第几个（从 1 数）；不在列表里是 nil。
    var focusedPosition: Int? {
        focusedID.flatMap { id in cells.firstIndex { $0.id == id } }.map { $0 + 1 }
    }

    /// 那一排的格子变了（重新展开、缩略图之外的内容变了）。焦点还在就留着，不在了就重选默认。
    mutating func setCells(_ next: [Cell]) {
        cells = next
        navigator.clear()
        guard isActive else { return }
        if let focusedID, next.contains(where: { $0.id == focusedID }) { return }
        focusedID = Self.defaultFocus(in: next)
    }

    mutating func pointerEntered() { pointerInside = true }
    mutating func pointerLeft() { pointerInside = false }

    /// 那一排收起了（指针出去、点了一格、更高的层挂起了它）：焦点随之结束。
    mutating func shelfClosed() {
        isActive = false
        focusedID = nil
        navigator.clear()
    }

    /// 统一出口。`.notchShelf` 是开关：没开始就开始，开着就结束。
    mutating func handle(_ action: WS2.Action) -> Effect {
        switch action {
        case .notchShelf:
            if isActive { shelfClosed(); return .end }
            isActive = true
            focusedID = Self.defaultFocus(in: cells)
            navigator.clear()
            return .begin(announcement: Self.openAnnouncement(count: cells.count))
        case .focusUp: return move(.up)
        case .focusDown: return move(.down)
        case .focusLeft: return move(.left)
        case .focusRight: return move(.right)
        case .activateFocused:
            guard let id = visibleFocusID else { return .none }
            return .activate(id: id)
        case .back:
            guard isActive else { return .none }
            // 这一排只有一层：Esc 直接收起。
            shelfClosed()
            return .end
        default:
            return .none
        }
    }

    /// 焦点直接回到最前面那一格（遥控器回到那一排）。一步到位，读屏只念这一格一次；已经在最前、指针占着或没开始时什么都不做。
    mutating func focusFirst() -> Effect {
        guard isActive, !pointerInside, let first = cells.first else { return .none }
        navigator.clear()
        guard first.id != focusedID else { return .none }
        focusedID = first.id
        return .moved(id: first.id,
                      announcement: Self.moveAnnouncement(title: first.title, index: 1, count: cells.count))
    }

    private mutating func move(_ direction: Direction) -> Effect {
        // 指针在刘海里时焦点是隐藏的，方向键不抢指针。
        guard isActive, !pointerInside, !cells.isEmpty else { return .none }
        let items = cells.enumerated().map { index, cell in
            FocusNavigator.Item(
                id: String(cell.id), group: "shelf", display: Self.display,
                rect: .init(x: Double(index) * NotchRow.pitch + (cell.ongoing ? NotchRow.dividerExtra : 0), y: 0,
                            width: NotchRow.cellWidth, height: 80),
                visible: true, enabled: true)
        }
        let current = focusedID.map(String.init)
        guard case .focused(let raw) = navigator.move(from: current, direction: direction, display: Self.display,
                                                      items: items),
              let id = UInt32(raw), let index = cells.firstIndex(where: { $0.id == id }) else { return .none }
        let line = Self.moveAnnouncement(cell: cells[index], index: index + 1, count: cells.count)
        if id == focusedID { return .bump(direction: direction, announcement: line) }
        focusedID = id
        return .moved(id: id, announcement: line)
    }
}
