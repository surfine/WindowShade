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
    check(M.expandedSize.width > M.inertHeight && M.expandedSize.height > M.inertHeight, "展开比本体大")
    check(M.horizontalMinimalViewWidth == 45, "最小形旁 45（Apple maximumHorizontalMinimalViewSize）")

    check(M.pinnedTopSize.width > M.pinnedTopSize.height, "贴顶版是横的长方形")
    check(M.pinnedTopSize != M.expandedSize, "贴顶与展开是两个自由度")
    check(M.interpolate(from: M.minimalSize, to: M.expandedSize, progress: 0) == M.minimalSize, "t=0 是起点")
    check(M.interpolate(from: M.minimalSize, to: M.expandedSize, progress: 1) == M.expandedSize, "t=1 是终点")
    check(M.interpolate(from: M.minimalSize, to: M.expandedSize, progress: -5) == M.minimalSize, "负进度夹到 0")
    check(M.interpolate(from: M.minimalSize, to: M.expandedSize, progress: 9) == M.expandedSize, "超过 1 夹到终点")
    let mid = M.interpolate(from: M.minimalSize, to: M.expandedSize, progress: 0.5)
    check(mid.width == (36 + 230) / 2 && mid.height == (36 + 64) / 2, "中点线性")

    if failures == 0 { print("PASS island-metrics") } else { print("FAILED \(failures)"); exit(1) }
}

@main struct Runner { @MainActor static func main() { runTests() } }
