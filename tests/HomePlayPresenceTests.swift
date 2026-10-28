// F1-B 桥（WS2HomePlayPresenceSource）的纯逻辑侧：解析、翻转去抖、事件序列。
// 不开网络——feed 走 probeFeed。
import Foundation

@main
struct HomePlayPresenceTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    @MainActor final class Recorder {
        var batches: [[PresenceLock.Event]] = []
        var all: [PresenceLock.Event] { batches.flatMap { $0 } }
        func emit(_ events: [PresenceLock.Event]) { batches.append(events) }
        func connectAndCount(source: WS2HomePlayPresenceSource) { source.start { self.emit($0) } }
    }

    @MainActor static func main() {
        WS2HomePlayPresenceSource.debounce = 0   // 测试不走网络抖动
        let source = WS2HomePlayPresenceSource()
        let recorder = Recorder()
        source.start { recorder.emit($0) }

        // 1. 正常 verified=true：connect + 一对 read 回执。
        expect(source.probeFeed(#"{"type":"phone-presence","verified":true,"generation":1}"#), "feeds accepted")
        let first = recorder.all
        expect(first.contains { if case .connected(.phone, _) = $0 { return true }; return false }, "verified→connected")
        expect(first.contains { if case .readSucceeded(.phone, _, _) = $0 { return true }; return false }, "read receipt attached")
        expect(first.allSatisfy { if case .rssi = $0 { return false }; return true }, "no rssi (we don't invent one)")

        // 2. 同值重复：不发。
        let countBefore = recorder.all.count
        _ = source.probeFeed(#"{"type":"phone-presence","verified":true,"generation":2}"#)
        expect(recorder.all.count == countBefore, "same value stays silent")

        // 3. 别的类型/坏 JSON：不吃。
        expect(!source.probeFeed(#"{"type":"session","state":"started"}"#), "other types ignored")
        expect(!source.probeFeed("not json"), "bad json ignored")

        // 4. 翻转为 false：disconnected + 回执。
        expect(source.probeFeed(#"{"type":"phone-presence","verified":false,"generation":3}"#), "flip accepted")
        expect(recorder.all.contains { if case .disconnected(.phone, _) = $0 { return true }; return false }, "false→disconnected")

        // 5. 非法负载（verified 非布尔）：不崩、不吃。
        let safe = recorder.all.count
        expect(!source.probeFeed(#"{"type":"phone-presence","verified":"yes"}"#), "non-bool ignored")

        // 6. 未 start（emit 为 nil）时拒绝。
        let idle = WS2HomePlayPresenceSource()
        expect(!idle.probeFeed(#"{"type":"phone-presence","verified":true}"#), "not started refuses")

        _ = safe
        print("\(failures == 0 ? "PASS" : "FAIL") HomePlayPresence: \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
