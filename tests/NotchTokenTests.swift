// 刘海动效与紧凑令牌对齐（总稿“令牌”节）：形状 → 弹簧、内容淡入淡出时序、停留时长、
// 两耳文字的选择、番茄钟环与信息点的几何。纯计算，不碰窗口。
import CoreGraphics
import Foundation

@main
struct NotchTokenTests {
    static func item(_ kind: NotchActivityKind, title: String = "t", subtitle: String = "", detail: String = "",
                     progress: Double? = nil, trailing: String? = nil) -> NotchActivity {
        NotchActivity(id: "x", kind: kind, title: title, subtitle: subtitle, startedAt: 0,
                      progress: progress, detail: detail, trailing: trailing)
    }

    static func main() {
        var t = TestSuite("C01")

        t.section("C01-01", "形状 → 弹簧令牌：最小 calm，紧凑三种 settle，提醒 bloom，展开 expand，交互与音量亮度 pop，落点 catchDrop")
        let table: [(Motion.NotchShape, Motion.Spring, String)] = [
            (.minimum, .calm, "calm"), (.compact, .settle, "settle"), (.chin, .settle, "settle"),
            (.capsuleCompact, .settle, "settle"), (.alert, .bloom, "bloom"), (.expanded, .expand, "expand"),
            (.interaction, .pop, "pop"), (.meter, .pop, "pop"), (.drop, .catchDrop, "catchDrop"),
        ]
        t.expect(table.count == Motion.NotchShape.allCases.count, "映射表覆盖每一种形状")
        for (shape, token, name) in table {
            t.expect(Motion.notchSpring(for: shape, reduced: false) == token, "\(shape) 用 \(name)")
            t.expect(Motion.notchSpring(for: shape, reduced: true) == .reducedNotch, "\(shape) 在减少动态效果时用 reducedNotch")
        }
        t.expect(Motion.Spring.calm.response == 0.34 && Motion.Spring.calm.bounce == 0, "calm 0.34 / 不回弹")
        t.expect(Motion.Spring.settle.response == 0.38 && Motion.Spring.settle.bounce == 0, "settle 0.38 / 不回弹")
        t.expect(Motion.Spring.bloom.response == 0.42 && Motion.Spring.bloom.dampingRatio == 0.84, "bloom 0.42 / 0.84")
        t.expect(Motion.Spring.expand.response == 0.4 && Motion.Spring.expand.dampingRatio == 0.92, "expand 0.40 / 0.92")
        t.expect(Motion.Spring.pop.response == 0.3 && Motion.Spring.pop.dampingRatio == 0.75, "pop 0.30 / 0.75")
        t.expect(Motion.notchSpring(for: .interaction, reduced: false) != .calm, "认证卡不再用 calm")

        t.section("C01-02", "内容时序常量：淡入 0.18、淡出 0.10、停 0.04、第二层晚 0.20、形状四成")
        t.expect(Motion.Fade.in == 0.18 && Motion.Fade.out == 0.10, "淡入 0.18 / 淡出 0.10")
        t.expect(Motion.Fade.gap == 0.04 && Motion.Fade.secondLayerDelay == 0.20, "停 0.04 / 第二层 0.20")
        t.expect(Motion.Fade.shapeGate == 0.40, "形状走到四成才开始淡入")
        t.expect(Motion.Fade.fadeIn(reduced: false) == 0.18 && Motion.Fade.fadeOut(reduced: false) == 0.10, "平时按令牌")
        t.expect(Motion.Fade.fadeIn(reduced: true) == 0.25 && Motion.Fade.fadeOut(reduced: true) == 0.25, "减少动态效果交叉淡化 0.25（令牌 reducedNotch）")
        t.expect(Motion.Fade.exitGap(reduced: false) == 0.04 && Motion.Fade.exitGap(reduced: true) == 0, "减少动态效果没有退场停顿")
        t.expect(Motion.Fade.secondLayerLag(reduced: false) == 0.20 && Motion.Fade.secondLayerLag(reduced: true) == 0, "减少动态效果不分层")

        t.section("C01-03", "停留：格子 0.20、指针停在刘海 0.12、卷帘条意图 0.20")
        t.expect(Motion.Hold.tileDwell == 0.20, "格子 0.20")
        t.expect(Motion.Hold.notchDwell == 0.12, "刘海仍是 0.12")
        t.expect(Motion.Hold.alert == 2.6, "提醒停留不变")
        t.expect(GlanceTiming.standard.intentDelay == 0.20, "卷帘条意图 0.20")
        t.expect(GlanceTiming.standard.leaveGrace == 0.16, "离开宽限不变")

        t.section("C01-04", "右耳文字：音乐不写 %，番茄钟 18 分 / 0:42 / 暂停，下载与隔空投送可以写 %")
        t.expect(NotchEarText.trailing(item(.music, progress: 0.42)) == "", "音乐有进度、没有剩余时间：不写 %")
        t.expect(NotchEarText.trailing(item(.music, detail: "com.apple.Music", progress: 0.42)) == "", "音乐不退回到 App 标识")
        t.expect(NotchEarText.trailing(item(.music, progress: 0.42, trailing: "2:14")) == "2:14", "音乐给了剩余时间就写它")
        t.expect(NotchEarText.trailing(item(.download, progress: 0.5)) == "50%", "下载写 %")
        t.expect(NotchEarText.trailing(item(.airDrop, progress: 0.07)) == "7%", "隔空投送写 %")
        t.expect(NotchEarText.trailing(item(.focus, progress: 0.3)) != "30%", "番茄钟不写 %")
        t.expect(NotchEarText.trailing(item(.focus, progress: 0.3, trailing: "18 分")) == "18 分", "番茄钟右耳 18 分")
        t.expect(NotchEarText.trailing(item(.download, progress: 0.5, trailing: "还剩 1 分")) == "还剩 1 分", "来源给的字优先于百分比")
        t.expect(NotchEarText.trailing(item(.route, subtitle: "12 分钟")) == "12 分钟", "没有 trailing 的退回副句")
        t.expect(!NotchActivityKind.music.writesPercent && !NotchActivityKind.focus.writesPercent, "音乐与番茄钟不写百分比")
        t.expect(NotchActivityKind.download.writesPercent && NotchActivityKind.airDrop.writesPercent, "下载与隔空投送写百分比")

        t.section("C01-05", "番茄钟右耳用 FocusTimer.compactText；暂停写暂停；副句今天第 N 个")
        let cal = FocusTimer.CalendarSample(today: "2026-10-03", deadlineDay: "2026-10-03")
        var timer = FocusTimer(bootID: fixtureBoot)
        _ = timer.handle(.start, at: sec(0), calendar: cal)
        t.expect(NotchEarText.focusTrailing(compactText: timer.compactText(at: sec(420)), paused: false) == "18 分", "18 分")
        t.expect(NotchEarText.focusTrailing(compactText: timer.compactText(at: sec(1458)), paused: false) == "0:42", "最后一分钟 0:42")
        t.expect(NotchEarText.focusTrailing(compactText: "18 分", paused: true) == "暂停", "暂停写暂停")
        t.expect(NotchEarText.focusSubtitle(isRest: false, completedToday: 0, paused: false) == "今天第 1 个", "专注中 N = 已完成 + 1")
        t.expect(NotchEarText.focusSubtitle(isRest: false, completedToday: 2, paused: false) == "今天第 3 个", "第三个")
        t.expect(NotchEarText.focusSubtitle(isRest: true, completedToday: 1, paused: false) == "今天第 1 个", "休息中 N = 已完成")
        t.expect(NotchEarText.focusSubtitle(isRest: false, completedToday: 1, paused: true) == "已暂停", "暂停写已暂停")
        let focusItem = item(.focus, title: "专注", trailing: "18 分")
        t.expect(NotchEarText.cardTitle(focusItem) == "专注 · 18 分", "展开的卡片合起来读")
        t.expect(NotchEarText.cardTitle(item(.focus, title: "番茄钟 25 / 5")) == "番茄钟 25 / 5", "空闲卡不变")
        t.expect(NotchEarText.cardTitle(item(.music, title: "歌", trailing: "2:14")) == "歌", "别的种类不合并")
        t.expect(NotchEarText.isRest(item(.focus, title: "休息")) && !NotchEarText.isRest(focusItem), "按标题认休息")

        t.section("C01-06", "音乐剩余时间 m:ss")
        t.expect(NotchEarText.musicRemaining(elapsed: 106, duration: 240) == "2:14", "240 - 106 = 2:14")
        t.expect(NotchEarText.musicRemaining(elapsed: 0, duration: 59.2) == "1:00", "向上取整")
        t.expect(NotchEarText.musicRemaining(elapsed: nil, duration: 240) == nil, "没有位置不编数")
        t.expect(NotchEarText.musicRemaining(elapsed: 10, duration: nil) == nil, "没有总长不编数")
        t.expect(NotchEarText.musicRemaining(elapsed: 10, duration: 0) == nil, "总长为 0 不编数")
        t.expect(NotchEarText.musicRemaining(elapsed: 300, duration: 240) == "0:00", "走过头夹到 0:00")
        t.expect(NotchEarText.musicRemaining(elapsed: .nan, duration: 240) == nil, "非有限值不编数")

        t.section("C01-07", "进度环与信息点几何、语气色")
        t.expect(NotchFocusRing.viewport == 16 && NotchFocusRing.radius == 6.5 && NotchFocusRing.lineWidth == 2.2, "环 16 / 6.5 / 2.2")
        t.expect(NotchFocusRing.trackWhiteAlpha == 0.18, "底环白 18%")
        t.expect(NotchFocusRing.viewport / 2 >= NotchFocusRing.radius + NotchFocusRing.lineWidth / 2, "环不超出视口")
        t.expect(NotchFocusRing.focusRGB == (255.0 / 255, 107.0 / 255, 94.0 / 255), "专注红 #FF6B5E")
        t.expect(NotchFocusRing.restRGB == (95.0 / 255, 211.0 / 255, 138.0 / 255), "休息绿 #5FD38A")
        t.expect(NotchInfoDot.diameter == 8 && NotchInfoDot.trailingInset == 10 && NotchInfoDot.bottomInset == 8, "信息点 8pt、右 10、下 8")
        t.expect(NotchInfoDot.tone(for: item(.focus, title: "专注")) == .focus, "专注红")
        t.expect(NotchInfoDot.tone(for: item(.focus, title: "休息")) == .rest, "休息绿")
        t.expect(NotchInfoDot.tone(for: item(.music)) == .playback, "播放绿")
        t.expect(NotchInfoDot.tone(for: item(.download)) == .accent && NotchInfoDot.tone(for: item(.route)) == .accent, "其余用强调色")

        t.finish()
    }
}
