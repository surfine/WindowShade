import Foundation

@main
struct NotchFocusTests {
    static func main() {
        var t = TestSuite("M07")
        typealias Cell = NotchFocusController.Cell
        func cell(_ id: UInt32, _ title: String = "窗口", waiting: Bool = false, tucked: Bool = false) -> Cell {
            Cell(id: id, title: title, waiting: waiting, tucked: tucked)
        }
        func started(_ cells: [Cell], pointerInside: Bool = false) -> NotchFocusController {
            var c = NotchFocusController()
            c.setCells(cells)
            if pointerInside { c.pointerEntered() }
            _ = c.handle(.notchShelf)
            return c
        }

        t.section("M07-01", "默认焦点：等你的会话格 > 最近收进去的 > 第一格")
        t.expect(NotchFocusController.defaultFocus(in: [cell(1), cell(2, tucked: true), cell(3, waiting: true)]) == 3, "有等你的会话格就落在它上面")
        t.expect(NotchFocusController.defaultFocus(in: [cell(1), cell(2, tucked: true), cell(3, tucked: true)]) == 2, "否则落在最近收进去的那一扇（宿主把最近的排在前面）")
        t.expect(NotchFocusController.defaultFocus(in: [cell(7), cell(8)]) == 7, "都没有就落在第一格")
        t.expect(NotchFocusController.defaultFocus(in: []) == nil, "空的一排没有焦点")
        t.expect(started([cell(1), cell(2, waiting: true)]).focusedID == 2, "开始时按默认落点")

        t.section("M07-02", "方向键挪焦点，到头不绕回、朝那个方向顶一下")
        var c = started([cell(1, "甲"), cell(2, "乙"), cell(3, "丙")])
        t.expect(c.focusedID == 1, "从第一格开始")
        if case .bump(let direction, let line) = c.handle(.focusLeft) {
            t.expect(direction == .left && line == "甲，第 1 个，共 3 个", "第一格再往左：顶一下，重念当前这一格")
        } else { t.expect(false, "第一格往左应该是 bump") }
        t.expect(c.focusedID == 1, "没有绕回最后一格")
        t.expect(c.handle(.focusRight) == .moved(id: 2, announcement: "乙，第 2 个，共 3 个"), "向右挪到第二格")
        t.expect(c.handle(.focusRight) == .moved(id: 3, announcement: "丙，第 3 个，共 3 个"), "再向右到最后一格")
        if case .bump(let direction, _) = c.handle(.focusRight) { t.expect(direction == .right && c.focusedID == 3, "最后一格再往右：顶一下，不绕回第一格") }
        else { t.expect(false, "最后一格往右应该是 bump") }
        if case .bump(let direction, _) = c.handle(.focusUp) { t.expect(direction == .up && c.focusedID == 3, "一排里往上没有目标：顶一下") }
        else { t.expect(false, "往上应该是 bump") }
        if case .bump(let direction, _) = c.handle(.focusDown) { t.expect(direction == .down, "往下也一样") }
        else { t.expect(false, "往下应该是 bump") }
        t.expect(c.handle(.focusLeft) == .moved(id: 2, announcement: "乙，第 2 个，共 3 个"), "往回挪")

        t.section("M07-03", "读屏字符串格式")
        t.expect(NotchFocusController.openAnnouncement(count: 3) == "刘海那一排，3 项", "展开时念“刘海那一排，n 项”")
        var opener = NotchFocusController()
        opener.setCells([cell(1), cell(2), cell(3), cell(4)])
        t.expect(opener.handle(.notchShelf) == .begin(announcement: "刘海那一排，4 项"), "开始时给宿主的就是这一句")
        t.expect(NotchFocusController.moveAnnouncement(title: "访达", index: 2, count: 5) == "访达，第 2 个，共 5 个", "挪一次念“标题，第 k 个，共 n 个”")
        let long = String(repeating: "长", count: 40)
        let labelled = NotchFocusController.label(for: long)
        t.expect(labelled.count == NotchSentence.detailLimit && labelled.hasSuffix("…"), "标题按 NotchSentence 尾部省略")
        t.expect(NotchFocusController.label(for: "  ") == "窗口" && NotchFocusController.label(for: " 备忘录 ") == "备忘录", "空标题念“窗口”，首尾空白去掉")
        let exact = String(repeating: "整", count: NotchSentence.detailLimit)
        t.expect(NotchFocusController.label(for: exact) == exact, "刚好到上限不动")

        t.section("M07-04", "指针进入时焦点隐藏（状态机）")
        var p = started([cell(1), cell(2)])
        t.expect(p.visibleFocusID == 1, "指针不在时焦点可见")
        p.pointerEntered()
        t.expect(p.visibleFocusID == nil && p.isActive && p.focusedID == 1, "指针一进来就隐藏，但位置记着")
        t.expect(p.handle(.focusRight) == .none && p.focusedID == 1, "指针在里面时方向键不抢指针")
        t.expect(p.handle(.activateFocused) == .none, "指针在里面时 Return 不打开隐藏的焦点")
        p.pointerLeft()
        t.expect(p.visibleFocusID == 1, "指针出去后焦点回来")
        t.expect(started([cell(1)], pointerInside: true).visibleFocusID == nil, "开始时指针已在刘海里：焦点保持隐藏")
        p.shelfClosed()
        t.expect(!p.isActive && p.visibleFocusID == nil, "那一排收起，焦点结束")
        t.expect(p.handle(.focusRight) == .none && p.handle(.activateFocused) == .none && p.handle(.back) == .none, "没开始时方向键、Return、Esc 都不处理")

        t.section("M07-05", "Return 打开亮着的格子；Esc 收起；统一出口是开关")
        var a = started([cell(5, "访达"), cell(6, "邮件")])
        _ = a.handle(.focusRight)
        t.expect(a.handle(.activateFocused) == .activate(id: 6), "Return 打开亮着的这一格")
        t.expect(a.handle(.back) == .end && !a.isActive, "Esc 收起这一排")
        t.expect(a.handle(.notchShelf) == .begin(announcement: "刘海那一排，2 项"), "再按展开动作重新开始")
        t.expect(a.handle(.notchShelf) == .end && !a.isActive, "开着时再按一次就结束")
        t.expect(a.handle(.mediaMute) == .none, "不认识的动作不处理")
        t.expect(NotchFocusController.handles(.focusUp) && NotchFocusController.handles(.back) && NotchFocusController.handles(.notchShelf)
                 && NotchFocusController.handles(.activateFocused) && !NotchFocusController.handles(.launchpad), "出口只接这些动作")

        t.section("M07-06", "格子变了：焦点还在就留着，不在了重选")
        var s = started([cell(1), cell(2), cell(3)])
        _ = s.handle(.focusRight)
        s.setCells([cell(9), cell(2), cell(3)])
        t.expect(s.focusedID == 2, "还在的焦点不动")
        s.setCells([cell(9, tucked: true), cell(3)])
        t.expect(s.focusedID == 9, "焦点那一格没了：重选默认落点")
        s.setCells([])
        t.expect(s.focusedID == nil && s.handle(.focusRight) == .none, "一格都没了：没有焦点")

        t.section("M07-06b", "回到最前面：一步到位，只念一次")
        var f = started([cell(1), cell(2), cell(3)])
        _ = f.handle(.focusRight); _ = f.handle(.focusRight)
        let back = f.focusFirst()
        t.expect(back == .moved(id: 1, announcement: NotchFocusController.moveAnnouncement(title: "窗口", index: 1, count: 3)) && f.focusedID == 1, "落在第一格，读屏一句")
        t.expect(f.focusFirst() == .none, "已经在最前：不再念")
        var g = started([cell(1), cell(2)])
        _ = g.handle(.focusRight); g.pointerEntered()
        t.expect(g.focusFirst() == .none && g.focusedID == 2, "指针占着：不抢")

        t.section("M07-07", "按键对应动作")
        t.expect(NotchFocusController.action(forKeyCode: 123, hasCommandModifiers: false) == .focusLeft
                 && NotchFocusController.action(forKeyCode: 124, hasCommandModifiers: false) == .focusRight
                 && NotchFocusController.action(forKeyCode: 125, hasCommandModifiers: false) == .focusDown
                 && NotchFocusController.action(forKeyCode: 126, hasCommandModifiers: false) == .focusUp, "四个方向键")
        t.expect(NotchFocusController.action(forKeyCode: 36, hasCommandModifiers: false) == .activateFocused
                 && NotchFocusController.action(forKeyCode: 76, hasCommandModifiers: false) == .activateFocused, "Return 与小键盘 Enter")
        t.expect(NotchFocusController.action(forKeyCode: 53, hasCommandModifiers: false) == .back, "Esc")
        t.expect(NotchFocusController.action(forKeyCode: 124, hasCommandModifiers: true) == nil, "带 ⌘⌃⌥ 的组合不拦")
        t.expect(NotchFocusController.action(forKeyCode: 0, hasCommandModifiers: false) == nil, "别的键不管")

        t.section("M07-08", "焦点样式：1.1 倍、上移 4 点、描边 2.5（增强对比度 4.5）、到头顶 6 点")
        typealias Style = NotchFocusController.Style
        t.expect(Style.scale == 1.1 && Style.lift == 4 && Style.bump == 6, "放大、抬起、顶出的数")
        t.expect(Style.stroke(increasedContrast: false) == 2.5 && Style.stroke(increasedContrast: true) == 4.5, "描边粗细")
        let rest = Style.transform(width: 124, height: 80, pivotX: 0, pivotY: 0, focused: false)
        t.expect(rest.scale == 1 && rest.translationX == 0 && rest.translationY == 0, "没亮的格子不变形")
        let centered = Style.transform(width: 124, height: 80, pivotX: 62, pivotY: 40, focused: true)
        t.expect(centered.scale == 1.1 && centered.translationX == 0 && centered.translationY == 4, "锚点在中心：只上移 4 点")
        let corner = Style.transform(width: 124, height: 80, pivotX: 0, pivotY: 0, focused: true)
        t.expect(abs(corner.translationX - -6.2) < 1e-9 && abs(corner.translationY - 0) < 1e-9, "锚点在左下角：平移补回，放大仍绕中心")
        // 格子中心放大后的位置：pivot + t + s·(c − pivot) 必须等于 c + (0, lift)。
        t.expect(abs((corner.translationX + 1.1 * 62) - 62) < 1e-9 && abs((corner.translationY + 1.1 * 40) - 44) < 1e-9, "格子中心只上移 4 点")
        let up = Style.transform(width: 124, height: 80, pivotX: 62, pivotY: 40, focused: true, bump: .up)
        let left = Style.transform(width: 124, height: 80, pivotX: 62, pivotY: 40, focused: true, bump: .left)
        t.expect(up.translationY == 10 && left.translationX == -6, "顶出：朝那个方向多 6 点")
        t.finish()
    }
}
