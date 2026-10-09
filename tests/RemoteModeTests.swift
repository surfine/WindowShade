import Foundation

@main
struct RemoteModeTests {
    /// 一次完整的短按：按下、松开。
    static func press(_ a: inout RemoteMode, _ key: WS2.Button, id: UInt64, at t: Double) -> [RemoteMode.Effect] {
        let down = a.handle(button(key, .down, id, t, t))
        return down + a.handle(button(key, .up, id, t, t + 0.1))
    }

    static func main() {
        var t = TestSuite("I1f")

        t.section("I1f-01", "默认关闭 → 所有输入不产生动作")
        var a = RemoteMode()
        t.expect(a.handle(button(.playPause, .clickOnly, 1, 0, 0)).isEmpty, "默认关闭")
        _ = a.setEnabled(true)

        t.section("I1f-02", "每个键都是松开那一下才算：按下不动，松开才发")
        t.expect(a.handle(button(.tv, .down, 2, 1, 1)).isEmpty, "按下等待松手")
        t.expect(a.handle(button(.tv, .up, 2, 1, 1.1)) == [.returnToRow], "电视键短按 → 回到那一排")
        t.expect(a.handle(button(.up, .down, 3, 2, 2)).isEmpty, "方向键按下不动")
        t.expect(a.handle(button(.up, .up, 3, 2, 2.1)) == [.action(.focusUp)], "方向键松开才算")
        t.expect(a.handle(button(.select, .clickOnly, 4, 3, 3)) == [.action(.activateFocused)], "中心是独立确认")

        t.section("I1f-03", "电视键按住 ≥0.5 s → 启动台，尾部松开不再补短按")
        _ = a.handle(button(.tv, .down, 5, 4, 4))
        t.expect(a.handle(button(.tv, .heldHalfSecond, 5, 4, 4.5)) == [.launchpad], "半秒启动台")
        t.expect(a.handle(button(.tv, .up, 5, 4, 4.6)).isEmpty, "按住的尾部消耗，不再回到那一排")

        t.section("I1f-04", "电源、静音、播放、音量、返回 → 各是一件事，每层一样")
        for layer in [RemoteMode.Layer.collapsed, .row] {
            var b = RemoteMode(); _ = b.setEnabled(true); _ = b.setLayer(layer)
            t.expect(press(&b, .power, id: 1, at: 1) == [.wrapUp], "电源收工（\(layer)）：不请求睡眠")
            t.expect(press(&b, .mute, id: 2, at: 2) == [.togglePromptSound], "静音只管提示音，不发系统静音（\(layer)）")
            t.expect(press(&b, .playPause, id: 3, at: 3) == [.action(.mediaPlayPause)], "播放/暂停（\(layer)）")
            t.expect(press(&b, .volumeUp, id: 4, at: 4) == [.volume(1)] && press(&b, .volumeDown, id: 5, at: 5) == [.volume(-1)], "音量 ±1（\(layer)）")
            t.expect(press(&b, .back, id: 6, at: 6) == [.action(.back)], "返回退一层（\(layer)）")
            t.expect(press(&b, .left, id: 7, at: 7) == [.action(.focusLeft)] && press(&b, .right, id: 8, at: 8) == [.action(.focusRight)], "左右挪焦点（\(layer)）")
        }

        t.section("I1f-05", "往下：第 0 层展开那一排，第 1 层挪焦点")
        var c = RemoteMode(); _ = c.setEnabled(true)
        t.expect(press(&c, .down, id: 1, at: 1) == [.expandRow], "第 0 层往下展开")
        _ = c.setLayer(.row)
        t.expect(press(&c, .down, id: 2, at: 2) == [.action(.focusDown)], "第 1 层往下是焦点")

        t.section("I1f-06", "侧边键按住：只在焦点落在会话格上才走进会话")
        var d = RemoteMode(); _ = d.setEnabled(true); _ = d.setLayer(.row)
        _ = d.handle(button(.side, .down, 1, 1, 1))
        t.expect(d.handle(button(.side, .heldHalfSecond, 1, 1, 1.5)).isEmpty && d.handle(button(.side, .up, 1, 1, 1.6)).isEmpty, "焦点不在会话格 → 忽略，松开也不补")
        d.setFocusOnSession(true)
        _ = d.handle(button(.side, .down, 2, 2, 2))
        t.expect(d.handle(button(.side, .heldHalfSecond, 2, 2, 2.5)) == [.enterSessionAndListen], "焦点在会话格 → 走进会话并听")
        t.expect(d.handle(button(.side, .up, 2, 2, 2.6)).isEmpty, "按住的尾部消耗")
        t.expect(press(&d, .side, id: 3, at: 3).isEmpty, "侧边键短按不发系统听写")
        _ = d.setLayer(.collapsed)
        t.expect(!d.focusOnSession, "离开第 1 层，会话格焦点作废")

        t.section("I1f-07", "没有模式切换：播放键按住一秒也不换层")
        var e = RemoteMode(); _ = e.setEnabled(true)
        _ = e.handle(button(.playPause, .down, 1, 1, 1))
        t.expect(e.handle(button(.playPause, .heldOneSecond, 1, 1, 2)).isEmpty && e.layer == .collapsed, "按住一秒什么都不换")
        t.expect(e.handle(button(.playPause, .up, 1, 1, 2.1)) == [.action(.mediaPlayPause)], "松开仍是播放/暂停")

        t.section("I1f-08", "会话层：新的完整按压原样转交；换层时旧 up 不带进来，离开撤输入")
        var f = RemoteMode(); _ = f.setEnabled(true)
        _ = f.handle(button(.tv, .down, 1, 1, 1))
        t.expect(f.setLayer(.session).isEmpty, "第 1 层走进会话不需要撤输入")
        t.expect(f.handle(button(.tv, .up, 1, 1, 1.1)).isEmpty, "换层前按下的键，松开不进会话")
        let fresh = button(.select, .down, 2, 2, 2)
        t.expect(f.handle(fresh) == [.forward(fresh)], "原样交给 ConductorSession")
        let release = button(.select, .up, 2, 2, 2.1)
        t.expect(f.handle(release) == [.forward(release)], "松开也原样转交")
        let hold = button(.tv, .down, 3, 3, 3); _ = f.handle(hold)
        let held = button(.tv, .heldHalfSecond, 3, 3, 3.5)
        t.expect(f.handle(held) == [.forward(held)], "会话层的长按也交给 ConductorSession，不在这里翻译")
        _ = f.handle(button(.tv, .up, 3, 3, 3.6))
        _ = f.handle(button(.back, .down, 4, 4, 4))
        t.expect(f.setLayer(.row) == [.cancelConductorInput], "离开会话层撤掉转交的输入")
        t.expect(f.handle(button(.back, .up, 4, 4, 4.1)).isEmpty, "旧 release 不被当成第 1 层的返回")

        t.section("I1f-09", "关闭、重复、取消 → 清输入且不补短按")
        var g = RemoteMode(); _ = g.setEnabled(true)
        _ = g.handle(button(.tv, .down, 10, 10, 10))
        t.expect(g.handle(button(.tv, .cancel, 10, 10, 10.1)).isEmpty, "取消无动作")
        t.expect(g.handle(button(.tv, .up, 10, 10, 10.2)).isEmpty, "取消后的 up 忽略")
        _ = g.setLayer(.session)
        t.expect(g.setEnabled(false).contains(.cancelConductorInput) && g.layer == .collapsed, "关闭撤销输入，回到第 0 层")

        t.finish()
    }
}
