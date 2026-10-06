// PERF-08：活动来源多久问一次系统。
//
// 分两层：
// 1. `NotchActivityPollPolicy` 是纯函数——档位与间隔，任何机器上答案都一样。
// 2. 接上真的 `NotchActivitySources`：音乐关着、画面上也没有卡片时，4.5 秒里不该出现
//    2 秒一次的节奏；有通知（换曲/设备变化）时应当立刻再对一次账。
//
// 注意测试机状态会影响档位：插着 AirPods 时卡会出现，档位降到 10 秒。所以这里钉的是
// 「没有 2 秒节奏」与「档位跟策略一致」，不是「完全安静」。
import Cocoa

@main
struct NotchPollingTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        policyTests()

        _ = NSApplication.shared
        MainActor.assumeIsolated {
            UserDefaults.standard.setVolatileDomain([NotchActivitySources.musicKey: false], forName: UserDefaults.argumentDomain)
            let sources = NotchActivitySources()
            var deliveries = 0
            sources.onSnapshot = { _ in deliveries += 1 }
            sources.start()

            // 空闲档是 30 秒、来源档是 10 秒；4.5 秒够它走完第一轮，不够它走第二轮。
            run(seconds: 4.5)
            let idlePolls = sources.polls
            let tier = sources.currentTier
            let interval = sources.tickInterval
            expect(deliveries >= 1, "start() 之后至少交付过一次快照")
            expect(tier != .progress, "没有播放器时不会用进度的 2 秒档（实际 \(tier)）")
            expect(interval == NotchActivityPollPolicy.interval(for: tier), "tick 间隔和档位一致")
            expect(interval >= NotchActivityPollPolicy.sourceInterval, "音乐关着时不会每 2 秒问一次（实际 \(interval)s）")
            expect(idlePolls <= 2, "音乐关着、没有新通知时不会反复通问（4.5 秒内 \(idlePolls) 次）")

            // 换曲通知（播放器自己发的就是这个名字）：不用等下一个 tick，立刻再对一次账。
            DistributedNotificationCenter.default().postNotificationName(
                .init("com.apple.Music.playerInfo"), object: nil, userInfo: nil, deliverImmediately: true)
            run(seconds: 0.6)
            let notifiedPolls = sources.polls
            expect(notifiedPolls > idlePolls, "换曲通知触发一次对账（\(idlePolls) → \(notifiedPolls)）")

            // 停掉之后通知不该再唤醒它。
            sources.stop()
            DistributedNotificationCenter.default().postNotificationName(
                .init("com.apple.Music.playerInfo"), object: nil, userInfo: nil, deliverImmediately: true)
            run(seconds: 0.6)
            expect(sources.polls == notifiedPolls, "stop() 之后通知不再触发对账")
            expect(sources.tickInterval == 0, "stop() 之后没有留下的 tick")
        }

        if failures == 0 { print("PASS: activity polling backs off when there is nothing to watch, and wakes on notifications") }
        else { print("FAILED \(failures)"); exit(1) }
    }

    /// 纯逻辑：三档的判据、间隔与容忍度。
    private static func policyTests() {
        let p = NotchActivityPollPolicy.self
        expect(p.tier(hasPlayer: true, hasRecordingSource: true, hasVisibleCard: true) == .progress, "有播放器就是进度档")
        expect(p.tier(hasPlayer: false, hasRecordingSource: true, hasVisibleCard: false) == .source, "只有录音来源也要看着")
        expect(p.tier(hasPlayer: false, hasRecordingSource: false, hasVisibleCard: true) == .source, "画面上有卡片就还要更新")
        expect(p.tier(hasPlayer: false, hasRecordingSource: false, hasVisibleCard: false) == .idle, "什么都没有才空闲")
        expect(p.interval(for: .progress) == 2 && p.interval(for: .source) == 10 && p.interval(for: .idle) == 30,
               "三档的间隔分别是 2 / 10 / 30 秒")
        expect(p.tolerance(for: p.interval(for: .progress)) == 1, "进度档容忍 1 秒——进度条靠推算，不差这一秒")
        expect(p.tolerance(for: p.interval(for: .idle)) == 1, "容忍度上限 1 秒，空闲档不该被拖到 15 秒")
        expect(p.tolerance(for: 1) == 0.5, "短间隔按一半算")
        expect(p.tolerance(for: 3) == 1, "超过 2 秒的间隔一律只容忍 1 秒")
    }

    private static func run(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}
