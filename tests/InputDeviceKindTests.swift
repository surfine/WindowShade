import Foundation

@main
struct InputDeviceKindTests {
    static func main() {
        var t = TestSuite("I1b")

        let magic = InputDeviceClassifier.Device(localToken: "m", vendorID: 0x05ac, productID: 0x0323, hidClass: .mouse)
        let wheel = InputDeviceClassifier.Device(localToken: "w", vendorID: 0x046d, productID: 1, hidClass: .mouse)
        t.section("I1b-01", "连续/动量字段没有逐事件设备关联 → 不能据此认出设备")
        let unknown = InputDeviceClassifier.classify(.init(continuous: false, hasMomentum: false, device: wheel, association: .enumerationOnly))
        t.expect(unknown.kind == .unknown && !unknown.mayRewrite, "仅枚举不够")
        t.expect(!InputDeviceClassifier.classify(.init(continuous: true, hasMomentum: true, device: nil, association: .none)).mayRewrite, "字段不能绑定硬件")
        t.section("I1b-02", "逐事件确认为滚轮鼠标 → 可进入滚轮改写路径")
        let w = InputDeviceClassifier.classify(.init(continuous: false, hasMomentum: false, device: wheel, association: .verifiedPerEvent))
        t.expect(w.kind == .wheelMouse && w.mayRewrite, "确认的滚轮")
        t.section("I1b-03", "已知 Apple 0323 → 妙控鼠标，仅方向层使用，不再平滑")
        let m = InputDeviceClassifier.classify(.init(continuous: true, hasMomentum: true, device: magic, association: .verifiedPerEvent))
        t.expect(m.kind == .magicMouse && m.mayRewrite, "0323 条目")
        t.section("I1b-04", "已知 0315 与未知 Apple PID → 遥控器或未知，不进滚轮路径")
        let remote = InputDeviceClassifier.Device(localToken: "r", vendorID: 0x05ac, productID: 0x0315, hidClass: .other)
        t.expect(InputDeviceClassifier.classify(.init(continuous: false, hasMomentum: false, device: remote, association: .verifiedPerEvent)).kind == .siriRemote, "0315 条目")
        let appleUnknown = InputDeviceClassifier.Device(localToken: "a", vendorID: 0x05ac, productID: 0xffff, hidClass: .mouse)
        t.expect(!InputDeviceClassifier.classify(.init(continuous: false, hasMomentum: false, device: appleUnknown, association: .verifiedPerEvent)).mayRewrite, "未知 Apple 产品不猜")
        t.section("I1b-05", "确认的触控板和连续未知鼠标 → 都不做滚轮平滑")
        let pad = InputDeviceClassifier.Device(localToken: "p", vendorID: 9, productID: 9, hidClass: .trackpad)
        let p = InputDeviceClassifier.classify(.init(continuous: true, hasMomentum: false, device: pad, association: .verifiedPerEvent))
        t.expect(p.kind == .trackpad && !p.mayRewrite, "触控板让开")
        t.expect(!InputDeviceClassifier.classify(.init(continuous: true, hasMomentum: false, device: wheel, association: .verifiedPerEvent)).mayRewrite, "连续鼠标未证明是滚轮")

        t.finish()
    }
}
