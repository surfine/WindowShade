import CoreGraphics
import Foundation

// 刘海岛的纯几何：外接屏胶囊不顶出屏幕；弹簧飞行保护只在模型值已是新目标时留着在飞的弹簧。
@main
struct NotchIslandGeometryTests {
    static func main() {
        var t = TestSuite("NotchIslandGeometry")
        typealias G = NotchIslandGeometry
        // 外接屏的隐形刘海：沿用内建刘海高 33.5，或菜单栏估算 24（屏幕顶 1440）。
        let virtualTall = CGRect(x: 1187.5, y: 1406.5, width: 185, height: 33.5)
        let virtualShort = CGRect(x: 1185, y: 1416, width: 190, height: 24)
        let pill: CGFloat = 37.33

        t.section("NG-01", "外接屏的紧凑胶囊悬在菜单栏中央，顶边不顶出屏幕")
        for slot in [virtualTall, virtualShort] {
            let frame = G.islandFrame(notch: slot, width: 126, height: pill, virtual: true, hanging: false)
            t.expect(frame.maxY <= slot.maxY + 0.0001, "高 \(slot.height) 的隐形刘海：胶囊顶边 \(frame.maxY) ≤ 屏幕顶 \(slot.maxY)")
            t.expect(abs(frame.midX - slot.midX) < 0.0001 && frame.height == pill, "横向居中、高不变")
        }
        let roomy = CGRect(x: 0, y: 0, width: 200, height: 60)
        let centred = G.islandFrame(notch: roomy, width: 126, height: pill, virtual: true, hanging: false)
        t.expect(abs(centred.midY - roomy.midY) < 0.0001, "放得下时仍竖直居中在菜单栏里")
        let alert = G.islandFrame(notch: virtualShort, width: 371, height: 84, virtual: true, hanging: true)
        t.expect(alert.maxY == virtualShort.minY, "悬垂形状不受影响：顶边 = 隐形刘海下沿")

        t.section("NG-02", "弹簧飞行保护：只有模型值已经是新目标才留着在飞的弹簧")
        let big = CGRect(x: 0, y: 0, width: 371, height: 84)
        let small = CGRect(x: 93, y: 46.67, width: 185, height: 37.33)
        t.expect(NotchFlight.preserves(animated: false, inFlight: true, model: big, target: big), "在飞、模型值就是目标：留着，让它落地")
        t.expect(NotchFlight.preserves(animated: false, inFlight: true, model: big.insetBy(dx: 0.2, dy: 0.2), target: big), "差半点以内算同一个")
        t.expect(!NotchFlight.preserves(animated: false, inFlight: true, model: big, target: small),
                 "提醒正长着时来了不带动画的收回：去掉重设，不落在旧的大小")
        t.expect(!NotchFlight.preserves(animated: false, inFlight: true, model: big.offsetBy(dx: 0, dy: 1), target: big), "位置差一点也重设")
        t.expect(!NotchFlight.preserves(animated: false, inFlight: false, model: big, target: big), "不在飞：照常重设")
        t.expect(!NotchFlight.preserves(animated: true, inFlight: true, model: big, target: small), "带弹簧的：交给接力，不保护")
        t.finish()
    }
}
