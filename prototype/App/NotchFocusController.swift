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
// - 打字筛选（LA-7）：点刘海或按快捷键打开的那一排接键盘，直接打字就筛（规则在 NotchRowFilter）；悬停打开的不接键盘。
//   对不上的格子离开，焦点落第一格；Esc 先清字，再按一次才收起；指针进来焦点熄灭，筛选的字留着。

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
        /// 筛选时除标题以外还找的字：窗口格是 App 名，正在进行的格是种类名。共享屏幕时被遮住的格不给（和标题一样不露）。
        var terms: [String] = []
    }

    /// 那一排是怎么打开的。点（长按）和快捷键接键盘；悬停打开的不接：你在别的 App 里打字，不会被刘海吃掉。
    enum Origin: Sendable { case shortcut, press, hover }

    /// 一次按键里和筛选有关的部分。
    enum TypedInput: Equatable, Sendable {
        case insert(String)
        case deleteBackward
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
        /// 筛选的字变了（或被清掉）：宿主按 `cells` 重排这一排，`announcement` 念“剩 n 项”。
        case filtered(announcement: String)
        /// 收起这一排、交还键盘。
        case end
    }

    /// 现在显示的格子（筛选之后）。没有筛选时就是 `allCells`。
    private(set) var cells: [Cell] = []
    /// 这一排所有的格子（筛选之前）。
    private(set) var allCells: [Cell] = []
    /// 筛选字。空就是没有筛选。
    private(set) var query = ""
    /// 这一次打开接不接键盘打字（悬停打开的不接）。
    private(set) var acceptsTyping = false
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
        WSL10n.text("notch.alert.indexWithLabel", zh: "%@，第 %@ 个，共 %@ 个", label(for: title), String(index), String(count))
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

    /// 打字筛选用的按键：删除键，或可打印的字。带 ⌘⌃⌥ 的组合不拦；空格留给筛选字（标题里有空格），但不能是第一个字。
    /// 方向键、Return、Esc、Tab 这类（它们的字符落在控制区或私用区）一律不是字。
    static func typedInput(forKeyCode code: UInt16, characters: String?, hasCommandModifiers: Bool) -> TypedInput? {
        guard !hasCommandModifiers else { return nil }
        if code == 51 { return .deleteBackward }
        guard let characters, !characters.isEmpty else { return nil }
        let typable = String(characters.filter(NotchRowFilter.isTypable))
        return typable.isEmpty ? nil : .insert(typable)
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
    /// 正在筛选吗。
    var isFiltering: Bool { !query.isEmpty }
    /// 筛选之后一格也没有：那一排写“没有匹配的”。
    var showsNoMatch: Bool { isFiltering && cells.isEmpty }
    /// 现在显示的格子的 id（宿主按它从自己的格子里挑出要画的）。
    var visibleIDs: [UInt32] { cells.map(\.id) }

    /// 焦点此刻落在会话格上吗（不看指针：指针进来只是把焦点藏起来，它还在那一格）。
    var focusIsOnSession: Bool { isActive && focusedCell?.session == true }

    /// 第几个（从 1 数）；不在列表里是 nil。
    var focusedPosition: Int? {
        focusedID.flatMap { id in cells.firstIndex { $0.id == id } }.map { $0 + 1 }
    }

    /// 那一排的格子变了（重新展开、缩略图之外的内容变了）。焦点还在就留着，不在了就重选默认。
    mutating func setCells(_ next: [Cell]) {
        allCells = next
        cells = filtered(next)
        navigator.clear()
        guard isActive else { return }
        if let focusedID, cells.contains(where: { $0.id == focusedID }) { return }
        focusedID = isFiltering ? cells.first?.id : Self.defaultFocus(in: cells)
    }

    private func filtered(_ list: [Cell]) -> [Cell] {
        isFiltering ? list.filter { NotchRowFilter.matches(query: query, title: $0.title, terms: $0.terms) } : list
    }

    /// 筛选字换了：重新挑格子，焦点落第一格（一格也没有就没有焦点）。
    private mutating func refilter() -> Effect {
        cells = filtered(allCells)
        navigator.clear()
        focusedID = isFiltering ? cells.first?.id : Self.defaultFocus(in: cells)
        return .filtered(announcement: NotchRowFilter.remainingAnnouncement(count: cells.count))
    }

    /// 打字。不接键盘（悬停打开的、没开始的）什么都不做。
    mutating func type(_ text: String) -> Effect {
        guard isActive, acceptsTyping else { return .none }
        var next = query
        for character in text where NotchRowFilter.isTypable(character) {
            if next.isEmpty, character.isWhitespace { continue }
            guard next.count < NotchRowFilter.maxQueryLength else { break }
            next.append(character)
        }
        guard next != query else { return .none }
        query = next
        return refilter()
    }

    /// 退格：删最后一个字。没有字时什么都不做。
    mutating func deleteBackward() -> Effect {
        guard isActive, acceptsTyping, !query.isEmpty else { return .none }
        query.removeLast()
        return refilter()
    }

    /// 按键对应的输入交给这里。
    mutating func apply(_ input: TypedInput) -> Effect {
        switch input {
        case .insert(let text): return type(text)
        case .deleteBackward: return deleteBackward()
        }
    }

    mutating func pointerEntered() { pointerInside = true }
    mutating func pointerLeft() { pointerInside = false }

    /// 那一排收起了（指针出去、点了一格、更高的层挂起了它）：焦点随之结束。
    mutating func shelfClosed() {
        isActive = false
        focusedID = nil
        query = ""
        acceptsTyping = false
        cells = allCells
        navigator.clear()
    }

    /// 开始。`.hover` 不接键盘：什么都不做（那一排由悬停展开，焦点和键盘都不归这里）。
    mutating func begin(origin: Origin) -> Effect {
        guard origin != .hover, !isActive else { return .none }
        isActive = true
        acceptsTyping = true
        query = ""
        cells = allCells
        focusedID = Self.defaultFocus(in: cells)
        navigator.clear()
        return .begin(announcement: Self.openAnnouncement(count: cells.count))
    }

    /// 统一出口。`.notchShelf` 是开关：没开始就开始，开着就结束。
    mutating func handle(_ action: WS2.Action) -> Effect {
        switch action {
        case .notchShelf:
            if isActive { shelfClosed(); return .end }
            return begin(origin: .shortcut)
        case .focusUp: return move(.up)
        case .focusDown: return move(.down)
        case .focusLeft: return move(.left)
        case .focusRight: return move(.right)
        case .activateFocused:
            guard let id = visibleFocusID else { return .none }
            return .activate(id: id)
        case .back:
            guard isActive else { return .none }
            // 有字先清字，再按一次才收起。
            if isFiltering {
                query = ""
                return refilter()
            }
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
