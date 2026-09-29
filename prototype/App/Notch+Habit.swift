// 卡住时刘海开口（docs/stuck-habits.md §4.8）：照 teach() 的样子从刘海长出来，岛里演一遍 Mac 上那一下，旁边一句话。
// 和手势提示不同的两点（Aaron 定，2026-09-29）：点一下提示就替他做成那一下（拷贝、存储、回到主屏幕……），记成会了；
// 右上角另有一个小叉，点它只是关掉，这条不再出。副句放 subtitle。落在没有刘海的屏上时换成备好的另一套（⌘H 那条）。
// 什么时候说、说什么由 HabitCenter（App/HabitContext.swift）定；这里只管露面。

import Cocoa

/// 一条要说的卡住提示。
struct HabitTip {
    /// 岛里的一句话、一句副句和那一小段演示。
    struct Content {
        let title: String
        let subtitle: String
        let demo: HabitDemo
    }
    let rule: HabitRule
    let content: Content
    /// 落在没有刘海的屏上（隐形刘海）时换成这一套；nil 就照常。
    var noNotch: Content? = nil
    /// 点一下：替他做成那一下，这条记成会了。
    let perform: () -> Void
    /// 点小叉：这条不再出。
    let close: () -> Void
}

extension NotchController {
    /// 在指针所在那块屏的刘海上说一条卡住提示。刘海或教学关着、一排正展开着、落点正垂着时返回 false（这次不说，不记账）。
    @discardableResult
    func teachHabit(_ tip: HabitTip) -> Bool {
        guard Self.isEnabled, Self.teachEnabled, !Self.probeSilence, let panel = habitPanel(),
              !panel.isExpanded, panel.dropState == .none else { return false }
        panel.collapse()
        // 上一条卡住提示还在岛上（只有探针会连着来）：先换成一句空的，好让演示按这一条重建。
        if panel.alertForProbe?.demo == .habit {
            panel.alert(NotchPanel.Alert(id: 0, icon: nil, title: "", subtitle: "", tone: .tip), duration: 0.1)
        }
        // 说什么、演什么跟着这块屏走：隐形刘海上点不到刘海，就不演“点一下刘海”。
        let content = panel.isVirtual ? tip.noNotch ?? tip.content : tip.content
        NotchDemoView.habit = NotchDemoView.HabitShow(demo: content.demo, onClose: tip.close)
        let alert = NotchPanel.Alert(id: 0, icon: nil, title: content.title, subtitle: content.subtitle, tone: .tip, demo: .habit,
                                     onClick: {
                                         // 点在小叉上是关掉，点在别处是替他做成那一下。
                                         if NotchDemoView.closeHit(NSEvent.mouseLocation) { tip.close() } else { tip.perform() }
                                     })
        panel.alert(alert, duration: 6.6)
        // 念的时候修饰键念成键名（⌃ 念 Control），第一次听到也知道是哪个键。
        let spoken = content.subtitle.isEmpty ? content.title : "\(content.title)。\(content.subtitle)"
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: HabitWords.spoken(spoken),
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        wlog("notch: habit \(tip.rule.rawValue)")
        return true
    }

    /// 指针所在那块屏的刘海（人正看着那里）；那块屏上没有，就用带刘海的那块，再没有就随便一块。和 announce、teach 同一个挑法。
    private func habitPanel() -> NotchPanel? {
        let panels = NSApp.windows.compactMap { $0 as? NotchPanel }
        let mouse = NSEvent.mouseLocation
        func screen(of panel: NotchPanel) -> NSScreen? {
            NSScreen.screens.first { $0.frame.contains(NSPoint(x: panel.notch.midX, y: panel.notch.midY)) }
        }
        return panels.first { screen(of: $0)?.frame.contains(mouse) == true }
            ?? panels.first { !$0.isVirtual }
            ?? panels.first
    }
}
