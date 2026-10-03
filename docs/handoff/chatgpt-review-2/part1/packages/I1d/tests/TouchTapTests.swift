import Foundation

@main
struct TouchTapTests {
    static func main() {
        var t = TestSuite("I1d")

        func contacts(_ n:Int,_ phase:TouchTap.Phase,_ shift:Double=0,_ area:Double=20)->[TouchTap.Contact] {
            (0..<n).map { .init(id:Int64($0),pointMM:.init(x:Double($0)*10+shift,y:0),areaMM2:area,phase:phase) }
        }
        t.section("I1d-01", "三指与四指同时落下，200ms 全抬起 → 各仅一次轻点")
        for n in [3,4] {
            var x=TouchTap(device:.trackpad); _=x.frame(contacts(n,.began),sequence:1,at:sec(0))
            t.expect(x.frame(contacts(n,.ended),sequence:2,at:sec(0.2)).tap == (n == 3 ? .threeFingers : .fourFingers), "三/四指完整组")
            t.expect(x.frame([],sequence:3,at:sec(0.21)).tap == nil, "空帧不重复")
        }
        t.section("I1d-02", "先三指，100ms 加第四指 → 不预报三指，最终四指")
        var a=TouchTap(device:.trackpad)
        t.expect(a.frame(contacts(3,.began),sequence:1,at:sec(0)).tap == nil, "先落三指不触发")
        var frame=contacts(3,.stationary); frame.append(.init(id:3,pointMM:.init(x:30,y:0),areaMM2:20,phase:.began))
        t.expect(a.frame(frame,sequence:2,at:sec(0.1)).tap == nil, "第四指入组")
        t.expect(a.frame(contacts(4,.ended),sequence:3,at:sec(0.2)).tap == .fourFingers, "最终四指")
        t.section("I1d-03", "三指移动达到 1.5mm 或掌面 → 整组失效")
        for (shift,area) in [(1.5,20.0),(0.0,140.0)] {
            var x=TouchTap(device:.trackpad); _=x.frame(contacts(3,.began),sequence:1,at:sec(0))
            t.expect(x.frame(contacts(3,.moved,shift,area),sequence:2,at:sec(0.1)).cancelled, "拖移/掌面拒绝")
            t.expect(x.frame(contacts(3,.ended),sequence:3,at:sec(0.2)).tap == nil, "失效后不复活")
        }
        t.section("I1d-04", "两指落下一指抬起、快照静默丢点 → 都不算三指")
        var b=TouchTap(device:.trackpad); _=b.frame(contacts(2,.began),sequence:1,at:sec(0))
        let mixed:[TouchTap.Contact]=[.init(id:0,pointMM:.init(x:0,y:0),areaMM2:20,phase:.ended),.init(id:1,pointMM:.init(x:10,y:0),areaMM2:20,phase:.stationary)]
        t.expect(b.frame(mixed,sequence:2,at:sec(0.1)).tap == nil, "部分抬手不结束整组")
        var c=TouchTap(device:.trackpad); _=c.frame(contacts(3,.began),sequence:1,at:sec(0))
        t.expect(c.frame(contacts(2,.ended),sequence:2,at:sec(0.1)).cancelled, "丢点不冒充 ended")
        t.section("I1d-05", "150ms/250ms 精确边界与超时 → 边界接受，超出拒绝")
        var d=TouchTap(device:.trackpad); _=d.frame(contacts(3,.began),sequence:1,at:sec(0))
        t.expect(d.frame(contacts(3,.ended),sequence:2,at:sec(0.25)).tap == .threeFingers, "250ms 包含边界")
        var e=TouchTap(device:.trackpad); _=e.frame(contacts(3,.began),sequence:1,at:sec(0))
        t.expect(e.frame(frame,sequence:2,at:sec(0.151)).cancelled, "迟到第四指拒绝")
        t.section("I1d-06", "妙控鼠标两指持续 3 秒 → 仍为两指按下，不套轻点时限")
        var m=TouchTap(device:.magicMouse); _=m.frame(contacts(2,.began),sequence:1,at:sec(0))
        t.expect(m.frame(contacts(2,.stationary),sequence:2,at:sec(3)).twoFingersDown, "持续弦键")
        t.expect(!m.frame(contacts(2,.ended),sequence:3,at:sec(3.1)).twoFingersDown, "抬起解除")
        t.section("I1d-07", "重复编号、超上限、序号重放、取消 → 不产出轻点")
        var n=TouchTap(device:.trackpad); let dup=contacts(1,.began)+contacts(1,.began)
        t.expect(n.frame(dup,sequence:1,at:sec(0)).fault == .malformedInput, "触点编号去重")
        _=n.frame([],sequence:2,at:sec(1))
        t.expect(n.frame(contacts(17,.began),sequence:3,at:sec(2)).fault == .capacityExceeded, "固定容量")
        t.expect(n.frame([],sequence:3,at:sec(2)).fault == .sequenceReplayed, "序号不能重用")
        _=n.frame([],sequence:4,at:sec(3)); n.cancel()
        t.expect(n.frame(contacts(3,.began),sequence:5,at:sec(4)).cancelled, "取消后先等全空帧")

        t.finish()
    }
}
