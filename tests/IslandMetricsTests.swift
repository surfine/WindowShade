// 岛的量法：圆角＝高/2、最小形＝高见方、紧凑最宽＝屏宽−2高（纯常量与纯函数）。
import Foundation

@MainActor
func runTests() {
    var failures = 0
    func check(_ ok: Bool, _ name: String) {
        if !ok { failures += 1; print("FAIL \(name)") }
    }
    typealias M = IslandMetrics

    check(M.inertHeight == 36, "本体高 36（macOS 的 36/18 整数对）")
    check(M.cornerRadius == M.inertHeight / 2, "圆角＝高/2（Apple 的 minimumContinuousCornerRadius）")
    check(M.cornerRadius == 18, "圆角 18")
    check(M.minimalSize == CGSize(width: 36, height: 36), "最小形＝本体高见方的圆")
    check(M.radius(forHeight: 64) == 32, "圆角由高度推")
    check(M.radius(forHeight: 0) >= 1, "高度 0 时圆角仍有下限")
    check(M.radius(forHeight: 3) == 1.5, "小高度按半高")

    check(M.maximumCompactWidth(screenWidth: 1000) == 928, "紧凑最宽＝屏宽−2×36")
    check(M.maximumCompactWidth(screenWidth: 40) == 36, "屏太窄时不小于本体高")
    check(M.capsuleExpandedSize.width > M.inertHeight && M.capsuleExpandedSize.height > M.inertHeight, "无刘海胶囊展开比本体大")
    check(M.capsuleExpandedSize == CGSize(width: 230, height: 64), "无刘海胶囊展开 230×64")
    check(M.notchExpandedMaxWidth == 408, "刘海屏展开上限 408（Aaron #29/#83）")
    check(M.externalExpandedMaxWidth == 371, "外接屏展开上限 371（Aaron #83）")
    check(M.expandedMaxWidth(hasNotch: true) == 408, "有刘海走 408")
    check(M.expandedMaxWidth(hasNotch: false) == 371, "外接屏走 371")
    check(M.expandedMaxHeight == 160, "展开高度上限 160（Aaron #29）")
    check(M.horizontalMinimalViewWidth == 45, "最小形旁 45（Apple maximumHorizontalMinimalViewSize）")

    check(M.dropIslandSize.width > M.dropIslandSize.height, "落点小岛是横的长方形")
    check(M.dropIslandSize == CGSize(width: 340, height: 84), "落点小岛 340×84（WS2 DropIsland）")
    check(M.dropIslandRadius == 22, "落点小岛圆角 22")
    check(M.dropIslandSize != M.capsuleExpandedSize, "落点与无刘海胶囊展开是两个自由度")

    let behavior = M.expandedBehavior(hasNotch: true, availableWidth: 1000)
    check(behavior.minWidth == 36 && behavior.preferredWidth == 408
          && behavior.idealWidth == 408 && behavior.maxWidth == 1000,
          "展开行为照固件的 min/preferred/ideal/max 四尺寸")
    check(behavior.resolvedWidth == 408, "没有内容时解出 408")
    let wide = M.expandedBehavior(hasNotch: true, availableWidth: 1000, contentWidth: 416)
    check(wide.idealWidth == 416 && wide.resolvedWidth == 416, "内容 416 抬高理想值")
    let narrow = M.expandedBehavior(hasNotch: true, availableWidth: 1000, contentWidth: 300)
    check(narrow.idealWidth == 408 && narrow.resolvedWidth == 408, "内容比 preferred 窄时仍用 preferred")
    check(M.expandedWidth(hasNotch: true, availableWidth: 1000) == 408, "没有内容：刘海屏展开 408")
    check(M.expandedWidth(hasNotch: false, availableWidth: 1000) == 371, "没有内容：外接屏展开 371")
    check(M.expandedWidth(hasNotch: true, availableWidth: 390) == 390, "屏幕放不下时按可用宽度收")
    check(M.expandedWidth(hasNotch: true, availableWidth: 1000, contentWidth: 416) == 416, "3 格窗口 416 不被 408 裁掉")
    check(M.expandedWidth(hasNotch: true, availableWidth: 1000, contentWidth: 300) == 408, "内容比系统窄时仍用 408")
    check(M.expandedWidth(hasNotch: false, availableWidth: 1000, contentWidth: 420) == 420, "外接屏内容可超 371")
    check(M.expandedWidth(hasNotch: true, availableWidth: 420, contentWidth: 500) == 420, "内容再宽也不出可用宽度")
    check(M.expandedWidth(hasNotch: true, availableWidth: 0) == 0, "可用宽度为 0 时不返回负值")

    if failures == 0 { print("PASS island-metrics") } else { print("FAILED \(failures)"); exit(1) }
}

@main struct Runner { @MainActor static func main() { runTests() } }
