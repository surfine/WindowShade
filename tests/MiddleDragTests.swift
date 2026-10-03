import Foundation

@main
struct MiddleDragTests {
    static func main() {
        var t = TestSuite("I1c")

        let origin = WS2.Point(x: 0, y: 0)
        t.section("I1c-01", "标题栏移动恰好 10 点后抬手 → 一次点击")
        var a = MiddleDrag(); _ = a.handle(.down(origin,.titlebar),at:sec(0))
        t.expect(a.handle(.up(.init(x:10,y:0)),at:sec(0.1)) == [.clickTitlebar], "大于而非等于十点才拖")
        t.expect(a.handle(.up(origin),at:sec(0.2)) == [.passThrough], "重复 up 无点击")
        t.section("I1c-02", "短拖超阈值但不到提交进度 → 取消，不变成点击")
        var b = MiddleDrag(); _ = b.handle(.down(origin,.titlebar),at:sec(0))
        _ = b.handle(.move(.init(x:20,y:0)),at:sec(0.1))
        t.expect(b.handle(.up(.init(x:20,y:0)),at:sec(0.2)) == [.cancelled], "短拖取消")
        t.section("I1c-03", "斜拖未形成主方向 → 原样放行，不猜轴")
        var c = MiddleDrag(); _ = c.handle(.down(origin,.other),at:sec(0))
        t.expect(c.handle(.move(.init(x:50,y:50)),at:sec(0.1)) == [.passThrough], "斜拖灰区")
        t.expect(c.handle(.up(.init(x:50,y:50)),at:sec(0.2)) == [.cancelled], "不突然提交")
        t.section("I1c-04", "锁定水平后垂直晃动 → 水平轴不翻转")
        var d = MiddleDrag(); _ = d.handle(.down(origin,.other),at:sec(0)); _ = d.handle(.move(.init(x:30,y:0)),at:sec(0.1))
        t.expect(d.handle(.up(.init(x:180,y:500)),at:sec(0.2)) == [.commit(.spaceRight)], "固定主轴")
        t.section("I1c-05", "同轴往返，回到起点抬手 → 取消，不补发短按")
        var e = MiddleDrag(); _ = e.handle(.down(origin,.titlebar),at:sec(0)); _ = e.handle(.move(.init(x:180,y:0)),at:sec(0.1))
        t.expect(e.handle(.up(origin),at:sec(0.2)) == [.cancelled], "往返取消")
        t.section("I1c-06", "四个明确方向大拖 → 对应既有标题栏/桌面意图")
        for (point,action) in [(WS2.Point(x:0,y:180),WS2.Action.missionControl),(.init(x:0,y:-180),.appWindows),(.init(x:-180,y:0),.spaceLeft)] {
            var x=MiddleDrag(); _=x.handle(.down(origin,.other),at:sec(0))
            t.expect(x.handle(.up(point),at:sec(1)) == [.commit(action)], "方向映射")
        }
        var x=MiddleDrag(); _=x.handle(.down(origin,.titlebar),at:sec(0))
        t.expect(x.handle(.up(.init(x:0,y:-180)),at:sec(1)) == [.commit(.titlebarDown)], "标题栏单独意图")
        t.section("I1c-07", "未知区域/非法坐标/倒流/中途取消 → 不提交动作")
        var f=MiddleDrag(); _=f.handle(.down(origin,.unknown),at:sec(0))
        t.expect(!f.isTracking && f.handle(.up(.init(x:500,y:0)),at:sec(1)) == [.passThrough], "未知区域放行")
        _=f.handle(.down(origin,.other),at:sec(2))
        t.expect(f.handle(.move(.init(x:.nan,y:1)),at:sec(3)).contains(.fault(.malformedInput)) && !f.isTracking, "无效坐标取消")
        t.expect(f.handle(.cancel,at:sec(1)) == [.fault(.timeReversed)], "时间倒流")

        t.finish()
    }
}
