import Foundation

@main
struct SiriRemoteButtonsTests {
    static func main() {
        var t = TestSuite("I1e")

        t.section("I1e-01", "12 个规定 HID 用法与未知用法 → 准确映射，未知不猜")
        let entries:[(UInt32,UInt32,WS2.Button)]=[(12,0x42,.up),(12,0x43,.down),(12,0x44,.left),(12,0x45,.right),(12,0x80,.select),(1,0x86,.back),(12,0x60,.tv),(12,0xcd,.playPause),(12,0xe2,.mute),(12,0xe9,.volumeUp),(12,0xea,.volumeDown),(12,4,.side)]
        for (p,u,b) in entries { t.expect(SiriRemoteButtons.button(page:p,usage:u)==b,"HID 映射 \(u)") }
        t.expect(SiriRemoteButtons.button(page:12,usage:0x30)==nil,"不捏造电源用法")
        t.section("I1e-02", "100ms 短按、重复 down/up → 一对阶段，无重复")
        var a=SiriRemoteButtons(); let down=a.report(page:12,usage:0x80,value:1,at:sec(0))
        t.expect(down.count==1 && down[0].phase == .down,"按下")
        t.expect(a.report(page:12,usage:0x80,value:1,at:sec(0.05)).isEmpty,"重复按下忽略")
        let up=a.report(page:12,usage:0x80,value:0,at:sec(0.1))
        t.expect(up.count==1 && up[0].phase == .up && up[0].pressID==down[0].pressID,"同一按压编号")
        t.expect(a.report(page:12,usage:0x80,value:0,at:sec(0.2)).isEmpty && a.nextWake==nil,"松开去重无定时器")
        t.section("I1e-03", "按住跨 0.5 秒和 1 秒 → 阈值各发一次，up 保留原编号")
        var b=SiriRemoteButtons(); _=b.report(page:12,usage:0xcd,value:1,at:sec(0))
        t.expect(b.nextWake==sec(0.5),"下一阈值")
        t.expect(b.tick(at:sec(0.5)).map(\.phase)==[.heldHalfSecond],"半秒")
        t.expect(b.tick(at:sec(1)).map(\.phase)==[.heldOneSecond],"一秒")
        t.expect(b.tick(at:sec(2)).isEmpty && b.nextWake==nil,"不持续重复 held")
        t.expect(b.report(page:12,usage:0xcd,value:0,at:sec(3)).map(\.phase)==[.up],"长按仍有匹配 up")
        t.section("I1e-04", "两个键重叠按住后断开 → 各一个 cancel，无伪造 up")
        var c=SiriRemoteButtons(); _=c.report(page:12,usage:0x60,value:1,at:sec(0)); _=c.report(page:12,usage:4,value:1,at:sec(0.01))
        let cancelled=c.cancelAll(at:sec(0.1))
        t.expect(cancelled.count==2 && cancelled.allSatisfy{$0.phase == .cancel},"丢 up 用取消")
        t.expect(c.cancelAll(at:sec(0.2)).isEmpty && c.nextWake==nil,"重复取消幂等")
        t.section("I1e-05", "up 恰好一秒才到 → 先补阈值，再 up；非法值与倒流不变状态")
        var d=SiriRemoteButtons(); _=d.report(page:12,usage:0xcd,value:1,at:sec(1))
        t.expect(d.report(page:12,usage:0xcd,value:0,at:sec(2)).map(\.phase)==[.heldHalfSecond,.heldOneSecond,.up],"事件顺序可消耗 release")
        t.expect(d.report(page:12,usage:0xcd,value:2,at:sec(3)).isEmpty && d.tick(at:sec(0)).isEmpty,"非法事件无输出")

        t.finish()
    }
}
