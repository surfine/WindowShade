// 卷轴维护（ScrollStripRun）按事件做之后的纯判定：哪些变化算“被人拖走”、新窗口够不够格、
// 够不够格但还没准备好时怎么重试。不碰窗口、不碰 AX，单独放这里好单独测。
//
// 改动前这些都在每半秒一次的对账里一把做完；现在窗口的挪动/隐藏/消失来自 WindowStateHub 的事件，
// 新窗口来自 SkyLight 的“加入桌面”（可能比 App 把窗口摆好还早），所以多了“还没准备好就稍后再试”这一层。

import CoreGraphics
import Foundation

enum StripWatchPolicy {
    /// 窗口实际位置/大小和最近一次摆上去的差超过这么多点，就当被人拖走、改了大小。
    static let dragThreshold: CGFloat = 24
    /// 新窗口至少这么大才算（比这小的是浮窗、面板）。
    static let minimumNewWidth: CGFloat = 240
    static let minimumNewHeight: CGFloat = 160

    /// 窗口实际外框离开最近摆的外框有多远算被人拖走（任一边超过 24 点）。
    static func draggedAway(actual: CGRect, expected: CGRect) -> Bool {
        abs(actual.minX - expected.minX) > dragThreshold || abs(actual.minY - expected.minY) > dragThreshold
            || abs(actual.width - expected.width) > dragThreshold || abs(actual.height - expected.height) > dragThreshold
    }

    enum Drift: Equatable {
        /// 没被拖走，或这扇窗不归这条规则管（停在边上的、正拖着标题栏的）。
        case none
        /// 被人拖走了：忘掉这扇窗的排布，让出位置。
        case forget
        /// 差得多，但卷轴自己刚挪过窗口（窗口还在路上）：过这么久再看一次，不丢这次变化。
        case recheck(after: TimeInterval)
    }

    /// 一扇窗的变化落地后的“被拖走”判定。quiet：卷轴自己没在挪（busyUntil 过了、没有动画）。
    /// busyRemaining：距离 busyUntil 还有多久（可以为负）。
    static func drift(actual: CGRect?, expected: CGRect?, quiet: Bool, busyRemaining: TimeInterval,
                      parked: Bool, holdsTitleDrag: Bool) -> Drift {
        guard let actual, let expected, !parked, !holdsTitleDrag, draggedAway(actual: actual, expected: expected) else { return .none }
        if quiet { return .forget }
        return .recheck(after: max(0.05, busyRemaining + 0.02))
    }

    /// 一列有变化后，补查收起/侧拉/收进刘海标记的延迟（标记可能晚于窗口事件才打上）。必须明显小于原来的 0.5 秒对账间隔。
    static let flagRecheckDelay: TimeInterval = 0.3

    /// 这扇卷轴里的窗要不要让出位置（不含被拖走）：看不到了（关掉、最小化、隐藏、层级变了），
    /// 或被收起、侧拉、收进刘海。
    static func leaves(visible: Bool, flagged: Bool) -> Bool { flagged || !visible }

    enum Eligibility: Equatable {
        case eligible
        /// 不是现在就不是：自己的窗口，或临时 App 模式下别的 App 的窗口。
        case never
        /// 现在不够格（太小、不在这块屏上），窗口可能还没摆好：值得稍后再看。
        case notYet
    }

    /// 新窗口的几何与归属检查（辅助功能那几项另外问）。
    static func newWindowEligibility(pid: pid_t, bounds: CGRect, ownPID: pid_t, arrangeOnly: pid_t?,
                                     screenAX: CGRect) -> Eligibility {
        if pid == ownPID { return .never }
        if let arrangeOnly, arrangeOnly != pid { return .never }
        guard bounds.width >= minimumNewWidth, bounds.height >= minimumNewHeight,
              screenAX.contains(CGPoint(x: bounds.midX, y: bounds.midY)) else { return .notYet }
        return .eligible
    }

    /// “加入桌面”事件可能先于 App 把窗口摆好、让辅助功能看得到：第一次立刻试，之后 0.15 秒、0.4 秒（自事件起）各再试一次。
    /// 返回下一次试之前等多久；试完了返回 nil（交给 1 秒心跳的整轮对账，和改动前的 0.5 秒轮询一样会再看到它）。
    static let appearanceAttemptTimes: [TimeInterval] = [0, 0.15, 0.4]
    static func appearanceRetryDelay(afterAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 0, attempt + 1 < appearanceAttemptTimes.count else { return nil }
        return appearanceAttemptTimes[attempt + 1] - appearanceAttemptTimes[attempt]
    }

    /// 各列的事实不是同一时刻采的（每列只在自己的事件落地时才刷新）：有一列看起来不在屏上，别的列可能还停在旧的“在屏上”。
    /// 这时不能拿它们去判“让出”，先对所有列重问一次，得到同一时刻的快照。
    static func needsCoherentSnapshot(visible: [Bool]) -> Bool { visible.contains(false) }

    /// 同一时刻的快照里卷轴的窗口一扇都不在屏上：切到了别的桌面、锁了屏、调度中心开着，这时不核对（和原来整轮对账一样）。
    static func nothingOnScreen(visible: [Bool]) -> Bool { !visible.contains(true) }

    /// 卷轴自己在挪窗口时列的订阅暂停，只靠一个半秒的“关掉了没有”检查兜关窗（和原来的 0.5 秒对账一样慢）。
    static let busyCheckInterval: TimeInterval = 0.5

    /// 新窗口 1325 之后前几次都没成，再临时盯它这么久：它挪动、改大小、显示时立刻重试，另外每 0.5 秒也试一次
    /// （辅助功能晚点才看得到它是没有事件的）。过了这个时间就交给 1 秒心跳。
    static let lateWatchDuration: TimeInterval = 3
    static let lateRetryInterval: TimeInterval = 0.5
    /// 临时盯着的第 elapsed 秒，下一次定时重试前等多久；盯够了返回 nil。
    static func lateRetryDelay(elapsed: TimeInterval) -> TimeInterval? {
        guard elapsed < lateWatchDuration else { return nil }
        return min(lateRetryInterval, lateWatchDuration - elapsed)
    }
}
