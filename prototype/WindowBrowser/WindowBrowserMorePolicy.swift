// 窗口浏览 9/28 补上的四件事里能单独测的纯逻辑：
// - 新建窗口：从 App 菜单里挑哪一项（标题得是“新建窗口”一类），挑不到就不按、不发按键；
// - 关窗时卡片退场：哪些移出该做动画、做多久、缩到多大；
// - 把卡片拖出面板：指针贴着屏幕哪条边、松手去哪儿（左半屏 / 右半屏 / 铺满屏幕 / 侧拉）；
// - 辅助进程归到它的 App 名下（微信的小程序窗口归微信）。
//
// 这里不碰 AX、NSWorkspace、NSScreen，输入都是值，便于直接测试。

import Foundation
import CoreGraphics
import QuartzCore

// MARK: - 新建窗口

enum WindowBrowserNewWindowCommand {
    /// 菜单栏里读到的一项（只留挑选要用的几个属性）。
    struct Candidate: Equatable {
        /// 在菜单栏里是第几个菜单（0 是苹果菜单，1 是 App 菜单，2 通常是“文件”）。
        let menuIndex: Int
        let itemIndex: Int
        /// “新建窗口 ▸”这类子菜单里的第几项（终端、带个人资料的 Safari）；顶层菜单里的项为 nil。
        var subItemIndex: Int? = nil
        let title: String
        /// 子菜单里的项：它所在那个子菜单的标题（“新建窗口”）。
        var parentTitle: String? = nil
        let commandCharacter: String?
        /// kAXMenuItemCmdModifiersAttribute：0 表示只按 ⌘；读不到按 0 算（系统的默认值）。
        /// 其余是位标记：1 ⇧、2 ⌥、4 ⌃、8 不带 ⌘。
        let commandModifiers: Int?
        let enabled: Bool
        /// 这一项自己带子菜单：按下它只会展开子菜单，不会新建窗口。
        var hasSubmenu: Bool = false

        var path: ItemPath { ItemPath(menuIndex: menuIndex, itemIndex: itemIndex, subItemIndex: subItemIndex) }
    }

    struct ItemPath: Hashable {
        let menuIndex: Int
        let itemIndex: Int
        let subItemIndex: Int?
    }

    enum Plan: Equatable {
        /// 按下这一项（菜单的 AXPress）。
        case press(ItemPath)
        /// 找到了新建窗口，但现在是灰的。
        case disabled
        /// 菜单读得到，里面没有新建窗口：不按别的，也不发按键。
        /// 标题不像“新建窗口”的 ⌘N 也算没有：日历、提醒事项、备忘录、通讯录的 ⌘N 会新建日程、提醒、备忘录、名片。
        case noCommand
        /// 菜单根本读不到（App 没响应、没有菜单栏）：不猜，不给它发按键。
        case unreadable
    }

    enum TitleKind: Equatable {
        /// 标题说的就是新开一扇窗：“新建窗口”“新建访达窗口”“打开新的窗口”“New Window”。
        case newWindow
        /// 文稿类 App 的“新建 / New”：新建一份文稿就是新开一扇窗。
        case newDocument
        case other
    }

    /// 只带 ⌘ 的 N。⇧⌘N（新建无痕窗口、新建文件夹）不算。
    static func isNewWindowShortcut(character: String?, modifiers: Int?) -> Bool {
        guard let character, character.uppercased() == "N" else { return false }
        return (modifiers ?? 0) == 0
    }

    // 标题里有这些就不是“新开一扇普通窗口”：无痕 / 隐私窗口，把标签页移到新窗口，重新打开关掉的窗口。
    private static let excludedWords: Set<String> = [
        "incognito", "inprivate", "move", "merge", "tab", "tabs", "reopen", "restore"
    ]
    private static let excludedFragments = [
        "无痕", "隐私", "隱私", "私密", "私人", "移到", "移至", "移动", "移動", "合并", "合併",
        "标签", "標籤", "分頁", "重新", "恢复", "恢復", "还原", "還原", "复原", "復原",
        "プライベート", "シークレット", "タブ"
    ]
    /// 拼音文字按词比对“新 + 窗口”；中日文按片段比对。
    private static let wordPairs: [(String, String)] = [
        ("new", "window"), ("neues", "fenster"), ("nouvelle", "fenêtre"), ("nueva", "ventana"),
        ("nuova", "finestra"), ("nova", "janela"), ("새", "창"), ("새", "윈도우")
    ]
    private static let newFragments = ["新建", "新增", "新的", "新窗口", "新視窗", "新视窗", "新規", "新しい"]
    private static let windowFragments = ["窗口", "視窗", "视窗", "ウインドウ", "ウィンドウ"]
    /// 文稿类 App 的“新建”只认这几种原样的标题（不认“新建备忘录”“新建事件”这类）。
    private static let genericNewTitles: Set<String> = [
        "new", "new document", "新建", "新建文稿", "新建文档", "新文稿", "新規", "新規書類",
        "neu", "nouveau", "nuevo"
    ]

    static func titleKind(_ title: String) -> TitleKind {
        let lowered = title.lowercased()
        let words = Set(lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        if isExcluded(lowered: lowered, words: words) { return .other }
        if wordPairs.contains(where: { words.contains($0.0) && words.contains($0.1) }) { return .newWindow }
        if newFragments.contains(where: lowered.contains),
           windowFragments.contains(where: lowered.contains) { return .newWindow }
        var trimmed = lowered.trimmingCharacters(in: .whitespacesAndNewlines)
        for ellipsis in ["…", "..."] where trimmed.hasSuffix(ellipsis) {
            trimmed = String(trimmed.dropLast(ellipsis.count)).trimmingCharacters(in: .whitespaces)
        }
        return genericNewTitles.contains(trimmed) ? .newDocument : .other
    }

    private static func isExcluded(lowered: String, words: Set<String>) -> Bool {
        // private / privée / privates / privada / privata……都以 priv 开头。
        if words.contains(where: { $0.hasPrefix("priv") }) { return true }
        if !words.isDisjoint(with: excludedWords) { return true }
        return excludedFragments.contains(where: lowered.contains)
    }

    /// 标题说的是新建窗口：顶层菜单里标题像“新建窗口”的项，或者“新建窗口 ▸”子菜单里只带 ⌘ 的 N 那一项。
    static func isNewWindowItem(_ item: Candidate) -> Bool {
        guard !item.hasSubmenu else { return false }
        guard item.subItemIndex != nil else { return titleKind(item.title) == .newWindow }
        guard let parent = item.parentTitle, titleKind(parent) == .newWindow else { return false }
        let lowered = item.title.lowercased()
        let words = Set(lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return !isExcluded(lowered: lowered, words: words)
            && isNewWindowShortcut(character: item.commandCharacter, modifiers: item.commandModifiers)
    }

    /// 文稿类 App 的“新建”：标题就是“新建 / New”，快捷键是只带 ⌘ 的 N。
    static func isNewDocumentItem(_ item: Candidate) -> Bool {
        !item.hasSubmenu && item.subItemIndex == nil && titleKind(item.title) == .newDocument
            && isNewWindowShortcut(character: item.commandCharacter, modifiers: item.commandModifiers)
    }

    /// 快捷键越像“新建窗口”越靠前：只带 ⌘ 的 N，其次别的 N（⌥⌘N、⇧⌘N），再次别的快捷键，最后没有快捷键的。
    static func shortcutRank(_ item: Candidate) -> Int {
        if isNewWindowShortcut(character: item.commandCharacter, modifiers: item.commandModifiers) { return 0 }
        guard let character = item.commandCharacter, !character.isEmpty else { return 3 }
        return character.uppercased() == "N" ? 1 : 2
    }

    /// 先看快捷键，再看菜单（“文件”下标 2 排最前），再看菜单里的顺序。
    private static func precedes(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        let lr = shortcutRank(lhs), rr = shortcutRank(rhs)
        if lr != rr { return lr < rr }
        let l = lhs.menuIndex == 2 ? -1 : lhs.menuIndex
        let r = rhs.menuIndex == 2 ? -1 : rhs.menuIndex
        if l != r { return l < r }
        if lhs.itemIndex != rhs.itemIndex { return lhs.itemIndex < rhs.itemIndex }
        return (lhs.subItemIndex ?? -1) < (rhs.subItemIndex ?? -1)
    }

    /// 先找标题说“新建窗口”的项，没有可用的再找文稿类 App 的“新建”（⌘N）。
    /// 标题不像这两种的 ⌘N 一律不按。
    static func plan(menuReadable: Bool, candidates: [Candidate]) -> Plan {
        guard menuReadable else { return .unreadable }
        let usable = candidates.filter { $0.menuIndex > 0 }
        let tiers = [usable.filter(isNewWindowItem), usable.filter(isNewDocumentItem)]
        for tier in tiers {
            if let chosen = tier.sorted(by: precedes).first(where: \.enabled) {
                return .press(chosen.path)
            }
        }
        return tiers.contains(where: { !$0.isEmpty }) ? .disabled : .noCommand
    }

    /// 读菜单时可以提前停下：已经有一项可用、快捷键就是 ⌘N 的“新建窗口”（后面的菜单不会比它更合适）。
    static func isSettled(_ candidates: [Candidate]) -> Bool {
        candidates.contains { $0.menuIndex > 0 && $0.enabled && isNewWindowItem($0) && shortcutRank($0) == 0 }
    }

    /// 这一项值不值得记下来交给 plan：标题像新建窗口 / 新建文稿、或快捷键是 N、或是子菜单里的项。
    static func isWorthKeeping(_ item: Candidate) -> Bool {
        item.subItemIndex != nil || titleKind(item.title) != .other
            || item.commandCharacter?.uppercased() == "N"
    }

    /// 新窗口有没有出来：之后的窗口号里出现了之前没有的。
    static func appeared(before: Set<CGWindowID>, after: Set<CGWindowID>) -> Bool {
        !after.subtracting(before).isEmpty
    }
}

// MARK: - 关窗时卡片退场

enum WindowBrowserDepartureMotion {
    /// 卡片缩小淡出的时长（≤ 200 ms，与 iPadOS 关掉一张卡片的节奏相近）。
    static let duration: TimeInterval = 0.16
    /// 开启“减少动态效果”时：不缩放、不让其余卡片滑动，整块列表 0.12 秒交叉淡化。
    static let reducedDuration: TimeInterval = 0.12
    /// 退场时缩到原来的多大。
    static let scale: CGFloat = 0.88
    /// 标记为“刚关掉”的窗口多久内移出列表才算数；过期的标记不再触发动画。
    static let markLifetime: TimeInterval = 3

    /// 这次列表变化该不该给移出的卡片做退场：只有纯移出、且移出的全是刚关掉的窗口。
    /// 搜索过滤、换应用、换显示方式造成的移出一律照旧立即更新。
    static func shouldAnimate(removed: [WindowKey], insertedCount: Int,
                              departing: Set<WindowKey>, styleChanged: Bool) -> Bool {
        guard !styleChanged, insertedCount == 0, !removed.isEmpty else { return false }
        return removed.allSatisfy { departing.contains($0) }
    }

    static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedDuration : duration
    }

    /// 以图层中心为基点缩放（图层的 anchorPoint 不一定在中心：AppKit 管的图层常在左下角）。
    static func centeredScale(_ scale: CGFloat, size: CGSize, anchor: CGPoint) -> CATransform3D {
        let dx = (0.5 - anchor.x) * size.width
        let dy = (0.5 - anchor.y) * size.height
        var transform = CATransform3DMakeTranslation(dx, dy, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -dx, -dy, 0)
    }

    /// 清掉过期的标记，只留仍在列表里、还没过期的。
    static func liveMarks(_ marks: [WindowKey: CFTimeInterval], now: CFTimeInterval,
                          listed: Set<WindowKey>) -> [WindowKey: CFTimeInterval] {
        marks.filter { listed.contains($0.key) && now - $0.value <= markLifetime }
    }
}

// MARK: - 把卡片拖出面板

/// 卡片拖出面板后松手的去处。
enum WindowBrowserDropZone: Equatable {
    case leftHalf
    case rightHalf
    case fill
    /// 屏幕左右边上那一小块（和拖标题栏进侧拉是同一块，要停一下才算数）。
    case slideOver

    var placementAction: WindowPlacementAction? {
        switch self {
        case .leftHalf: return .leftHalf
        case .rightHalf: return .rightHalf
        case .fill: return .fill
        case .slideOver: return nil
        }
    }
}

enum WindowBrowserCardDragPolicy {
    /// 指针离按下点多远、而且已经出了面板，才算“拖出去排布”；面板里面拖动仍是原来的“拖出取消”。
    static let startDistance: CGFloat = 12
    /// 面板四周这么宽也算面板：出了这一圈才从“拖出取消”换成“拖去排布”。
    static let panelSlop: CGFloat = 12
    /// 面板四周这么宽是取消带：按原来的习惯把卡片拖出面板松手，仍然什么都不做。
    /// 面板贴着 Dock，可能正好挨着屏幕左右边（Dock 在侧边、或停在靠边的图标上）。
    static let cancelBand: CGFloat = 80
    /// 指针离可用区域的左右边、顶边这么近才算落点（和拖窗口到屏幕边上排布一样，要贴边）。
    static let edgeBand: CGFloat = 40

    static func shouldBegin(down: CGPoint, pointer: CGPoint, panelFrame: CGRect) -> Bool {
        guard hypot(pointer.x - down.x, pointer.y - down.y) >= startDistance else { return false }
        return !panelFrame.insetBy(dx: -panelSlop, dy: -panelSlop).contains(pointer)
    }

    /// 指针所在位置对应的落点（Cocoa 坐标，y 向上）。
    /// - 离面板不到一条取消带、落在 Dock 那一侧（可用区域以外）、或没贴着屏幕边：没有落点，松手就是取消；
    /// - 屏幕左右边上的侧拉那一块由调用方判定（`slideOverEdgeHit`，要停够才算），优先于半屏；
    /// - 贴着左边 / 右边：左半屏 / 右半屏；贴着顶边（含菜单栏）：铺满屏幕。
    static func zone(pointer: CGPoint, screenFrame: CGRect, visibleFrame: CGRect,
                     panelFrame: CGRect?, slideOverEdgeHit: Bool) -> WindowBrowserDropZone? {
        if let panelFrame, panelFrame.insetBy(dx: -cancelBand, dy: -cancelBand).contains(pointer) {
            return nil
        }
        // 可用区域向上延到屏幕顶（菜单栏也算“顶上”）；Dock 所在的底边 / 侧边不算。
        let area = CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: visibleFrame.width,
                          height: max(visibleFrame.height, screenFrame.maxY - visibleFrame.minY))
        guard area.width > edgeBand * 4, area.height > edgeBand * 4, area.contains(pointer) else { return nil }
        if slideOverEdgeHit { return .slideOver }
        if pointer.x <= visibleFrame.minX + edgeBand { return .leftHalf }
        if pointer.x >= visibleFrame.maxX - edgeBand { return .rightHalf }
        if pointer.y >= visibleFrame.maxY - edgeBand { return .fill }
        return nil
    }
}

// MARK: - 辅助进程归到它的 App 名下

/// 一个在跑的进程（只留判断要用的几个值；调用方在主线程从 NSWorkspace 取好）。
struct WindowBrowserAppProcess: Equatable {
    let pid: pid_t
    let bundleIdentifier: String?
    /// 已规范化的 .app 路径（standardized + 解析过符号链接）。
    let bundlePath: String?
    /// 在 Dock 里有自己的图标（activationPolicy == .regular）。
    let hasDockIcon: Bool
    let name: String
}

enum WindowBrowserHelperApps {
    /// 反向域名的前两段（com.tencent.xinWeChat → com.tencent）。少于三段的不算。
    static func vendorPrefix(_ bundleIdentifier: String?) -> String? {
        guard let parts = bundleIdentifier?.lowercased().split(separator: "."),
              parts.count >= 3 else { return nil }
        return "\(parts[0]).\(parts[1])"
    }

    /// helper 是不是 parent 自己带的辅助进程：
    /// - parent 在 Dock 里有图标，helper 没有（有自己图标的进程，窗口归它自己的图标）；
    /// - helper 的 .app 就装在 parent 的 .app/Contents/ 里面（签名封装在同一个包里）；
    /// - 两者的 bundle ID 属于同一家（前两段相同）。
    /// 微信的小程序窗口属于 WeChatAppEx（com.tencent.flue.WeChatAppEx，装在
    /// WeChat.app/Contents/MacOS/ 里，LSUIElement，没有 Dock 图标），按这条归到微信名下。
    static func isHelper(_ helper: WindowBrowserAppProcess,
                         of parent: WindowBrowserAppProcess) -> Bool {
        guard helper.pid != parent.pid, parent.hasDockIcon, !helper.hasDockIcon else { return false }
        guard let parentPath = trimmed(parent.bundlePath), parentPath.hasSuffix(".app"),
              let helperPath = trimmed(helper.bundlePath) else { return false }
        guard helperPath.hasPrefix(parentPath + "/Contents/") else { return false }
        guard let a = vendorPrefix(parent.bundleIdentifier),
              let b = vendorPrefix(helper.bundleIdentifier), a == b else { return false }
        return true
    }

    /// 每个辅助进程对应的 App（有 Dock 图标的那个）。嵌套时取路径最长的那一层。
    static func parentsByHelper(_ processes: [WindowBrowserAppProcess])
        -> [pid_t: WindowBrowserAppProcess] {
        let parents = processes.filter(\.hasDockIcon)
        var result: [pid_t: WindowBrowserAppProcess] = [:]
        for helper in processes where !helper.hasDockIcon {
            let owners = parents.filter { isHelper(helper, of: $0) }
            if let best = owners.max(by: { ($0.bundlePath?.count ?? 0) < ($1.bundlePath?.count ?? 0) }) {
                result[helper.pid] = best
            }
        }
        return result
    }

    static func helperPIDs(of parentPID: pid_t,
                           in map: [pid_t: WindowBrowserAppProcess]) -> Set<pid_t> {
        Set(map.filter { $0.value.pid == parentPID }.map(\.key))
    }

    /// 辅助进程有没有普通层（layer 0）的窗口。Chrome、Electron 的 Helper 也装在 App 包里、
    /// 没有 Dock 图标，同样会被归到它们的 App 名下，但它们没有自己的窗口：没有普通窗口的
    /// 辅助进程不去问 AX（问了也是空的，碰上不响应的还要等到超时）。
    /// windows 是这个进程在 WindowServer 里的窗口（CGWindowList 的字典）。
    static func hasLayerZeroWindow(_ windows: [[String: Any]]) -> Bool {
        windows.contains { ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 }
    }

    private static func trimmed(_ path: String?) -> String? {
        guard var path, !path.isEmpty else { return nil }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
