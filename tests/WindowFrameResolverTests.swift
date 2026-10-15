import CoreGraphics
import Foundation

// 规格 R7：外框四级回退的判据。AX 两项都在时结果与原来一样，缺了才用窗口服务器补。
@main
struct WindowFrameResolverTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; print("FAIL \(what)") }
    }

    static func main() {
        let p = CGPoint(x: 100, y: 50), s = CGSize(width: 800, height: 600)
        let listed = CGRect(x: 120, y: 60, width: 700, height: 500)

        let ax = WindowFrameResolver.resolve(axPosition: p, axSize: s, windowList: listed)
        check(ax?.frame == CGRect(origin: p, size: s) && ax?.source == .ax, "AX 两项都在：只用 AX，不看窗口服务器")

        let noSize = WindowFrameResolver.resolve(axPosition: p, axSize: nil, windowList: listed)
        check(noSize?.frame == CGRect(origin: p, size: listed.size) && noSize?.source == .axPositionWindowListSize,
              "缺尺寸：位置用 AX、尺寸用窗口服务器")

        let noPosition = WindowFrameResolver.resolve(axPosition: nil, axSize: s, windowList: listed)
        check(noPosition?.frame == CGRect(origin: listed.origin, size: s) && noPosition?.source == .windowListPositionAXSize,
              "缺位置：位置用窗口服务器、尺寸用 AX")

        let none = WindowFrameResolver.resolve(axPosition: nil, axSize: nil, windowList: listed)
        check(none?.frame == listed && none?.source == .windowList, "AX 全读不到：整个用窗口服务器")

        check(WindowFrameResolver.resolve(axPosition: nil, axSize: nil, windowList: nil) == nil, "四级都没有：nil，不编")
        check(WindowFrameResolver.resolve(axPosition: nil, axSize: nil,
                                          windowList: CGRect(x: 0, y: 0, width: 1, height: 1)) == nil,
              "窗口服务器报 1×1（藏起来的窗口）当作没读到")
        check(WindowFrameResolver.resolve(axPosition: nil, axSize: CGSize(width: 0, height: 0), windowList: listed)?.source
              == .windowList, "AX 尺寸是 0×0 时不拿它拼")

        if failures > 0 { print("window-frame-resolver: \(failures) failure(s)"); exit(1) }
        print("PASS window-frame-resolver: ax first, three fallbacks, bounded nil, tiny frames rejected")
    }
}
