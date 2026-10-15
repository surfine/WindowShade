import Cocoa

@main
struct MenuStructureTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; print("FAIL \(what)") }
    }

    @MainActor
    static func run() {
        let ids = StatusMenuLayout.fixedTopLevel.map(\.id)
        let titles = StatusMenuLayout.fixedTopLevel.map(\.title)

        // 顶层恰好 9 项，顺序对。
        check(titles == ["收起", "收进刘海", "置顶", "整理", "启动台", "已收起的窗口", "设置…", "关于", "退出"],
              "顶层 9 项与顺序")
        check(Set(ids).count == 9, "id 不重复")

        // 用同样 id 搭一个菜单：动态行、分隔线、按住 ⌥ 才显示的隐藏项都不算在 9 项里。
        func makeMenu(dynamic: [String], hiddenExtras: Int) -> NSMenu {
            let menu = NSMenu()
            for id in dynamic {
                let item = NSMenuItem(title: "动态", action: nil, keyEquivalent: "")
                item.identifier = NSUserInterfaceItemIdentifier(id)
                menu.addItem(item)
            }
            if !dynamic.isEmpty { menu.addItem(.separator()) }
            for (id, title) in StatusMenuLayout.fixedTopLevel {
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.identifier = NSUserInterfaceItemIdentifier(id)
                menu.addItem(item)
                if id == "ws.menu.folded" { menu.addItem(.separator()) }
            }
            for _ in 0..<hiddenExtras {
                let hidden = NSMenuItem(title: "检查更新…", action: nil, keyEquivalent: "")
                hidden.isHidden = true
                menu.addItem(hidden)
            }
            return menu
        }
        let plain = makeMenu(dynamic: [], hiddenExtras: 2)
        check(StatusMenuLayout.visibleFixedIDs(in: plain) == ids, "固定项按顺序可见")
        let busy = makeMenu(
            dynamic: StatusMenuLayout.dynamicRowIDs(focusActive: true, waitingCodingSessions: 2), hiddenExtras: 2)
        check(StatusMenuLayout.visibleFixedIDs(in: busy) == ids, "有动态行时固定项仍是同样 9 项")
        check(busy.items.count == plain.items.count + 4, "动态行 3 条加 1 条分隔线")

        // 动态行只在进行中出现。
        check(StatusMenuLayout.dynamicRowIDs(focusActive: false, waitingCodingSessions: 0).isEmpty, "没有进行中就没有动态行")
        check(StatusMenuLayout.dynamicRowIDs(focusActive: true, waitingCodingSessions: 0)
                == [StatusMenuLayout.focusRowID], "番茄钟进行中一行")
        check(StatusMenuLayout.dynamicRowIDs(focusActive: false, waitingCodingSessions: 2)
                == [StatusMenuLayout.codingRowID, StatusMenuLayout.codingRowID], "每个等你的会话一行")

        // 有置顶窗口：多一行动态行，固定项不变；没有则不在。
        check(StatusMenuLayout.dynamicRowIDs(focusActive: false, waitingCodingSessions: 0, pinnedCount: 0).isEmpty,
              "没有置顶就没有置顶行")
        let pinnedIDs = StatusMenuLayout.dynamicRowIDs(focusActive: false, waitingCodingSessions: 0, pinnedCount: 2)
        check(pinnedIDs == [StatusMenuLayout.pinnedRowID], "有置顶多一行")
        let withPins = makeMenu(dynamic: pinnedIDs, hiddenExtras: 2)
        check(StatusMenuLayout.visibleFixedIDs(in: withPins) == ids, "有置顶时顶层仍是同样 9 项")
        check(withPins.items.count == plain.items.count + 2, "置顶行加分隔线")
        check(StatusMenuLayout.pinnedRowTitle(count: 2) == "置顶的窗口（2）", "置顶行名")
        // 辅助功能没开：最上面多一行，不算在固定 9 项里。
        let axIDs = StatusMenuLayout.dynamicRowIDs(focusActive: true, waitingCodingSessions: 0, accessibilityOff: true)
        check(axIDs.first == StatusMenuLayout.accessibilityRowID && axIDs.count == 2, "辅助功能那一行排在动态行最前")
        let withAX = makeMenu(dynamic: [StatusMenuLayout.accessibilityRowID], hiddenExtras: 2)
        check(StatusMenuLayout.visibleFixedIDs(in: withAX) == StatusMenuLayout.visibleFixedIDs(in: plain),
              "辅助功能那一行不占固定 9 项")

        // 子菜单里的窗口项仍属于状态栏菜单树（悬停预览依赖这个）。
        let root = NSMenu(), sub = NSMenu(), subsub = NSMenu(), other = NSMenu()
        let a = NSMenuItem(title: "a", action: nil, keyEquivalent: ""); a.submenu = sub; root.addItem(a)
        let b = NSMenuItem(title: "b", action: nil, keyEquivalent: ""); b.submenu = subsub; sub.addItem(b)
        check(StatusMenuLayout.belongsToStatusMenu(root, root: root), "根菜单")
        check(StatusMenuLayout.belongsToStatusMenu(subsub, root: root), "二级子菜单")
        check(!StatusMenuLayout.belongsToStatusMenu(other, root: root), "别的菜单不算")

        // 旧 → 新位置表：每个旧 action 仍在 MenuBarController 里挂着，且位置表没有「已删除」。
        let source = (try? String(contentsOfFile: "prototype/App/MenuBarController.swift", encoding: .utf8)) ?? ""
        check(!source.isEmpty, "能读到 MenuBarController.swift")
        for row in StatusMenuLayout.legacyLocations {
            check(source.contains("#selector(\(row.action)"), "旧 action 仍挂在菜单上：\(row.action)")
            check(!row.now.isEmpty && !row.now.contains("删"), "有新位置：\(row.action)")
        }
        let actions = StatusMenuLayout.legacyLocations.map(\.action)
        check(Set(actions).count == actions.count, "位置表没有重复 action")
        for id in ids { check(source.contains("\"\(id)\""), "控制器给了顶层项 id：\(id)") }
        check(source.contains("addPinnedPreviewMenuSection(menuState.pinnedPreviews, into: pinnedMenu)"), "置顶段进动态行")
        check(!source.contains("into: arrangement)"), "整理▸里不再重复置顶段")
        check(source.contains("phase != .idle"), "番茄钟行只在进行中才加")
        check(source.contains("StatusMenuLayout.stripOverviewRowID"), "整理▸里有卷轴概览")
        check(StatusMenuLayout.fixedTopLevel.count == 9, "卷轴概览在子菜单里，顶层仍是 9 项")

        // 卷轴概览（SS-05）：主菜单“窗口”里一项，快捷键默认不占；顶层项数不变；卷轴没接上时灰着。
        _ = NSApplication.shared  // make() 要写 NSApp.servicesMenu
        let main = StandardMenu.make(appName: "WindowShade", settingsTarget: nil, settingsAction: nil)
        check(main.items.count == 3, "主菜单顶层仍是 应用 / 编辑 / 窗口 三项")
        let windowMenu = main.items.last?.submenu
        let overview = windowMenu?.items.first { $0.identifier?.rawValue == StandardMenu.stripOverviewID }
        check(overview?.title == "卷轴概览", "窗口菜单里有“卷轴概览”")
        check(overview?.keyEquivalent == "", "卷轴概览默认不占快捷键")
        check(windowMenu?.items.filter { !$0.isSeparatorItem }.map(\.title) == ["关闭", "最小化", "卷轴概览"],
              "窗口菜单：关闭、最小化、卷轴概览")
        StripOverviewMenuTarget.shared.canOpen = nil
        check(overview.map { !StripOverviewMenuTarget.shared.validateMenuItem($0) } == true, "卷轴没开时灰着")
        var opened = false
        StripOverviewMenuTarget.shared.canOpen = { true }
        StripOverviewMenuTarget.shared.open = { opened = true; return true }
        check(overview.map { StripOverviewMenuTarget.shared.validateMenuItem($0) } == true, "卷轴开着时能点")
        StripOverviewMenuTarget.shared.openStripOverview(nil)
        check(opened, "点了就打开概览")
        StripOverviewMenuTarget.shared.open = nil
        StripOverviewMenuTarget.shared.canOpen = nil
    }

    static func main() {
        MainActor.assumeIsolated { run() }
        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("menu structure tests passed")
    }
}
