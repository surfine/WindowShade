import Cocoa

/// 租约接进刘海宿主之后的验收：协调器不再是纸上规则，面板真的按它出场和收场。
/// 纯核的 LEASE-01…10 在 tests/run-part2-core-tests.sh；这里只测宿主接线。
@main enum NotchLeaseHostTests {
    @MainActor static func main() async {
        _ = NSApplication.shared
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            if condition { print("ok   \(label)") } else { failures += 1; print("FAIL \(label)") }
        }

        let main = WS2.DisplayID(value: 71)
        let other = WS2.DisplayID(value: 72)
        var locked = false
        var panels: [WS2.DisplayID: NotchPanel] = [:]
        final class LeaseBox { var hub: NotchLeaseHub? }
        let box = LeaseBox()
        let hub = NotchLeaseHub(
            displays: { [main, other] },
            locked: { locked },
            cancel: { notice in
                let panel = panels[notice.display]
                if notice.reason == .suspended {
                    if panel?.suspendShelf() != true { box.hub?.forgetShelfPark(on: notice.display) }
                    return
                }
                panel?.cancelLease(notice.owner)
            })
        box.hub = hub
        hub.resumeShelfHandler = { panels[$0]?.resumeSuspendedShelf() }
        // 面板摆在屏幕外：测试不闪现在人眼前。
        func makePanel(_ display: WS2.DisplayID, x: CGFloat) -> NotchPanel {
            let panel = NotchPanel(notch: NSRect(x: x, y: 900, width: 180, height: 32), virtual: true)
            panel.leases = hub
            panel.displayID = display
            panels[display] = panel
            return panel
        }
        let notch = makePanel(main, x: -4000)
        let second = makePanel(other, x: -4400)

        print("CASE LEASE-H01 | 一块屏同一时刻只有一个主人")
        expect(hub.acquire(.authorization, on: main), "授权拿到这块屏")
        expect(hub.snapshot(main)?.layer == .authorization, "快照里是授权层")
        notch.expand(with: [])
        expect(!notch.isExpanded, "授权占着时那一排不展开")

        print("CASE LEASE-H02 | 授权抢占有同步收尾")
        hub.release(.authorization, on: main)
        expect(hub.owner(of: main) == nil, "释放授权")
        notch.expand(with: [])
        expect(notch.isExpanded, "那一排展开")
        let openedShelf = hub.snapshot(main)?.lease
        expect(hub.acquire(.authorization, on: main), "授权随后进来")
        expect(!notch.isExpanded, "被抢占时那一排同步收起")
        expect(hub.owner(of: main) == .authorization, "这块屏只剩新主人")

        print("CASE LEASE-H03 | 释放后原样回来，旧租约不复活")
        hub.release(.authorization, on: main)
        expect(hub.owner(of: main) == .notchShelf, "让出后那一排拿一份新的展示权")
        expect(notch.isExpanded && notch.lastShelfChangeAnimated == false, "从挂起处露出，不重播进场")
        expect(hub.snapshot(main)?.lease != nil && hub.snapshot(main)?.lease != openedShelf, "旧租约没有复活")

        print("CASE LEASE-H04 | 锁屏障撤掉一切")
        hub.invalidate(.locked)
        expect(hub.owner(of: main) == nil && hub.owner(of: other) == nil, "两块屏都没有主人")
        expect(!notch.isExpanded, "锁屏时那一排收起")
        expect(hub.snapshot(main)?.layer == .idle, "锁屏后回到空闲层")

        print("CASE LEASE-H05 | 撤屏只取消那一块")
        second.expand(with: [])
        expect(second.isExpanded, "第二块屏展开一排")
        expect(hub.owner(of: other) == .notchShelf, "这块屏的主人是那一排")
        hub.removeDisplay(main)
        expect(second.isExpanded, "撤掉另一块屏不影响这一块")
        expect(hub.owner(of: other) == .notchShelf, "这一块的租约还在")
        hub.removeDisplay(other)
        expect(!second.isExpanded, "撤掉自己这块屏就收起")
        expect(hub.owner(of: other) == nil, "撤屏后没有主人")

        print("CASE LEASE-H06 | 被占时的提醒只留小点")
        expect(hub.acquire(.launchpad, on: main), "启动台占着")
        expect(!hub.remind(on: main), "被占着：提醒不露面")
        hub.release(.launchpad, on: main)
        expect(hub.remind(on: main), "空下来：提醒可以露面")

        print("CASE LEASE-H07 | 持续活动每屏最多三条、去重")
        hub.publishOngoing(["a", "b", "a", "c", "d"], on: main)
        expect(hub.snapshot(main)?.ongoingIDs == ["a", "b", "c"], "去重并截断到三条")
        expect(hub.snapshot(other)?.ongoingIDs == [], "只登记这块屏")

        print("CASE LEASE-H08 | 关掉功能时锁屏态也算撤销")
        locked = true
        expect(!hub.acquire(.notchShelf, on: main), "锁着时拿不到展示权")
        locked = false
        expect(hub.acquire(.notchShelf, on: main), "解锁后可以拿")
        hub.invalidate(.disabled)
        expect(hub.owner(of: main) == nil, "关掉功能后清空")

        print("CASE LEASE-H09 | 展开时的提醒只留点，放开后不补说")
        notch.expand(with: [])
        expect(notch.isExpanded, "关掉功能之后可以再展开")
        notch.alert(NotchPanel.Alert(id: 0, icon: nil, title: "构建完成", subtitle: ""))
        expect(!notch.isAlerting && notch.showsSecondaryDot, "展开着只留一个点")
        hub.release(.notchShelf, on: main)
        expect(!notch.isExpanded && !notch.isAlerting && notch.showsSecondaryDot, "放开后不把那一句再说一遍")

        print("CASE LEASE-H10 | 紧凑两耳就是当前这一件")
        let music = NotchActivity(id: "music", kind: .music, title: "September", subtitle: "Earth, Wind & Fire",
                                  symbol: "music.note", startedAt: 1, progress: 0.4)
        let ears = NotchPanel(notch: NSRect(x: -5200, y: 900, width: 180, height: 32), virtual: true)
        ears.setActivities([music], selected: "music")
        let earShape = ears.shapeForProbe!.island
        expect(earShape.width == 200 && abs(earShape.height - 26) < 0.01, "紧凑是一颗胶囊，不是旧的横条")
        expect(ears.compactForProbe?.leading == "September" && ears.compactForProbe?.trailing == "40%",
               "左耳是这一件，右耳是进度")
        ears.expand(with: [])
        expect(ears.isExpanded && ears.shapeForProbe!.island.height > earShape.height, "展开是同一件事放大")

        print("CASE LEASE-H11 | 分开、半路改方向、再合并")
        Motion.reducedOverrideForProbe = false
        ears.collapse()
        ears.split(showing: "标题变了")
        let apart = ears.splitForProbe
        if !(apart.separated && !apart.retargeted && !apart.fades) {
            print("INFO H11 apart=\(apart) island=\(ears.shapeForProbe?.island as Any)")
        }
        expect(apart.separated && !apart.retargeted && !apart.fades, "从这一颗旁边分开")
        ears.split(showing: "又一句")
        let retargeted = ears.splitForProbe
        if !(retargeted.separated && retargeted.retargeted) {
            print("INFO H11 retargeted=\(retargeted)")
        }
        expect(retargeted.separated && retargeted.retargeted, "半路改方向从当前位置接上")
        ears.mergeSplit()
        expect(!ears.isSplit && !ears.splitForProbe.separated, "再合成一颗")

        print("CASE LEASE-H12 | 减少动态效果只淡入淡出")
        Motion.reducedOverrideForProbe = true
        let quiet = NotchPanel(notch: NSRect(x: -5600, y: 900, width: 180, height: 32), virtual: true)
        quiet.split(showing: "淡入")
        expect(quiet.splitForProbe.separated && quiet.splitForProbe.fades, "位置不动，只改透明度")
        Motion.reducedOverrideForProbe = nil
        expect(!NotchCanvasView.contentHasReachedFourTenths(from: 28, to: 280, now: 28), "起点还没走到四成")
        expect(NotchCanvasView.contentHasReachedFourTenths(from: 28, to: 280, now: 28 + 0.4 * (280 - 28)), "形状走到四成再进内容")

        print("CASE LEASE-H13 | 音量长在同一颗岛上，对方的提示在跑就让位")
        NotchPanel.foreignHUDOverride = true
        ears.presentLevel(.volume, value: 0.4)
        expect(ears.yieldedHUD && ears.levelForProbe == nil, "侦测到同类提示就让位")
        NotchPanel.foreignHUDOverride = false
        ears.presentLevel(.volume, value: 0.4)
        expect(ears.levelForProbe?.kind == "音量" && ears.levelForProbe?.value == 0.4, "合成的音量鼓起这一颗")
        let levelShape = ears.shapeForProbe!.island
        if abs(levelShape.width - 210) >= 0.5 || abs(levelShape.height - 36) >= 0.5 {
            print("INFO H13 level shape=\(levelShape) meter=\(String(describing: ears.levelForProbe))")
        }
        expect(abs(levelShape.width - 210) < 0.5 && abs(levelShape.height - 36) < 0.5, "音量鼓成稿上的 210×36 胶囊")
        ears.presentLevel(.brightness, value: 0.7)
        expect(ears.levelForProbe?.kind == "亮度" && ears.levelForProbe?.value == 0.7, "亮度也是这一颗")
        NotchPanel.foreignHUDOverride = nil

        print("CASE LEASE-H14 | 退场字先淡，展开保留两耳锚点")
        expect(NotchCanvasView.shouldExitContentFirst(
            from: NotchCanvasView.Content(tiles: [], dots: 0, dotsChanged: false, dotsY: 0, compact: nil,
                                          compactSlots: nil, alert: NotchPanel.Alert(id: 1, icon: nil, title: "好了", subtitle: ""),
                                          hint: nil, notchHeight: 32),
            to: NotchCanvasView.Content(tiles: [], dots: 0, dotsChanged: false, dotsY: 0, compact: nil,
                                        compactSlots: nil, alert: nil, hint: nil, notchHeight: 32)),
               "提醒退场先清内容")
        let shelf = NotchPanel(notch: NSRect(x: -5800, y: 900, width: 180, height: 32), virtual: true)
        shelf.setCompact(NotchPanel.Compact(pid: nil, icon: nil, count: 2, changed: false), room: nil)
        shelf.expand(with: [NotchTile(id: 1, kind: .tucked, snapshot: nil, icon: nil, title: "窗口")])
        expect(shelf.isExpanded && shelf.compactForProbe?.count == 2 && shelf.compactForProbe?.leading == nil,
               "展开一排仍留着紧凑两耳的个数")

        print("CASE LEASE-H15 | 亮度也是 210×36；曲名变更走旁边那颗岛")
        let bright = NotchPanel(notch: NSRect(x: -6000, y: 900, width: 180, height: 32), virtual: true)
        bright.presentLevel(.brightness, value: 0.55)
        let brightShape = bright.shapeForProbe!.island
        expect(abs(brightShape.width - 210) < 0.5 && abs(brightShape.height - 36) < 0.5, "亮度鼓成同一颗胶囊")
        let duo = NotchPanel(notch: NSRect(x: -6200, y: 900, width: 180, height: 32), virtual: true)
        let tune = NotchActivity(id: "music", kind: .music, title: "September", subtitle: "Earth, Wind & Fire",
                                 symbol: "music.note", startedAt: 1, progress: 0.4)
        duo.setActivities([tune], selected: "music")
        duo.alert(NotchPanel.Alert(id: 0, icon: nil, title: "Boogie Wonderland", subtitle: "标题变了"), duration: 2.6)
        expect(duo.isSplit && duo.splitForProbe.separated, "曲名变了旁边分开一颗")

        print(failures == 0 ? "PASS NotchLeaseHostTests: 15 cases, \(failures) failures" : "FAIL NotchLeaseHostTests: \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
