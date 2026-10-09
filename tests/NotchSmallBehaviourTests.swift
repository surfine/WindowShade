import CoreGraphics
import Foundation

@main
struct NotchSmallBehaviourTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ message: String) {
        if !ok { failures += 1; print("FAIL: \(message)") }
    }

    static func main() {
        // 放不下的格子灰掉：目标比最小尺寸小才灰。
        let tiny = CGSize(width: 150, height: 400)
        check(NotchSmallBehaviour.isDisabled(target: tiny, minimum: CGSize(width: 300, height: 200)), "narrower than minimum is disabled")
        check(!NotchSmallBehaviour.isDisabled(target: CGSize(width: 300, height: 200), minimum: CGSize(width: 300, height: 200)), "exactly the minimum fits")
        check(NotchSmallBehaviour.isDisabled(target: CGSize(width: 800, height: 140), minimum: CGSize(width: 300, height: 200)), "shorter than minimum is disabled")
        check(!NotchSmallBehaviour.isDisabled(target: nil, minimum: CGSize(width: 9999, height: 9999)), "no target size never disables")
        // 读不到最小尺寸：按 200×150。
        check(NotchSmallBehaviour.isDisabled(target: CGSize(width: 199, height: 600), minimum: nil), "fallback width 200")
        check(NotchSmallBehaviour.isDisabled(target: CGSize(width: 600, height: 149), minimum: nil), "fallback height 150")
        check(!NotchSmallBehaviour.isDisabled(target: CGSize(width: 200, height: 150), minimum: nil), "fallback exact fit")
        check(NotchSmallBehaviour.isDisabled(target: CGSize(width: 199, height: 600), minimum: CGSize(width: 0, height: 0)), "zero minimum is unreadable")
        check(NotchSmallBehaviour.isDisabled(target: CGSize(width: 199, height: 600), minimum: CGSize(width: CGFloat.nan, height: 10)), "NaN minimum is unreadable")
        check(NotchSmallBehaviour.disabledReason == "屏幕太小，放不下", "reason text")
        check(NotchSmallBehaviour.disabledAlpha == 0.35, "disabled alpha")

        // 起飞 rect：有图标用图标，没有或无效就回到默认。
        let icon = CGRect(x: 100, y: 900, width: 24, height: 24)
        check(NotchSmallBehaviour.flightOrigin(icon: icon) == icon, "icon rect passes through")
        check(NotchSmallBehaviour.flightOrigin(icon: nil) == nil, "nil icon falls back")
        check(NotchSmallBehaviour.flightOrigin(icon: .zero) == nil, "empty icon falls back")
        check(NotchSmallBehaviour.flightOrigin(icon: CGRect(x: CGFloat.infinity, y: 0, width: 24, height: 24)) == nil, "non-finite icon falls back")

        // 时序常量。
        check(NotchSmallBehaviour.rowCollapseLag == 0.04, "row collapses 0.04s late")
        check(abs(NotchSmallBehaviour.tileFadeDelay(index: 0) - 0.09) < 1e-9, "first tile at 0.09")
        check(abs(NotchSmallBehaviour.tileFadeDelay(index: 3) - 0.21) < 1e-9, "fourth tile at 0.21")
        check(abs(NotchSmallBehaviour.tileFadeDelay(index: -2) - 0.09) < 1e-9, "negative index clamps")

        // 边线渐变：3 点以内看不见，20 点起全显。
        check(NotchSmallBehaviour.keyLineVisibility(atDepth: 0) == 0, "top edge hidden")
        check(NotchSmallBehaviour.keyLineVisibility(atDepth: 3) == 0, "3pt still hidden")
        check(abs(NotchSmallBehaviour.keyLineVisibility(atDepth: 11.5) - 0.5) < 1e-9, "midpoint half visible")
        check(NotchSmallBehaviour.keyLineVisibility(atDepth: 20) == 1, "20pt fully visible")
        check(NotchSmallBehaviour.keyLineVisibility(atDepth: 200) == 1, "below stays visible")
        let stops = NotchSmallBehaviour.keyLineLocations(layerHeight: 102, overscan: 2)
        check(stops.count == 4 && stops[0] == 0 && stops[3] == 1, "stops span the layer")
        check(abs(stops[1] - 5.0 / 102) < 1e-9 && abs(stops[2] - 22.0 / 102) < 1e-9, "stops at 3pt and 20pt below the island top")
        let squashed = NotchSmallBehaviour.keyLineLocations(layerHeight: 10, overscan: 2)
        check(squashed == squashed.sorted() && squashed.allSatisfy { $0 >= 0 && $0 <= 1 }, "short layer keeps stops ordered")
        check(NotchSmallBehaviour.keyLineLocations(layerHeight: 0, overscan: 2) == [0, 0, 1, 1], "zero height is safe")

        if failures == 0 { print("NotchSmallBehaviourTests: all passed") } else { print("\(failures) failure(s)"); exit(1) }
    }
}
