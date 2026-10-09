import Foundation

@main
struct NotchRowFilterTests {
    static func main() {
        var t = TestSuite("LA-7")
        typealias Cell = NotchFocusController.Cell
        func win(_ id: UInt32, _ title: String, app: String = "", tucked: Bool = true) -> Cell {
            Cell(id: id, title: title, tucked: tucked, terms: app.isEmpty ? [] : [app])
        }
        func act(_ id: UInt32, _ title: String, kind: String) -> Cell {
            Cell(id: id, title: title, ongoing: true, terms: [kind])
        }
        let download: UInt32 = 0xF000_0000
        let session: UInt32 = 0xF000_0001
        let row: [Cell] = [
            win(1, "周会纪要", app: "备忘录"), win(2, "报价单.pdf", app: "Preview"), win(3, "Inbox", app: "Mail"),
            win(4, "主页", app: "Safari"),
            act(download, "视频.mov", kind: "下载"), act(session, "WindowShade", kind: "编程会话"),
        ]
        func started(_ cells: [Cell] = row, origin: NotchFocusController.Origin = .shortcut, pointerInside: Bool = false) -> NotchFocusController {
            var c = NotchFocusController()
            c.setCells(cells)
            if pointerInside { c.pointerEntered() }
            _ = c.begin(origin: origin)
            return c
        }

        t.section("LA7-01", "匹配：标题、App 名、种类名；不分大小写")
        t.expect(NotchRowFilter.matches(query: "报价", title: "报价单.pdf", terms: ["Preview"]), "标题字面包含")
        t.expect(NotchRowFilter.matches(query: "PREVIEW", title: "报价单.pdf", terms: ["Preview"]), "App 名，不分大小写")
        t.expect(NotchRowFilter.matches(query: "下载", title: "视频.mov", terms: ["下载"]), "活动的种类名")
        t.expect(!NotchRowFilter.matches(query: "邮件", title: "报价单.pdf", terms: ["Preview"]), "对不上就是对不上")
        t.expect(NotchRowFilter.matches(query: "  ", title: "x", terms: []), "空白筛选字等于没有筛选")
        t.expect(NotchRowFilter.matches(query: "ｐｄｆ", title: "报价单.pdf", terms: []), "全角字母也认")
        t.expect(!NotchRowFilter.matches(query: "x", title: "", terms: [""]), "空标题、空字段谁也对不上")

        t.section("LA7-02", "拼音首字母")
        t.expect(NotchRowFilter.initials(of: "周会") == "zh", "“周会”首字母 zh")
        t.expect(NotchRowFilter.initials(of: "备忘录") == "bwl", "“备忘录”首字母 bwl")
        t.expect(NotchRowFilter.initials(of: "Safari 浏览器") == "safarillq", "夹着英文：英文原样小写，空格略过")
        t.expect(NotchRowFilter.matches(query: "zh", title: "周会纪要", terms: []), "“zh”找到“周会”")
        t.expect(NotchRowFilter.matches(query: "ZHJY", title: "周会纪要", terms: []), "首字母连着打，大小写都行")
        t.expect(NotchRowFilter.matches(query: "bwl", title: "x", terms: ["备忘录"]), "App 名也认拼音首字母")
        t.expect(!NotchRowFilter.matches(query: "zx", title: "周会纪要", terms: []), "不连着的首字母不算")
        t.expect(NotchRowFilter.matches(query: "xz", title: "下载", terms: []), "种类名也认：“xz”找到“下载”")

        t.section("LA7-03", "打字筛：对不上的离开，焦点落第一格，读屏“剩 n 项”")
        var c = started()
        t.expect(c.cells.count == 6 && c.acceptsTyping, "接键盘，起初六格")
        t.expect(c.type("zh") == .filtered(announcement: "剩 1 项"), "打 zh：只剩“周会纪要”")
        t.expect(c.visibleIDs == [1] && c.focusedID == 1, "焦点落第一格")
        t.expect(c.allCells.count == 6, "全部的格子还在，退格能回来")
        t.expect(c.deleteBackward() == .filtered(announcement: "剩 3 项") && c.query == "z" && c.visibleIDs == [1, 4, download],
                 "退格删一个字：“z”还对上“主页”“下载”的首字母")
        var d = started()
        t.expect(d.type("i") == .filtered(announcement: "剩 4 项"), "打 i：Preview、Inbox、Safari、WindowShade")
        t.expect(d.visibleIDs == [2, 3, 4, session] && d.focusedID == 2, "焦点落留下来的第一格")
        t.expect(d.type("n") == .filtered(announcement: "剩 2 项"), "再打 n：留下含 in 的（Inbox、WindowShade）")
        t.expect(d.visibleIDs == [3, session] && d.focusedID == 3, "剩下的保持原来的先后顺序，焦点落第一格")
        t.expect(d.type("zzz") == .filtered(announcement: "没有匹配的") && d.showsNoMatch && d.focusedID == nil, "一格也没有：写“没有匹配的”，焦点没有")
        t.expect(d.handle(.activateFocused) == .none && d.handle(.focusRight) == .none, "没有格子时 Return 与方向键不动")
        _ = d.deleteBackward(); _ = d.deleteBackward(); _ = d.deleteBackward()
        t.expect(d.visibleIDs == [3, session] && d.focusedID == 3 && !d.showsNoMatch, "退格退回去，格子回来")

        t.section("LA7-04", "只找自己的格子：别人的菜单、菜单栏图标、文件找不到")
        var o = started([win(1, "文档", app: "Pages")])
        t.expect(o.type("文件") == .filtered(announcement: "没有匹配的"), "一格里没有的字就是没有（不会去找文件）")
        t.expect(NotchRowFilter.matches(query: "编程", title: "WindowShade", terms: [NotchRowFilter.kindName(.session)]), "编程会话的种类名")
        t.expect(NotchRowFilter.kindName(.timer) == "计时器" && NotchRowFilter.kindName(.calendar) == "日程"
                 && NotchRowFilter.kindName(.focus) == "番茄钟" && NotchRowFilter.kindName(.shelf) == "文件架", "种类名和文案表一致")
        var redacted = started([Cell(id: 9, title: "", tucked: true, terms: [])])
        t.expect(redacted.type("a") == .filtered(announcement: "没有匹配的"), "共享屏幕时被遮住的格（标题、App 名都空）谁也找不到")

        t.section("LA7-05", "悬停打开的那一排不接键盘")
        var h = started(origin: .hover)
        t.expect(!h.isActive && !h.acceptsTyping, "悬停开始：什么都没开始")
        t.expect(h.type("zh") == .none && h.query.isEmpty && h.cells.count == 6, "打字被忽略，格子不变")
        t.expect(h.deleteBackward() == .none, "退格也不管")
        t.expect(started(origin: .press).acceptsTyping && started(origin: .shortcut).acceptsTyping, "点（长按）和快捷键打开：接键盘")
        var idle = NotchFocusController()
        idle.setCells(row)
        t.expect(idle.type("a") == .none, "没开始时打字不处理")

        t.section("LA7-06", "Esc 两步：先清字，再收起")
        var e = started()
        _ = e.type("zh")
        t.expect(e.handle(.back) == .filtered(announcement: "剩 6 项") && e.query.isEmpty && e.isActive, "第一次 Esc：清字，那一排还开着，格子都回来")
        t.expect(e.cells.count == 6 && e.focusedID == NotchFocusController.defaultFocus(in: row), "回到默认落点")
        t.expect(e.handle(.back) == .end && !e.isActive, "第二次 Esc：收起")
        var again = started()
        _ = again.type("zh"); _ = again.handle(.notchShelf)
        t.expect(!again.isActive && again.query.isEmpty && again.cells.count == 6, "快捷键收起也把字清掉")
        var zero = started()
        _ = zero.type("qqq")
        t.expect(zero.handle(.back) == .filtered(announcement: "剩 6 项"), "什么都没匹配时 Esc 也是先清字")

        t.section("LA7-07", "指针进来焦点熄灭，筛选的字留着")
        var p = started()
        _ = p.type("zh")
        p.pointerEntered()
        t.expect(p.visibleFocusID == nil && p.query == "zh" && p.cells.count == 1, "字和结果都留着")
        t.expect(p.type("j") == .filtered(announcement: "剩 1 项") && p.query == "zhj", "指针在里面照样能打字")
        p.pointerLeft()
        t.expect(p.visibleFocusID == p.focusedID && p.focusedID != nil, "指针出去焦点回来")
        let clickStart = started(origin: .press, pointerInside: true)
        t.expect(clickStart.acceptsTyping && clickStart.visibleFocusID == nil, "点开的那一排：指针在里面，焦点先熄，字照打")

        t.section("LA7-08", "格子变了（重新展开）：字留着，按字重新筛")
        var r = started()
        _ = r.type("in")
        r.setCells(row + [win(5, "Linux 笔记", app: "Notes")])
        t.expect(r.visibleIDs == [3, session, 5] && r.focusedID == 3, "新来的格子也按筛选字过一遍；焦点还在就不动")
        r.setCells([win(5, "Linux 笔记", app: "Notes")])
        t.expect(r.focusedID == 5, "焦点那一格没了：落在剩下的第一格")
        var cleared = started()
        _ = cleared.type("zh")
        cleared.shelfClosed()
        t.expect(cleared.query.isEmpty && cleared.cells.count == 6 && !cleared.acceptsTyping, "收起：字、筛选、接键盘都复位")

        t.section("LA7-09", "按键 → 输入")
        t.expect(NotchFocusController.typedInput(forKeyCode: 6, characters: "z", hasCommandModifiers: false) == .insert("z"), "字母")
        t.expect(NotchFocusController.typedInput(forKeyCode: 51, characters: "\u{7F}", hasCommandModifiers: false) == .deleteBackward, "退格")
        t.expect(NotchFocusController.typedInput(forKeyCode: 6, characters: "z", hasCommandModifiers: true) == nil, "带 ⌘⌃⌥ 的组合不拦")
        t.expect(NotchFocusController.typedInput(forKeyCode: 123, characters: "\u{F702}", hasCommandModifiers: false) == nil, "方向键的字符不是字")
        t.expect(NotchFocusController.typedInput(forKeyCode: 36, characters: "\r", hasCommandModifiers: false) == nil
                 && NotchFocusController.typedInput(forKeyCode: 48, characters: "\t", hasCommandModifiers: false) == nil
                 && NotchFocusController.typedInput(forKeyCode: 53, characters: "\u{1B}", hasCommandModifiers: false) == nil, "Return、Tab、Esc 不是字")
        t.expect(NotchFocusController.typedInput(forKeyCode: 0, characters: nil, hasCommandModifiers: false) == nil, "没有字符就不是输入")
        var s = started()
        t.expect(s.type(" ") == .none && s.query.isEmpty, "第一个字不能是空格")
        _ = s.type("w"); _ = s.type(" "); _ = s.type("s")
        t.expect(s.query == "w s", "空格可以在字中间")
        var long = started()
        _ = long.type(String(repeating: "a", count: 60))
        t.expect(long.query.count == NotchRowFilter.maxQueryLength, "筛选字有上限")
        t.expect(NotchRowFilter.visibleTail(of: "abcdefghij", limit: 5) == "…ghij" && NotchRowFilter.visibleTail(of: "abc", limit: 5) == "abc",
                 "放不下时留最后几个字")

        t.section("LA7-10", "一格也没有时那一排不窄于两格；读屏")
        t.expect(NotchRowFilter.emptyMinimumCells == 2
                 && NotchRowFilter.emptyIslandWidth == NotchRow.layout(windows: 2, ongoing: 0).islandWidth(minimum: 0), "两格的宽度")
        t.expect(NotchRowFilter.emptyIslandWidth > NotchRow.layout(windows: 1, ongoing: 0).islandWidth(minimum: 0), "比一格宽")
        t.expect(NotchRowFilter.noMatchText == "没有匹配的", "没有匹配的话术")
        t.expect(NotchRowFilter.remainingAnnouncement(count: 2) == "剩 2 项" && NotchRowFilter.remainingAnnouncement(count: 0) == "没有匹配的", "读屏：剩 2 项 / 没有匹配的")

        t.section("LA7-11", "旧行为不变")
        var legacy = NotchFocusController()
        legacy.setCells([Cell(id: 1, title: "甲"), Cell(id: 2, title: "乙")])
        t.expect(legacy.handle(.notchShelf) == .begin(announcement: "刘海那一排，2 项") && legacy.focusedID == 1, "快捷键开始与读屏不变")
        t.expect(legacy.handle(.focusRight) == .moved(id: 2, announcement: "乙，第 2 个，共 2 个"), "方向键不变")
        t.expect(legacy.handle(.back) == .end, "没有字时 Esc 直接收起")
        t.finish()
    }
}
