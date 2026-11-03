// 刘海那一排的分段与坐标（M11）：左段收着的窗口，中间一条竖线，右段正在进行的。纯 Foundation，画和接线在 App/Notch/。
// 窗口与正在进行的事以前是上下叠放的两块（活动卡+窗口格、两种高度）、两个主人（notchShelf、agentSessions）；现在
// 一排、一个主人、一套格子索引：指针、键盘焦点（M07）、遥控器（M09）看同一页，焦点可跨过竖线。
// 左段是收着的窗口格（缩略图 16:10），右段是正在播放/编程会话等；竖线 1pt、白 0.2、上下各留 10pt，只在两段都有格子时
// 才有。外框圆角 28、边距 14、格子圆角 14、格间 8（同心，HIG）；正在播放那格点开长成大卡、右下留 24 点播放/暂停键
// （NP-4）；读屏竖线不念，右段格子念“项目，在等你”。这里只有数字和字符串，不碰 AppKit。

import Foundation

/// 合成一排的开关（M11，默认开）。键里没有值用默认；显式开或关的值原样用。
enum NotchMergedRowPreference {
    static let defaultsKey = "Notch.mergedRow"
    static var defaultEnabled: Bool { ReleaseDefaults.value(defaultsKey) }
    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? defaultEnabled
    }
    /// 开关切换后，展开着的那一排要不要重排：只有展开着、且现在的样子和新设置不一样才重排（不动画闪烁）。
    static func needsReflow(isExpanded: Bool, currentlyMerged: Bool, enabled: Bool) -> Bool {
        isExpanded && currentlyMerged != enabled
    }
}

enum NotchRow {
    // MARK: 尺寸

    static let cellWidth = 124.0
    static let cellGap = 8.0
    /// 一格加一个间隙：相邻两格左边缘的距离。
    static let pitch = cellWidth + cellGap
    /// 岛的外框到格子的边距。
    static let edgeMargin = 14.0
    static let cellRadius = 14.0
    static let outerRadius = 28.0
    static let dividerWidth = 1.0
    /// 竖线上下各留多少。
    static let dividerInset = 10.0
    static let dividerWhite = 0.2
    /// 竖线两边各一个间隙：它让右段比平常的间隙多占 1 + 8（竖线本身加一侧间隙，另一侧原有的间隙不变）。
    static let dividerExtra = dividerWidth + cellGap
    /// 缩略图的宽高比。
    static let thumbnailAspect = 16.0 / 10.0
    /// 左段最多几格、右段最多几格（实时活动可见上限是 3）。
    static let windowLimit = 8
    static let ongoingLimit = 3

    // MARK: 分段

    /// 窄格（「还有 N 件」）的宽。
    static let narrowCellWidth = 56.0

    /// 这一排实际放几格、怎么摆。最前面是「离开期间」的格子（`away`，回来后那一阵才有），然后是 `windows`，最后是 `ongoing`；
    /// 相邻的两段都有格子时，中间各隔一条竖线。`awayNarrow`：离开期间的最后一格是 56 宽的「还有 N 件」窄格。
    struct Layout: Equatable, Sendable {
        var away = 0
        var awayNarrow = false
        let windows: Int
        let ongoing: Int
        var count: Int { away + windows + ongoing }
        /// 离开期间那一段和后面隔一条竖线。
        var hasAwayDivider: Bool { away > 0 && windows + ongoing > 0 }
        /// 窗口段和正在进行的段之间隔一条竖线。
        var hasWindowsDivider: Bool { windows > 0 && ongoing > 0 }
        /// 有没有竖线（任何一条）。
        var hasDivider: Bool { hasAwayDivider || hasWindowsDivider }
        private var dividerCount: Int { (hasAwayDivider ? 1 : 0) + (hasWindowsDivider ? 1 : 0) }
        /// 窄格比普通格窄多少（没有窄格是 0）。
        private var narrowShortfall: Double { awayNarrow && away > 0 ? cellWidth - narrowCellWidth : 0 }
        /// 第 index 格多宽。
        func width(ofCell index: Int) -> Double {
            awayNarrow && away > 0 && index == away - 1 ? narrowCellWidth : cellWidth
        }
        /// 所有格子加上间隙（和竖线）占多宽；没有格子是 0。
        var contentWidth: Double {
            guard count > 0 else { return 0 }
            return Double(count) * pitch - cellGap - narrowShortfall + Double(dividerCount) * dividerExtra
        }
        /// 第 index 格（从左数，先离开期间、再窗口、最后正在进行的）的左边缘，相对于内容的左边。
        func x(ofCell index: Int) -> Double {
            let i = max(0, index)
            var x = Double(i) * pitch
            if awayNarrow, away > 0, i >= away { x -= narrowShortfall }
            if hasAwayDivider, i >= away { x += dividerExtra }
            if hasWindowsDivider, i >= away + windows { x += dividerExtra }
            return x
        }
        /// 每一条竖线的左边缘，相对于内容的左边（从左到右）。
        var dividerXs: [Double] {
            var result: [Double] = []
            if hasAwayDivider { result.append(Double(away) * pitch - narrowShortfall) }
            if hasWindowsDivider {
                result.append(Double(away + windows) * pitch - narrowShortfall + (hasAwayDivider ? dividerExtra : 0))
            }
            return result
        }
        /// 第一条竖线的左边缘；没有竖线是 nil。
        var dividerX: Double? { dividerXs.first }
        /// 岛至少多宽：内容加两边的边距，不小于 `minimum`。
        func islandWidth(minimum: Double) -> Double {
            max(minimum, count == 0 ? 0 : contentWidth + 2 * edgeMargin)
        }
        /// 内容在一排里居中时的左边缘。
        func leading(inRowWidth width: Double) -> Double { (width - contentWidth) / 2 }
        /// 第一条竖线的外框：x 在一排里的位置，y 与高度按格子的竖直范围算（上下各留 10）。
        func dividerFrame(inRowWidth width: Double, cellsMinY: Double, cellsHeight: Double)
            -> (x: Double, y: Double, width: Double, height: Double)? {
            dividerFrames(inRowWidth: width, cellsMinY: cellsMinY, cellsHeight: cellsHeight).first
        }
        /// 每一条竖线的外框。
        func dividerFrames(inRowWidth width: Double, cellsMinY: Double, cellsHeight: Double)
            -> [(x: Double, y: Double, width: Double, height: Double)] {
            dividerXs.map {
                (leading(inRowWidth: width) + $0, cellsMinY + dividerInset, dividerWidth, max(0, cellsHeight - 2 * dividerInset))
            }
        }
    }

    /// 按数量排版，不裁。
    static func layout(windows: Int, ongoing: Int, away: Int = 0, awayNarrow: Bool = false) -> Layout {
        Layout(away: max(0, away), awayNarrow: away > 0 && awayNarrow, windows: max(0, windows), ongoing: max(0, ongoing))
    }

    /// 最多几格：窗口最多 8 格、正在进行的最多 3 格。照系统的岛，那一排宽固定（408）、格子全部排出、放不下就左右滚，
    /// 不再按屏宽裁格；这里只留数量上限（每一段的上限和以前一样，不是宽度裁剪）。离开期间的格子不裁（它自己有上限 4 + 窄格）。
    ///
    /// `tail`：右段末尾多一格文件架（FS-04）。它不算进“最多 3 件”（多放一格）。
    static func fit(windows: Int, ongoing: Int, tail: Bool = false, away: Int = 0, awayNarrow: Bool = false) -> Layout {
        Layout(away: max(0, away), awayNarrow: away > 0 && awayNarrow,
               windows: min(max(0, windows), windowLimit), ongoing: min(max(0, ongoing), ongoingLimit + (tail ? 1 : 0)))
    }

    // MARK: 滚动

    /// 岛固定宽：照系统的岛，展开上限 408（数字在 IslandMetrics，暂定，iOS 尺寸）。
    static var islandWidth: Double { Double(IslandMetrics.expandedWidth) }
    /// 滚动视口：岛宽减两边的边距（408 时是 380）。
    static var viewportWidth: Double { islandWidth - 2 * edgeMargin }

    /// 内容比视口宽多少，就是最多能滚多远；放得下是 0。
    static func maxScrollOffset(contentWidth: Double, viewport: Double = viewportWidth) -> Double {
        max(0, contentWidth - viewport)
    }

    /// 滚动位置夹在 0…最远之间。
    static func clampedOffset(_ offset: Double, contentWidth: Double, viewport: Double = viewportWidth) -> Double {
        min(max(0, offset), maxScrollOffset(contentWidth: contentWidth, viewport: viewport))
    }

    /// 内容放得下视口时居中，放不下从左边起排（再靠滚动看别的格）。返回内容左边缘在视口里的位置。
    static func contentOrigin(contentWidth: Double, viewport: Double = viewportWidth) -> Double {
        max(0, (viewport - contentWidth) / 2)
    }

    /// 键盘焦点走到第 index 格时，滚动位置要变成多少才看得全它（原位置够用就不动）。
    /// 后面（或前面）还有内容的那一侧多留一段淡出的宽度，免得焦点格被淡出盖住。
    static func offset(toReveal index: Int, in layout: Layout, current: Double, viewport: Double = viewportWidth,
                       fade: Double = Double(IslandMetrics.rowEdgeFadeWidth)) -> Double {
        let content = layout.contentWidth
        guard layout.count > 0, content > viewport else { return 0 }
        let i = min(max(0, index), layout.count - 1)
        let left = layout.x(ofCell: i)
        let right = left + layout.width(ofCell: i)
        let target: Double
        if left - (i > 0 ? fade : 0) < current { target = left - (i > 0 ? fade : 0) }
        else if right + (i < layout.count - 1 ? fade : 0) > current + viewport { target = right + (i < layout.count - 1 ? fade : 0) - viewport }
        else { target = current }
        return clampedOffset(target, contentWidth: content, viewport: viewport)
    }

    /// 视口左右两边要不要淡出：左边滚过了、右边后面还有。
    static func edgeFades(offset: Double, contentWidth: Double, viewport: Double = viewportWidth) -> (leading: Bool, trailing: Bool) {
        let limit = maxScrollOffset(contentWidth: contentWidth, viewport: viewport)
        return (offset > 0.5, offset < limit - 0.5)
    }

    /// 滚轮、触控板一下滚多少：触控板双指的横向位移（精确值，点）直接用；普通滚轮按行算（一行 10 点，竖滚轮也横着滚）。
    static func scrollDelta(precise: Bool, deltaX: Double, deltaY: Double) -> Double {
        if precise { return -deltaX }
        let lines = abs(deltaX) >= abs(deltaY) ? deltaX : deltaY
        return -lines * 10
    }

    /// 这一下滚动是不是归那一排（横着为主）。精确滚动（触控板）看横竖哪个大；普通滚轮没有横向分量时也归那一排。
    static func scrollBelongsToRow(precise: Bool, deltaX: Double, deltaY: Double) -> Bool {
        precise ? abs(deltaX) > abs(deltaY) : true
    }

    // MARK: 格子编号

    /// 窗口格的编号就是窗口号（CGWindowID，都很小）；正在进行的格借用高位编号，两边不会撞。
    static let ongoingIDBase: UInt32 = 0xF000_0000
    static func isOngoingID(_ id: UInt32) -> Bool { id >= ongoingIDBase }

    /// 活动 id（字符串）到格子编号的对应。同一个活动一直用同一个编号，格子重排、焦点和点击都认得它。
    struct IDMap: Sendable {
        /// 登记上限。活动的 id 就那么十来种；超过说明有东西不对，多出来的不再给编号。
        static let limit = 64
        private var forward: [String: UInt32] = [:]
        private var backward: [UInt32: String] = [:]
        private var next = ongoingIDBase


        mutating func id(for activityID: String) -> UInt32? {
            if let known = forward[activityID] { return known }
            guard forward.count < Self.limit else { return nil }
            let assigned = next
            next += 1
            forward[activityID] = assigned
            backward[assigned] = activityID
            return assigned
        }

        func activityID(for id: UInt32) -> String? { backward[id] }
    }

    // MARK: 右段放什么

    /// 右段的一格。`phase` 只有编程会话有。
    struct OngoingCell: Equatable, Sendable {
        let activityID: String
        let kind: NotchActivityKind
        let title: String
        let subtitle: String
        let symbol: String
        let phase: NotchSessionPhase?
        let isPaused: Bool
        /// 这件事的量（M12）：番茄钟的进度已经是左耳那圈环，格子里不再画。和紧凑右耳用同一套画法——有比例画环加数，只有个数写“第 k / n”，在做但不知道多少画不确定的弧。
        var quantity: NotchActivity.Quantity = .unknown
        /// 右耳上的字（会话在有额度数据时是“剩 p%”）；读屏用它念出剩多少。
        var earText: String? = nil
        /// 过期了（来源过了自己的过期时间还没消息）：格子内容画 0.5 透明，读屏加一句“可能已停”。
        var isStale = false
        /// 结束了，这是最后的样子（留在那一排里到看过或 15 分钟）：没有能点的动作。
        var isEnded = false

        /// 格子上量的数字：比例只给本身是百分比的种类写（和右耳一致），个数一律写；没有就不写。
        var quantityText: String? {
            if kind == .session, phase == .quota || phase == .quotaLow {
                return earText.flatMap { $0.isEmpty ? nil : $0 }
            }
            return quantity.valueText(writesPercent: kind.writesPercent)
        }
        /// 这个格子该怎么画量。
        var quantityDrawing: NotchProgressDrawing { quantity.drawing }

        /// 等你的会话格：键盘焦点默认落在它上面（NotchTile.waiting）。
        var waiting: Bool { phase == .waiting }
        var isSession: Bool { kind == .session }
        /// 点一下（或 Return）做什么：音乐是长成正在播放大卡（NP-4），别的都是“打开”（会话格走进指挥页，见 NotchController.activateOngoing）。
        var action: NotchActivityAction { kind == .music ? .nowPlayingOpen : .open }
        /// 做完这件事以后这一排要不要收起：都收。音乐是这一排长成了大卡，别的都要去别处。
        var closesRow: Bool { true }
        /// 格子右下角那个 24 点的小键（NP-4）：只有音乐有，点它是播放 / 暂停，这一排留着。
        var accessory: NotchActivityAction? { kind == .music ? .playPause : nil }
        static let accessorySide = 24.0
        /// 读屏念的话。
        var spoken: String { NotchRow.spoken(self) }
    }

    /// 能进右段的活动：正在播放的那一件、编程会话，以及下载、路线、录音、隔空投送、番茄钟这类正在进行的事。
    /// 耳机电量和遥控器连着只是耳朵上的符号，没有可点的东西，不进这一排。按 store 的顺序，最多 3 格。
    /// 文件架不算这 3 格：它是右段最后那一格三张叠起来的缩略图，由《文件架》那条线自己画。
    static func ongoingCells(from activities: [NotchActivity]) -> [OngoingCell] {
        let cells: [OngoingCell] = activities.compactMap { item in
            switch item.kind {
            case .airPods, .remote, .shelf: return nil
            default:
                return OngoingCell(activityID: item.id, kind: item.kind,
                                   title: item.kind == .focus ? NotchEarText.cardTitle(item) : item.title,
                                   subtitle: subtitle(of: item), symbol: item.symbol, phase: item.sessionPhase,
                                   isPaused: item.isPaused, quantity: item.kind == .focus ? .unknown : item.progress,
                                   earText: item.sessionPhase == .quota || item.sessionPhase == .quotaLow ? item.trailing : nil,
                                   isStale: item.isStale, isEnded: item.isEnded)
            }
        }
        return Array(cells.prefix(ongoingLimit))
    }

    private static func subtitle(of item: NotchActivity) -> String {
        if item.kind == .music, item.isPaused { return WSL10n.text("say.paused", zh: "已暂停") }
        return item.subtitle
    }

    // MARK: 读屏

    /// 会话格：“项目，在等你”“项目，在跑”；做完的那一格是“完成，改了 3 个文件”。其它：标题加状态。
    /// 项目名超长时只截项目名，状态一直念全。
    static func spoken(_ cell: OngoingCell) -> String {
        let base = liveSpoken(cell)
        return cell.isStale ? join(base, NotchActivity.staleSpoken) : base
    }

    private static func liveSpoken(_ cell: OngoingCell) -> String {
        let name = clipped(cell.title.trimmingCharacters(in: .whitespacesAndNewlines))
        switch cell.kind {
        case .session:
            switch cell.phase {
            case .waiting?: return join(name, WSL10n.text("notch.row.waiting", zh: "在等你"))
            case .running?: return join(name, WSL10n.text("notch.row.running", zh: "在跑"))
            case .quota?:
                let running = WSL10n.text("notch.row.running", zh: "在跑")
                let withEar = cell.earText.flatMap { $0.isEmpty ? nil : WSL10n.text("notch.row.runningWithEar", zh: "在跑，%@", $0) }
                return join(name, withEar ?? running)
            case .quotaLow?: return join(name, WSL10n.text("notch.row.runningQuotaLow", zh: "在跑，额度快用完了"))
            case .done?: return join(name, clipped(cell.subtitle))
            case nil: return name
            }
        case .music:
            return join(name, cell.isPaused ? WSL10n.text("say.paused", zh: "已暂停")
                                             : WSL10n.text("notch.row.playing", zh: "正在播放"))
        default:
            return join(name, clipped(cell.subtitle))
        }
    }

    private static func clipped(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return NotchSentence.truncateTail(trimmed, limit: NotchSentence.detailLimit)
    }

    private static func join(_ head: String, _ tail: String) -> String {
        switch (head.isEmpty, tail.isEmpty) {
        case (true, true): return ""
        case (true, false): return tail
        case (false, true): return head
        case (false, false): return "\(head)" + WSL10n.text("notch.join", zh: "，") + "\(tail)"
        }
    }
}

// MARK: - 在那一排里打字筛选（LA-7）
//
// 规则来自 docs/design-drafts/实时活动晋级.html“四 · 找东西更快”。只找自己的：收着的窗口（标题、App 名）和正在进行的事
// （标题、种类名）；不找别的 App 的菜单栏图标、菜单、文件。拼音首字母也算（“zh”找到“周会”）。
// 这里只有字符串规则，不碰 AppKit、不读任何东西；输入的字由宿主从按键里拿，格子由宿主给。

enum NotchRowFilter {
    /// 筛选字最多多长：再长没有意义，也免得一直按着一个键撑爆。
    static let maxQueryLength = 24
    /// 一格也没有时写的话。
    static var noMatchText: String { WSL10n.text("notch.row.noMatch", zh: "没有匹配的") }
    /// 一格也没有时，那一排至少排几格宽（稿：不窄于两格）。
    static let emptyMinimumCells = 2
    /// 一格也没有时岛的宽度（含两边的边距）。
    static var emptyIslandWidth: Double {
        NotchRow.layout(windows: emptyMinimumCells, ongoing: 0).islandWidth(minimum: 0)
    }

    /// 去掉首尾空白、统一大小写和全半角。空串表示没有筛选。
    static func normalize(_ text: String) -> String {
        let folded = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return folded.lowercased()
    }

    /// 读屏念的话：剩几项；一项也没有就是“没有匹配的”。
    static func remainingAnnouncement(count: Int) -> String {
        count > 0 ? WSL10n.text("notch.row.remaining", zh: "剩 %@ 项", String(count)) : noMatchText
    }

    /// 汉字是不是要转拼音（基本区、扩展 A、兼容区）。
    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value)
    }

    /// 一段文字的拼音首字母串：汉字取系统转出来的拼音第一个字母，字母数字原样（小写），其余（空格、标点）略过。
    /// “周会”→“zh”，“Safari 浏览器”→“safarillq”。多音字取系统给的第一个读音。
    static func initials(of text: String) -> String {
        var cache: [Character: String] = [:]
        var out = ""
        for character in text {
            if let first = character.unicodeScalars.first, isHan(first) {
                if let known = cache[character] { out += known; continue }
                let latin = String(character).applyingTransform(.mandarinToLatin, reverse: false)?
                    .applyingTransform(.stripDiacritics, reverse: false) ?? ""
                let initial = latin.first(where: { $0.isLetter }).map { String($0).lowercased() } ?? ""
                cache[character] = initial
                out += initial
            } else if character.isLetter || character.isNumber {
                out += String(character).lowercased()
            }
        }
        return out
    }

    /// 这一段文字对不对得上筛选字：字面包含（不分大小写），或者拼音首字母串包含。空的筛选字什么都对得上。
    static func matches(query: String, text: String) -> Bool {
        let q = normalize(query)
        guard !q.isEmpty else { return true }
        let t = normalize(text)
        if t.contains(q) { return true }
        let letters = String(q.filter { $0.isLetter || $0.isNumber })
        return !letters.isEmpty && initials(of: text).contains(letters)
    }

    /// 一格的所有可找字段里有一个对得上就算。`terms` 是格子自己给的（窗口的 App 名、活动的种类名）。
    static func matches(query: String, title: String, terms: [String]) -> Bool {
        guard !normalize(query).isEmpty else { return true }
        return ([title] + terms).contains { !$0.isEmpty && matches(query: query, text: $0) }
    }

    /// 刘海左边那一段放不下整串时，留最后几个字（光标在末尾，最新打的那几个字必须看得见），前面用“…”。
    static func visibleTail(of query: String, limit: Int) -> String {
        guard limit > 1, query.count > limit else { return query }
        return "…" + String(query.suffix(limit - 1))
    }

    /// 打字时能放进筛选字的字符：可打印的，不含控制字符、方向键一类功能键（它们落在私用区）。
    static func isTypable(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
                && !(0x80...0x9F).contains(scalar.value)
        }
    }

    /// 活动种类的名字（筛选用，也是用户平时的叫法）。
    static func kindName(_ kind: NotchActivityKind) -> String {
        switch kind {
        case .music: return WSL10n.text("notch.kind.music", zh: "音乐")
        case .airPods: return WSL10n.text("notch.kind.airPods", zh: "耳机")
        case .airDrop: return WSL10n.text("silent.activity.airdrop", zh: "隔空投送")
        case .route: return WSL10n.text("silent.activity.route", zh: "路线")
        case .recording: return WSL10n.text("silent.activity.recording", zh: "录音")
        case .focus: return WSL10n.text("settings.shade.focus.name", zh: "番茄钟")
        case .download: return WSL10n.text("notch.kind.download", zh: "下载")
        case .copy: return WSL10n.text("habit.fallback.copy", zh: "拷贝")
        case .remote: return WSL10n.text("settings.section.remote", zh: "遥控器")
        case .session: return WSL10n.text("notch.kind.session", zh: "编程会话")
        case .calendar: return WSL10n.text("settings.shade.calendar.name", zh: "日程")
        case .timer: return WSL10n.text("notch.kind.timer", zh: "计时器")
        case .shelf: return WSL10n.text("settings.shade.fileShelf.name", zh: "文件架")
        }
    }
}

// MARK: - 文件架（FS-04）：那一排右段的末格，以及文件架卡的纯逻辑
//
// 画面在 App/FileShelfView.swift；这里只有数字、句子和选择规则，不碰 AppKit，所以能单测。
// 规则来自 docs/design-drafts/文件架.html 的“一排里”“文件架卡”“一格能做的”“全部移出”。

extension NotchRow {
    /// 文件架在格子编号表里的活动号（和别的活动 id 不会撞）。
    static let fileShelfActivityID = "fileShelf"
    static let fileShelfSymbol = "tray.full"

    /// 一排右段的末格：叠三张缩略图，下面写“文件架 · 6”。空着或关着时这一格不在。
    struct FileShelfCell: Equatable, Sendable {
        let count: Int
        var title: String { WSL10n.text("notch.shelf.cellTitle", zh: "文件架 · %@", String(count)) }
        /// 叠几张缩略图：最多三张。
        var stacked: Int { min(3, count) }
        var spoken: String { WSL10n.text("notch.shelf.cellSpoken", zh: "文件架，%@ 个", String(count)) }
    }

    static func fileShelfCell(count: Int, enabled: Bool) -> FileShelfCell? {
        enabled && count > 0 ? FileShelfCell(count: count) : nil
    }
}

/// 文件架卡的尺寸与时间（稿里的数字，不凭感觉改）。
enum FileShelfCardLayout {
    static let width = 560.0
    static let height = 160.0
    static let radius = 28.0
    /// 稿里的示意机型（MacBook Air 15 英寸）刘海高度；卡里的格子从刘海下沿再空 8 点开始。
    static let referenceStrip = 33.5
    static let margin = 14.0
    static let tileTopGap = 8.0
    static let tileWidth = 76.0
    static let tileHeight = 104.0
    static let tileGap = 8.0
    static let tileRadius = 14.0
    static let thumbnail = 52.0
    static let thumbnailRadius = 12.0
    static let nameFont = 11.0
    static let nameWidth = 68.0
    static let closeDiameter = 16.0
    /// 指针离开岛以后多久 calm 收回。
    static let leaveDelay = 0.3
    /// 全部移出以后撤销的时间。
    static let clearHold = 5.0
    /// 右耳说明文字（“1 个找不到了”）停多久。
    static let noticeHold = 3.0

    /// 真刘海：耳朵在刘海那一条里，岛 = 刘海 + 这一块；没有刘海：整张卡都在视图里。
    static func contentHeight(hasNotch: Bool) -> Double {
        hasNotch ? height - referenceStrip : height
    }
    /// 视图里从上到下，格子的上沿（真刘海时视图在刘海下面，所以只剩那 8 点）。
    static func tilesTop(hasNotch: Bool, strip: Double = referenceStrip) -> Double {
        hasNotch ? tileTopGap : strip + tileTopGap
    }
    /// 第 index 格的左边缘（最新的在最左）。
    static func tileX(_ index: Int) -> Double { margin + Double(max(0, index)) * (tileWidth + tileGap) }
    /// 所有格子排开有多宽（含两边的边距）。
    static func documentWidth(count: Int) -> Double {
        count <= 0 ? width : max(width, 2 * margin + Double(count) * tileWidth + Double(count - 1) * tileGap)
    }
    /// 一屏放几格（含半格）：稿里“一屏放六格半”。
    static var visibleTiles: Double { (width - 2 * margin + tileGap) / (tileWidth + tileGap) }
    /// 键盘选到第 index 格时，横向滚动到哪里才看得全它（原位置够用就不动）。
    static func scrollOffset(toReveal index: Int, current: Double, viewport: Double = width) -> Double {
        let left = tileX(index) - margin
        let right = tileX(index) + tileWidth + margin
        if left < current { return max(0, left) }
        if right > current + viewport { return right - viewport }
        return current
    }
}

/// 格子上的名字：最多两行，中间省略，保留扩展名；读屏念全名。
enum FileShelfTileName {
    /// 一行大约放 12 个西文字符或 6 个汉字；两行一共 24 个“字宽”。
    static let units = 22
    static let staleUnits = 10

    static func width(of c: Character) -> Int { c.unicodeScalars.contains { $0.value >= 0x2E80 } ? 2 : 1 }
    static func width(of s: String) -> Int { s.reduce(0) { $0 + width(of: $1) } }

    static func display(_ name: String, units limit: Int = units) -> String {
        guard width(of: name) > limit else { return name }
        let dot = name.lastIndex(of: ".")
        var ext = "", base = name
        if let dot, dot != name.startIndex, name.distance(from: dot, to: name.endIndex) <= 6 {
            ext = String(name[dot...]); base = String(name[..<dot])
        }
        let budget = max(2, limit - width(of: ext) - 1)
        let head = Int((Double(budget) * 0.6).rounded(.up)), tail = budget - head
        var h = "", hw = 0
        for c in base { let w = width(of: c); if hw + w > head { break }; h.append(c); hw += w }
        var t = "", tw = 0
        for c in base.reversed() { let w = width(of: c); if tw + w > tail { break }; t.insert(c, at: t.startIndex); tw += w }
        return h + "…" + t + ext
    }

    /// 失效的格：名字只留短短一行，下面写原因。
    static func stale(_ name: String, reason: String) -> String { display(name, units: staleUnits) + "\n" + reason }
}

/// 拖出：默认拷贝，原文件不动、这一格留着；按住 ⌘ 移动（和访达一样），移完这一格离开。
enum FileShelfDrag {
    enum Operation: Equatable, Sendable { case copy, move }
    /// 系统问“你允许对方怎么处理”时的答案。只给一种：这样同一块盘上访达也不会悄悄变成移动。
    static func allowed(command: Bool) -> [Operation] { command ? [.move] : [.copy] }
    /// 拖完以后这一格要不要离开架子：只有真的移动了才走；拷贝、取消、落空都留着。
    static func leavesShelf(after operation: Operation?) -> Bool { operation == .move }
    /// 灰着的格（在废纸篓、硬盘没接上、找不到了）拖不出来，轻轻摇一下。`live`：这一格现在可用。
    static func canDrag(live: Bool) -> Bool { live }
}

/// 全部移出：格子都走，卡上留一句“文件架空了”和“撤销”，5 秒后卡收回。
struct FileShelfClearUndo: Equatable, Sendable {
    private(set) var count = 0
    private(set) var deadline: Double?
    static var line: String { WSL10n.text("notch.shelf.empty", zh: "文件架空了") }
    static var undoTitle: String { WSL10n.text("menu.undo", zh: "撤销") }

    mutating func begin(count: Int, now: Double) {
        guard count > 0 else { return }
        self.count = count
        deadline = now + FileShelfCardLayout.clearHold
    }
    func isPending(at now: Double) -> Bool { deadline.map { now < $0 } ?? false }
    /// 撤销：时间内才算，成功返回回来的个数。
    mutating func undo(at now: Double) -> Int? {
        guard isPending(at: now) else { return nil }
        let back = count
        self = FileShelfClearUndo()
        return back
    }
    /// 时间到了：清掉记录，调用方收卡。
    mutating func expire(at now: Double) -> Bool {
        guard let deadline, now >= deadline else { return false }
        self = FileShelfClearUndo()
        return true
    }
    mutating func cancel() { self = FileShelfClearUndo() }
}

/// 右键菜单与读屏动作：同一份清单，两边说的话一样。
enum FileShelfActions {
    enum Action: Equatable, Sendable { case preview, open, openWith, reveal, airDrop, remove }
    struct Item: Equatable, Sendable {
        let action: Action
        let title: String
        let enabled: Bool
    }

    static var previewTitle: String { WSL10n.text("notch.shelf.preview", zh: "大图预览") }
    static var removeTitle: String { WSL10n.text("notch.shelf.remove", zh: "移出文件架") }
    static var airDropTitle: String { WSL10n.text("silent.activity.airdrop", zh: "隔空投送") }

    /// 右键：打开、用哪个 App 打开、在访达中显示、隔空投送、移出文件架。
    /// 灰着的格只能移出；叠放的一格不能“用哪个 App 打开”（里面不是同一种东西）。
    static func menu(isStack: Bool, live: Bool) -> [Item] {
        [
            Item(action: .open, title: WSL10n.text("notch.shelf.open", zh: "打开"), enabled: live),
            Item(action: .openWith, title: WSL10n.text("notch.shelf.openWith", zh: "用哪个 App 打开"), enabled: live && !isStack),
            Item(action: .reveal, title: WSL10n.text("settings.privacy.showInFinder", zh: "在访达中显示"), enabled: live),
            Item(action: .airDrop, title: airDropTitle, enabled: live),
            Item(action: .remove, title: removeTitle, enabled: true),
        ]
    }

    /// 读屏念的动作：大图预览、移出文件架、隔空投送（灰着的格只有移出）。
    static func spokenActions(live: Bool) -> [Item] {
        (live ? [Item(action: .preview, title: previewTitle, enabled: true)] : [])
            + (live ? [Item(action: .airDrop, title: airDropTitle, enabled: true)] : [])
            + [Item(action: .remove, title: removeTitle, enabled: true)]
    }

    /// 每格念“报价单.pdf，文件架”；灰着的写上原因（`reason` 是格子上写的那句，可用时没有）。
    static func spoken(name: String, reason: String?) -> String {
        [name, reason, WSL10n.text("settings.shade.fileShelf.name", zh: "文件架")].compactMap { $0 }
            .joined(separator: WSL10n.text("notch.join", zh: "，"))
    }

    static func cardSpoken(count: Int) -> String {
        count > 0 ? WSL10n.text("notch.shelf.cellSpoken", zh: "文件架，%@ 个", String(count)) : line
    }
    private static var line: String { WSL10n.text("notch.shelf.empty", zh: "文件架空了") }
    static func removedSpoken(_ name: String) -> String { WSL10n.text("notch.shelf.removed", zh: "已移出文件架，%@", name) }
    /// 移出后念的一句。`name` 为 nil（屏幕正在共享，真文件名不念）或一次移出多个时只念个数。
    static func removedSpoken(name: String?, count: Int) -> String {
        if count == 1, let name { return removedSpoken(name) }
        return WSL10n.text("notch.shelf.removedCount", zh: "已移出文件架，%@ 个", String(count))
    }
}

// MARK: - 卷轴概览与刘海互通（SS-04）：左段多出停在屏幕外的卷轴列，左段的格子能拖出来
//
// 落点、放回的规则在 Core/StripNotchExchange.swift；这里只有左段怎么分和哪些格子能拖出来。

extension NotchRow {
    /// 左段放什么：收着的窗口排前面，停在屏幕外的卷轴列排它们后面；总数不超过左段上限。
    /// 只在这一排展开时才有卷轴列的格子；紧凑的两耳不画卷轴。
    static func leftSegment(tucked: Int, parked: Int, expanded: Bool) -> (tucked: Int, parked: Int) {
        let t = min(max(0, tucked), windowLimit)
        guard expanded else { return (t, 0) }
        return (t, min(max(0, parked), windowLimit - t))
    }

    /// 左段的一格能不能拖出来放回卷轴：只有收着的窗口能；右段正在进行的事和停在屏幕外的卷轴列（点一下是滑进来）都不能。
    static func canDragOut(cellID: UInt32, parkedCellIDs: Set<UInt32>) -> Bool {
        !isOngoingID(cellID) && !parkedCellIDs.contains(cellID)
    }
}
