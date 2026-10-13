// 魔法平铺：一下子把这块屏上的窗口排整齐。这里只做规划（纯逻辑、可单测），执行在 App/MagicTilingRun.swift。
//
// 不是一直开着的自动平铺：排一次，之后窗口照常随手挪；捏合一下整批撤回。
// - 谁当主角：看 App 要多大地方。浏览器、写代码、做设计、剪视频、表格要地方；写作、笔记、PDF、终端是参考；
//   聊天放侧拉。指针下（张开手势）或最前面的那扇加分；本来就占得大的也加一点。
// - 比例自己定：主角和旁边那一列各要多少地方，落到 5:5、6:4、7:3 三档之一；旁边一列太窄就退一档。
//   主角在左还是在右（竖屏：在上还是在下）跟着它现在在哪一边，窗口少挪。
// - 旁边一列最多放得下几扇就放几扇（每扇至少 280 点高、竖屏时至少 360 点宽），多出来的收进刘海。
// - 竖着放的屏幕（高比宽大）上下分：主角一块、下面（或上面）一排参考。

import CoreGraphics
import Foundation

struct MagicWindow: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let bundleID: String?
    /// App 自己写的类别（LSApplicationCategoryType）。
    let category: String?
    /// 现在的外框（AX 坐标，y 向下）。
    let frame: CGRect
    /// 最前面的那扇（键盘焦点在它上面）。
    let focused: Bool
}

struct MagicPlan: Equatable {
    struct Placement: Equatable {
        let id: CGWindowID
        let frame: CGRect
        let role: MagicTiling.Role
    }
    var placements: [Placement] = []
    var slideOver: CGWindowID?
    var tuck: [CGWindowID] = []
    /// 主角占多少（0.5、0.6、0.7）；只有一扇时是 1。
    var share: CGFloat = 1
    var vertical = false
    /// 主角在左（竖屏：在上）。
    var mainLeading = true
}

enum MagicTiling {
    enum Role: Int, Equatable, Comparable {
        case chat = 0, light, reference, wide
        static func < (a: Role, b: Role) -> Bool { a.rawValue < b.rawValue }
    }

    // MARK: 谁要多大地方

    private static let chat: Set<String> = [
        "com.apple.MobileSMS", "com.tencent.xinWeChat", "com.tencent.qq", "com.tencent.WeWorkMac",
        "com.alibaba.DingTalkMac", "com.bytedance.lark.Feishu", "com.electron.lark", "com.bytedance.macos.feishu",
        "ru.keepcoder.Telegram", "org.telegram.desktop", "com.tinyspeck.slackmacgap", "com.hnc.Discord",
        "net.whatsapp.WhatsApp", "desktop.WhatsApp", "org.whispersystems.signal-desktop", "com.microsoft.teams2",
        "com.microsoft.teams", "jp.naver.line.mac", "com.kakao.KakaoTalkMac",
    ]
    private static let wide: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.canary",
        "company.thebrowser.Browser", "company.thebrowser.dia", "org.mozilla.firefox", "com.microsoft.edgemac",
        "com.brave.Browser", "com.kagi.kagimacOS", "app.zen-browser.zen", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
        "com.panic.Nova", "com.sublimetext.4", "com.google.android.studio", "com.figma.Desktop",
        "com.bohemiancoding.sketch3", "com.pixelmatorteam.pixelmator.x", "com.apple.FinalCut",
        "com.blackmagic-design.DaVinciResolve", "com.apple.iMovieApp", "com.apple.logic10", "com.apple.Keynote",
        "com.apple.iWork.Keynote", "com.apple.iWork.Numbers", "com.microsoft.Excel", "com.microsoft.Powerpoint",
        "com.apple.Maps",
    ]
    private static let widePrefixes = ["com.jetbrains.", "com.adobe.", "com.affinity."]
    private static let reference: Set<String> = [
        "com.apple.Notes", "com.apple.iWork.Pages", "com.microsoft.Word", "md.obsidian", "notion.id",
        "net.shinyfrog.bear", "com.ulyssesapp.mac", "pro.writer.mac", "abnerworks.Typora", "com.apple.Preview",
        "com.readdle.PDFExpert-Mac", "com.apple.mail", "com.microsoft.Outlook", "com.apple.Terminal",
        "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "com.apple.TextEdit",
        "com.culturedcode.ThingsMac", "com.apple.freeform", "com.apple.Dictionary", "com.apple.iBooksX",
    ]
    private static let light: Set<String> = [
        "com.apple.finder", "com.apple.iCal", "com.apple.reminders", "com.apple.Music", "com.spotify.client",
        "com.apple.systempreferences", "com.apple.calculator", "com.apple.Photos", "com.apple.podcasts",
        "com.apple.ActivityMonitor", "com.apple.AppStore",
    ]

    static func role(bundleID: String?, category: String?) -> Role {
        if let id = bundleID {
            if chat.contains(id) { return .chat }
            if wide.contains(id) || widePrefixes.contains(where: id.hasPrefix) { return .wide }
            if reference.contains(id) { return .reference }
            if light.contains(id) { return .light }
        }
        switch category ?? "" {
        case "public.app-category.social-networking": return .chat
        case "public.app-category.developer-tools", "public.app-category.graphics-design", "public.app-category.video",
             "public.app-category.photography", "public.app-category.music": return .wide
        case "public.app-category.productivity", "public.app-category.business", "public.app-category.reference",
             "public.app-category.education", "public.app-category.finance", "public.app-category.medical": return .reference
        case "public.app-category.utilities", "public.app-category.lifestyle", "public.app-category.entertainment",
             "public.app-category.news", "public.app-category.weather", "public.app-category.travel": return .light
        default: return .reference
        }
    }

    /// 要多大地方（主角、比例都按它算）。
    static func demand(_ role: Role) -> CGFloat {
        switch role {
        case .wide: return 3
        case .reference: return 2
        case .light: return 1.3
        case .chat: return 1
        }
    }

    // MARK: 比例

    /// 主角占多少：两边要的地方一比，落到 0.5、0.6、0.7 三档；旁边一列（或一排）不到 minSide 就退一档。
    static func share(main: CGFloat, side: CGFloat, extent: CGFloat, minSide: CGFloat) -> CGFloat {
        let raw = main / max(0.01, main + side)
        var share: CGFloat = raw < 0.55 ? 0.5 : raw < 0.65 ? 0.6 : 0.7
        while share > 0.5, extent * (1 - share) < minSide { share -= 0.1 }
        return (share * 10).rounded() / 10
    }

    // MARK: 规划

    /// windows：这块屏上要排的窗口，最前面的在前。area：屏幕可用区域（AX 坐标）。
    /// preferredMain：指定谁当主角（张开手势落在哪扇上）。canSlideOver：侧拉现在空着。canTuck：刘海能收。
    static func plan(_ windows: [MagicWindow], area: CGRect, preferredMain: CGWindowID? = nil,
                     canSlideOver: Bool = true, canTuck: Bool = true) -> MagicPlan {
        var plan = MagicPlan()
        guard !windows.isEmpty, area.width > 0, area.height > 0 else { return plan }
        let screenArea = area.width * area.height
        func score(_ w: MagicWindow) -> CGFloat {
            let own = demand(role(bundleID: w.bundleID, category: w.category))
            let share = min(1, (w.frame.width * w.frame.height) / screenArea)
            return own + (w.focused ? 0.6 : 0) + 0.4 * share
        }
        // 聊天：第一扇放侧拉（侧拉空着、而且还有别的窗口时）；再多的聊天窗口当成轻的，排进旁边一列。
        var rest = windows
        if canSlideOver,
           let chatIndex = rest.firstIndex(where: { role(bundleID: $0.bundleID, category: $0.category) == .chat && $0.id != preferredMain }),
           rest.count > 1 {
            plan.slideOver = rest.remove(at: chatIndex).id
        }
        let ranked = rest.enumerated().sorted { a, b in
            if a.element.id == preferredMain { return true }
            if b.element.id == preferredMain { return false }
            let (sa, sb) = (score(a.element), score(b.element))
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)
        guard let main = ranked.first else { return plan }
        let mainRole = role(bundleID: main.bundleID, category: main.category)
        plan.vertical = area.height > area.width * 1.05
        // 只有一扇：铺满。
        guard ranked.count > 1 else {
            plan.placements = [.init(id: main.id, frame: area, role: mainRole)]
            return plan
        }
        let capacity = plan.vertical ? max(1, min(3, Int(area.width / 360))) : max(1, min(3, Int(area.height / 280)))
        let side = Array(ranked.dropFirst().prefix(capacity))
        let extra = ranked.dropFirst(1 + side.count).map(\.id)
        if canTuck { plan.tuck = extra }
        let sideRoles = side.map { role(bundleID: $0.bundleID, category: $0.category) }
        let sideDemand = (sideRoles.map(demand).max() ?? 1) + 0.3 * CGFloat(side.count - 1)
        let extent = plan.vertical ? area.height : area.width
        plan.share = share(main: demand(mainRole) + (main.focused ? 0.6 : 0), side: sideDemand,
                           extent: extent, minSide: plan.vertical ? 320 : 420)
        // 主角在哪一边：跟着它现在的中心。
        plan.mainLeading = plan.vertical ? main.frame.midY <= area.midY : main.frame.midX <= area.midX
        let mainExtent = (extent * plan.share).rounded()
        let mainFrame: CGRect
        let sideFrame: CGRect
        if plan.vertical {
            mainFrame = CGRect(x: area.minX, y: plan.mainLeading ? area.minY : area.maxY - mainExtent,
                               width: area.width, height: mainExtent)
            sideFrame = CGRect(x: area.minX, y: plan.mainLeading ? area.minY + mainExtent : area.minY,
                               width: area.width, height: area.height - mainExtent)
        } else {
            mainFrame = CGRect(x: plan.mainLeading ? area.minX : area.maxX - mainExtent, y: area.minY,
                               width: mainExtent, height: area.height)
            sideFrame = CGRect(x: plan.mainLeading ? area.minX + mainExtent : area.minX, y: area.minY,
                               width: area.width - mainExtent, height: area.height)
        }
        plan.placements.append(.init(id: main.id, frame: mainFrame, role: mainRole))
        // 旁边一列按原来的上下（竖屏：左右）次序分，要地方多的分得多一点。
        let ordered = zip(side, sideRoles).sorted {
            plan.vertical ? $0.0.frame.midX < $1.0.frame.midX : $0.0.frame.midY < $1.0.frame.midY
        }
        let total = ordered.map { demand($0.1) }.reduce(0, +)
        var cursor: CGFloat = 0
        for (index, (window, role)) in ordered.enumerated() {
            let length = plan.vertical ? sideFrame.width : sideFrame.height
            let piece = index == ordered.count - 1 ? length - cursor : (length * demand(role) / total).rounded()
            let frame = plan.vertical
                ? CGRect(x: sideFrame.minX + cursor, y: sideFrame.minY, width: piece, height: sideFrame.height)
                : CGRect(x: sideFrame.minX, y: sideFrame.minY + cursor, width: sideFrame.width, height: piece)
            plan.placements.append(.init(id: window.id, frame: frame, role: role))
            cursor += piece
        }
        return plan
    }

    /// 浮窗里说的那一句：“主角 6 · 参考 4”，有侧拉、收进刘海的再补一句。names：窗口 id → App 名字。
    static func summary(_ plan: MagicPlan, names: [CGWindowID: String]) -> String {
        guard let main = plan.placements.first else { return WSL10n.text("magic.noWindows", zh: "这块屏上没有能排的窗口") }
        var parts: [String] = []
        let mainName = names[main.id] ?? WSL10n.text("magic.mainWindow", zh: "主窗口")
        if plan.placements.count == 1 {
            parts.append(WSL10n.text("magic.fillsScreen", zh: "%@ 铺满", mainName))
        } else {
            let mainShare = Int((plan.share * 10).rounded())
            let sideNames = plan.placements.dropFirst().compactMap { names[$0.id] }
            let unique = sideNames.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            if unique == [mainName] {
                // 同一个 App 的几扇窗：只说比例。
                parts.append("\(mainName) \(mainShare):\(10 - mainShare)")
            } else {
                parts.append("\(mainName) \(mainShare) · \(unique.prefix(2).joined(separator: "、")) \(10 - mainShare)")
            }
        }
        if let slide = plan.slideOver {
            parts.append(WSL10n.text("magic.sideBySide", zh: "%@ 侧拉",
                                     names[slide] ?? WSL10n.text("magic.chatWindow", zh: "聊天")))
        }
        if !plan.tuck.isEmpty {
            parts.append(WSL10n.text("magic.tucked", zh: "%@ 扇收进刘海", String(plan.tuck.count)))
        }
        return parts.joined(separator: "，")
    }
}

// MARK: 拖窗口落到另一扇上：按指针角度分边
// 思路来自 Hyprland DwindleAlgorithm 的 smart_split 与 DragController 的 drag_threshold（BSD-3），这里自己用 Swift 写。

extension MagicTiling {
    enum SplitSide: Equatable { case left, right, top, bottom }

    struct Split: Equatable {
        let side: SplitSide
        /// 被拖的那扇拿到的一半。
        let dragged: CGRect
        /// 目标窗口留下的另一半。
        let target: CGRect
    }

    /// 落点小岛要拖出多远才出现（点）：从按下标题栏算起。
    static let dropIslandThreshold: CGFloat = 10

    /// 拖够了才出小岛：点一下标题栏、手抖一下都不算。
    static func dropIslandVisible(travel: CGFloat) -> Bool { travel >= dropIslandThreshold }

    /// 指针相对目标中心，按半宽、半高归一后比大小：宽窗口和高窗口一样好选边。
    /// 两边一样大（对角线、正中心）时取左右；刚好在中心线上取右、下。y 向下（AX 坐标）。
    static func splitSide(target: CGRect, pointer: CGPoint) -> SplitSide {
        let halfW = max(target.width / 2, 0.01), halfH = max(target.height / 2, 0.01)
        let nx = (pointer.x - target.midX) / halfW
        let ny = (pointer.y - target.midY) / halfH
        if abs(nx) >= abs(ny) { return nx < 0 ? .left : .right }
        return ny < 0 ? .top : .bottom
    }

    /// 被拖的占指针那一边的一半，目标留另一半。
    static func split(target: CGRect, pointer: CGPoint) -> Split {
        let side = splitSide(target: target, pointer: pointer)
        let w = (target.width / 2).rounded(), h = (target.height / 2).rounded()
        let first: CGRect, second: CGRect
        switch side {
        case .left, .right:
            let l = CGRect(x: target.minX, y: target.minY, width: w, height: target.height)
            let r = CGRect(x: target.minX + w, y: target.minY, width: target.width - w, height: target.height)
            (first, second) = side == .left ? (l, r) : (r, l)
        case .top, .bottom:
            let t = CGRect(x: target.minX, y: target.minY, width: target.width, height: h)
            let b = CGRect(x: target.minX, y: target.minY + h, width: target.width, height: target.height - h)
            (first, second) = side == .top ? (t, b) : (b, t)
        }
        return Split(side: side, dragged: first, target: second)
    }
}

// MARK: 拖窗口落到另一扇上：松手时哪个落点说了算

extension MagicTiling {
    /// 松手时指针下的一扇窗口。frames 按 AX 坐标；eligible：普通窗口（标准窗口、不是全屏、不在侧拉或刘海里）。
    struct DropWindow: Equatable {
        let id: CGWindowID
        let frame: CGRect
        let eligible: Bool
    }

    enum DropTarget: Equatable {
        /// 落点小岛（收进刘海、半屏、铺满、魔法平铺）。
        case notchIsland
        /// 屏幕边上：系统自己的拖边平铺、侧拉、画中画在管。
        case edge
        /// 另一扇普通窗口：两扇并排。
        case window(CGWindowID)
        case nothing
    }

    /// 屏幕边上多宽算“在边上”（点）。
    static let dropEdgeInset: CGFloat = 6
    /// 并排后每一扇至少这么大，不够就不并排（和魔法平铺认窗口的下限一致）。
    static let dropMinimumSize = CGSize(width: 240, height: 160)

    /// 松手时谁说了算：落点小岛 > 屏幕边 > 指针下最上面的那扇普通窗口 > 什么都没有。
    /// windows：这块屏上的窗口，最前面的在前；被拖的那扇自己不算。最上面的那扇不是普通窗口（对话框、浮动面板）就什么都不做，
    /// 不穿过去落到它后面的窗口上。pointer、screen、windows 同一个坐标系（AX，y 向下）。
    static func dropTarget(pointer: CGPoint, onNotchIsland: Bool, screen: CGRect, windows: [DropWindow],
                           dragged: CGWindowID, edgeInset: CGFloat = dropEdgeInset) -> DropTarget {
        if onNotchIsland { return .notchIsland }
        guard screen.contains(pointer),
              pointer.x > screen.minX + edgeInset, pointer.x < screen.maxX - edgeInset,
              pointer.y > screen.minY + edgeInset, pointer.y < screen.maxY - edgeInset else { return .edge }
        for window in windows where window.id != dragged && window.frame.contains(pointer) {
            return window.eligible ? .window(window.id) : .nothing
        }
        return .nothing
    }

    /// 并排之后两扇各占的位置：目标先裁进可用区域，再按指针分边，最后留缝（ArrangeGap）。
    /// 任何一半小于 dropMinimumSize 就返回 nil（那样的窗口并排不了）。
    static func dropSplit(target: CGRect, pointer: CGPoint, area: CGRect, gap: CGFloat) -> Split? {
        let visible = target.intersection(area)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }
        let raw = split(target: visible, pointer: pointer)
        let dragged = ArrangeGap.apply(raw.dragged, in: area, gap: gap)
        let rest = ArrangeGap.apply(raw.target, in: area, gap: gap)
        for frame in [dragged, rest] where frame.width < dropMinimumSize.width || frame.height < dropMinimumSize.height {
            return nil
        }
        return Split(side: raw.side, dragged: dragged, target: rest)
    }
}
