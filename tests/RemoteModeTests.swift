import Foundation

@main
struct RemoteModeTests {
    static func main() {
        var t = TestSuite("I1f")

        t.section("I1f-01", "默认关闭 → 所有输入不产生系统动作")
        var a=RemoteMode()
        t.expect(a.handle(button(.playPause,.clickOnly,1,0,0)).isEmpty,"默认关闭")
        _=a.setEnabled(true)
        t.section("I1f-02", "短按电视、中心、音量、电源 → 固定动作；电源只请求显示器睡眠")
        t.expect(a.handle(button(.tv,.down,2,1,1)).isEmpty,"等待松手")
        t.expect(a.handle(button(.tv,.up,2,1,1.1)) == [.action(.launchpad)],"电视短按启动台")
        t.expect(a.handle(button(.select,.clickOnly,3,2,2)) == [.action(.activateFocused)],"中心是独立确认")
        t.expect(a.handle(button(.power,.clickOnly,4,3,3)) == [.action(.displaySleepRequest)],"不请求睡眠整机")
        t.section("I1f-03", "电视半秒长按再 up → 只开刘海，不再启动台")
        _=a.handle(button(.tv,.down,5,4,4))
        t.expect(a.handle(button(.tv,.heldHalfSecond,5,4,4.5)) == [.action(.notchShelf)],"半秒刘海")
        t.expect(a.handle(button(.tv,.up,5,4,4.6)).isEmpty,"长按尾部消耗")
        t.section("I1f-04", "播放长按切模式，同时另一键按住 → 两个旧 up 都不能进入新模式")
        _=a.handle(button(.side,.down,6,5,5)); _=a.handle(button(.playPause,.down,7,5.1,5.1))
        let toggle=a.handle(button(.playPause,.heldOneSecond,7,5.1,6.1))
        t.expect(toggle.contains(.modeChanged(.conductor)) && a.mode == .conductor,"切入指挥")
        t.expect(a.handle(button(.playPause,.up,7,5.1,6.2)).isEmpty && a.handle(button(.side,.up,6,5,6.3)).isEmpty,"不把旧 release 当提交")
        t.section("I1f-05", "指挥模式新的完整按压 → 原样转交，长按切回的尾端不放行")
        let fresh=button(.select,.down,8,7,7)
        t.expect(a.handle(fresh)==[.forward(fresh)],"原样交 D1")
        _=a.handle(button(.select,.up,8,7,7.1)); _=a.handle(button(.playPause,.down,9,8,8))
        t.expect(a.handle(button(.playPause,.heldOneSecond,9,8,9)).contains(.modeChanged(.remote)),"切回遥控")
        t.expect(a.handle(button(.playPause,.up,9,8,9.1)).isEmpty,"不能播放媒体")
        t.section("I1f-06", "关闭、重复、取消 → 清输入且不补短按")
        _=a.handle(button(.tv,.down,10,10,10))
        t.expect(a.handle(button(.tv,.cancel,10,10,10.1)).isEmpty,"取消无动作")
        t.expect(a.handle(button(.tv,.up,10,10,10.2)).isEmpty,"取消后的 up 忽略")
        t.expect(a.setEnabled(false).contains(.cancelConductorInput) && a.mode == .remote,"关闭撤销 D1 输入")

        t.finish()
    }
}
