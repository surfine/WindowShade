// 实时活动 → 岛的六态（C03）：种类不重不漏，每一类落在预期状态；
// 等你的编程会话和录音用 prompt（islandPrompt）。
import Foundation

@main
struct NotchActivityMotionTests {
    static func activity(_ kind: NotchActivityKind, phase: NotchSessionPhase? = nil) -> NotchActivity {
        NotchActivity(id: "probe-\(kind.rawValue)", kind: kind, title: "", startedAt: 0, sessionPhase: phase)
    }

    static func main() {
        var t = TestSuite("C03")

        t.section("C03-01", "一直在的：编程会话／遥控器／耳机／文件架 → thinking")
        for kind in [NotchActivityKind.session, .remote, .airPods, .shelf] {
            t.expect(kind.motionState == .thinking, "\(kind.rawValue) → thinking")
        }

        t.section("C03-02", "要你注意的：录音 → prompt（islandPrompt）")
        t.expect(NotchActivityKind.recording.motionState == .prompt, "recording → prompt")
        t.expect(NotchActivityKind.recording.motionState.systemTag == 5, "prompt 是 tag 5")

        t.section("C03-03", "有内容可看的：音乐／计时器／番茄钟／路线 → response")
        for kind in [NotchActivityKind.music, .timer, .focus, .route] {
            t.expect(kind.motionState == .response, "\(kind.rawValue) → response")
        }

        t.section("C03-04", "短暂变化：日程／隔空投送／下载／拷贝 → transient")
        for kind in [NotchActivityKind.calendar, .airDrop, .download, .copy] {
            t.expect(kind.motionState == .transient, "\(kind.rawValue) → transient")
        }

        t.section("C03-05", "等你的编程会话按 phase 换成 prompt，在跑的仍是 thinking")
        t.expect(activity(.session, phase: .waiting).motionState == .prompt, "session.waiting → prompt")
        t.expect(activity(.session, phase: .running).motionState == .thinking, "session.running → thinking")
        t.expect(activity(.session, phase: .done).motionState == .thinking, "session.done → thinking")
        t.expect(activity(.recording).motionState == .prompt, "activity(recording) → prompt")

        t.section("C03-06", "13 个种类全部覆盖，且没有活动占用 Siri 的 listening")
        t.expect(NotchActivityKind.allCases.count == 13, "13 个种类")
        let states = NotchActivityKind.allCases.map(\.motionState)
        t.expect(!states.contains(.listening), "没有 listening")
        t.expect(states.contains(.prompt), "prompt 只来自录音（等你的会话在 activity 层）")
        t.expect(Set(states.map(\.systemTag)) == Set([1, 2, 3, 5]), "落在 thinking／response／transient／prompt")

        t.finish()
    }
}
