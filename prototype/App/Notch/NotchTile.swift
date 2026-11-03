// // 刘海那一排里的一格的模型：哪扇窗、什么形态、画面与标题。

import Cocoa
import ApplicationServices

struct NotchTile {
    enum Kind {
        case tucked, strip, thumbnail, slideOver, carried, minimized, hiddenApp, elsewhere
        /// 竖线右边正在进行的格（M11）：编程会话、正在播放的、其它正在进行的事。
        case session, playing, activity
        /// 卷轴停在屏幕外的一列（SS-04）：左段收着的窗口后面，角上 ← 或 →，点一下把那一列滑进来。
        case parked
        /// 最前面「离开期间」的格子（回来后那一阵才有，Core/AwaySummary 的 AwayList）。
        case away

        var isOngoing: Bool {
            switch self {
            case .session, .playing, .activity: return true
            case .tucked, .strip, .thumbnail, .slideOver, .carried, .minimized, .hiddenApp, .elsewhere, .parked, .away: return false
            }
        }
        var isAway: Bool { self == .away }
    }

    /// 离开期间的一格：内容、此刻能不能点、读屏念什么。`item` 是 nil 的是窄格「还有 N 件」。
    struct AwayCell: Equatable {
        var item: AwaySummary.Item?
        var omitted: Int
        var state: AwaySummary.CellState
        var spoken: String
        var help: String
        /// 格子上写的字：名字、大号数字、副句、底部动词（没有动词就是不能点），以及一个符号名（没有 App 图标时画它）。
        var title = ""
        var big: String? = nil
        var subtitle = ""
        var verb: String? = nil
        var symbol: String? = nil
        var isNarrow: Bool { item == nil }
        var isGone: Bool { state == .gone }
        var isActionable: Bool { if case .actionable = state { return true } else { return false } }
    }
    let id: CGWindowID
    let kind: Kind
    /// 格子上的画面。最小化、隐藏、别的桌面、侧拉的格子起初没有，后台截到后原地换上（NotchPanel.updateTileSnapshot）。
    var snapshot: CGImage?
    let icon: NSImage?
    var title: String
    var changed: Bool = false
    /// 别的桌面上的窗口：左上角写它在哪（“桌面 3”“全屏”）。
    var place: String? = nil
    /// 状态为“等你”的会话格：键盘焦点默认落在它上面（M07）。
    var waiting: Bool = false
    /// 正在进行的格（竖线右边）才有的内容。
    var ongoing: Ongoing? = nil
    /// 在那一排里打字筛选（LA-7）时，除标题以外还找的字：窗口格是 App 名，正在进行的格是种类名。
    /// 屏幕正在共享而被遮住的格不给（和标题一样不露）。
    var searchTerms: [String] = []
    /// 卷轴停在屏幕外的列才有（kind == .parked）。
    var parked: StripNotchExchange.ParkedCell? = nil
    /// 离开期间的格子才有（kind == .away）。
    var away: AwayCell? = nil

    struct Ongoing: Equatable {
        var activityID: String
        var subtitle: String
        var symbol: String
        var phase: NotchSessionPhase?
        var isPaused: Bool
        /// 这件事的量（M12）和它写出来的字（“42%”“第 2 / 9”）：和紧凑右耳同一套画法。
        var quantity: NotchActivity.Quantity = .unknown
        var quantityText: String? = nil
        /// 读屏念的整句（“项目，在等你”）。
        var spoken: String
        /// 点一下做什么，以及做完要不要收起这一排。
        var action: NotchActivityAction
        var closesRow: Bool
        /// 格子右下角的小键（音乐的播放 / 暂停，NP-4）：点它只做这件事，这一排留着。
        var accessory: NotchActivityAction? = nil
        /// 文件架这一格（FS-04）：叠几张缩略图；其它格是 nil。`shelfRevision` 变了说明缩略图换了，要重画。
        var shelfCount: Int? = nil
        var shelfRevision: Int = 0
        /// 过期（格子画 0.5 透明；读屏的整句里已有“可能已停”）和结束（最后的样子，没有能点的动作）。
        var isStale = false
        var isEnded = false
    }

    /// 屏幕正在共享时的样子：只剩 App 图标，没有画面、没有标题、没有“有变化”的点。
    func iconOnly() -> NotchTile {
        var copy = self
        copy.snapshot = nil
        copy.title = ""
        copy.changed = false
        copy.searchTerms = []
        return copy
    }

    /// 屏幕正在共享时，会话格不露项目名和做了什么：只剩“编程会话”和它的状态（读屏也一样）。
    func sessionRedacted() -> NotchTile {
        guard var copy = ongoing else { return self }
        var tile = self
        copy.subtitle = ""
        // 共享时只留会话状态；新加的额度数字不能绕过同一条遮隐路径。
        copy.quantity = .unknown
        copy.quantityText = nil
        let sessionKind = WSL10n.text("notch.kind.session", zh: "编程会话")
        let join = WSL10n.text("notch.join", zh: "，")
        switch copy.phase {
        case .waiting: copy.spoken = sessionKind + join + WSL10n.text("notch.row.waiting", zh: "在等你")
        case .running, .quota: copy.spoken = sessionKind + join + WSL10n.text("notch.row.running", zh: "在跑")
        case .quotaLow: copy.spoken = sessionKind + join + WSL10n.text("notch.row.runningQuotaLow", zh: "在跑，额度快用完了")
        default: copy.spoken = sessionKind
        }
        tile.title = WSL10n.text("notch.kind.session", zh: "编程会话")
        tile.ongoing = copy
        return tile
    }

    /// 内容变没变（比较用，不含画面）。
    var ongoingSignature: String? {
        // 量只记画法：数变了走 NotchPanel.updateOngoingQuantities（只改数字和环的终点），不整排重换。
        ongoing.map { "\($0.activityID)|\(title)|\($0.subtitle)|\($0.symbol)|\($0.phase.map(\.rawValue) ?? "")|\($0.isPaused)|\($0.spoken)|\($0.quantity.drawing)|\($0.shelfCount.map(String.init) ?? "")|\($0.shelfRevision)|\($0.isStale)|\($0.isEnded)" }
    }
}

/// 刘海上的面板：平时和刘海一样大（刘海里没有像素，看不见）；收着窗口时往下长出一截带点的“下巴”；
/// 指针停上来往下展开成一排窗口；拖着标题栏靠近时垂下一块落点小岛。
///
