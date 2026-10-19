import Darwin
import Foundation

private struct Suite {
    let name: String
    private var checks = 0
    private var failures = 0
    mutating func section(_ id: String, _ text: String) { print("CASE \(id) | \(text)") }
    mutating func expect(_ ok: Bool, _ text: String) {
        checks += 1
        if !ok { failures += 1 }
        print("\(ok ? "ok  " : "FAIL") \(text)")
    }
    func finish() {
        print(failures == 0 ? "PASS \(name): \(checks) assertions" : "FAIL \(name): \(failures)/\(checks)")
        exit(failures == 0 ? 0 : 1)
    }
}

@main
struct VoiceDraftTests {
    static func main() {
        var t = Suite(name: "voice-draft")
        var session = VoiceDraftSession()

        t.section("V-01", "只有空闲时能开始；重复开始不打断已经在说的这一句")
        t.expect(session.phase == .idle && !session.isActive, "初始空闲")
        t.expect(session.start(at: 10), "第一次能开始")
        t.expect(session.phase == .listening && session.startedAt == 10, "进入听写并记下起点")
        t.expect(!session.start(at: 11), "已经在听时不能再开一句")

        t.section("V-02", "部分结果只在听写时更新；松手后进入转写，不再改")
        session.update("先让开")
        t.expect(session.partial == "先让开", "听写时更新部分结果")
        t.expect(session.stop(at: 12), "松手进入转写")
        t.expect(session.phase == .transcribing, "阶段是转写")
        session.update("不该进来")
        t.expect(session.partial == "先让开", "转写后忽略部分结果")

        t.section("V-03", "最后结果去掉首尾空白；空结果算没听清")
        session.finish(.success("  待会儿回来。\n"))
        t.expect(session.phase == .idle && session.draft == "待会儿回来。", "草稿去掉首尾空白")
        t.expect(session.failure == nil, "成功时不带失败")
        var empty = VoiceDraftSession()
        _ = empty.start(at: 0)
        _ = empty.stop(at: 1)
        empty.finish(.success("   "))
        t.expect(empty.draft == nil && empty.failure == .empty, "空白结果 → 没听清")

        t.section("V-04", "60 秒上限：59.9 秒放行，60 秒当场作废")
        var long = VoiceDraftSession()
        _ = long.start(at: 100)
        t.expect(!long.tick(at: 159.9), "59.9 秒还在说")
        t.expect(long.phase == .listening, "仍在听写")
        t.expect(long.tick(at: 160), "到 60 秒作废")
        t.expect(long.phase == .idle && long.failure == .tooLong, "作废原因是超时")
        var late = VoiceDraftSession()
        _ = late.start(at: 0)
        t.expect(late.stop(at: 61) && late.failure == .tooLong, "超时后松手也作废")

        t.section("V-05", "识别器可以在松手前就给最后结果；不在这一句里的结果不接受")
        var early = VoiceDraftSession()
        _ = early.start(at: 0)
        early.finish(.success("短句"))
        t.expect(early.phase == .idle && early.draft == "短句", "听写中收到最后结果也收下")
        var stray = VoiceDraftSession()
        stray.finish(.success("没有开始过"))
        t.expect(stray.draft == nil && stray.phase == .idle, "空闲时忽略结果")

        t.section("V-06", "失败原因原样保留，不产生草稿")
        for failure in [VoiceDraftSession.Failure.onDeviceUnavailable, .notAuthorized, .interrupted] {
            var failed = VoiceDraftSession()
            _ = failed.start(at: 0)
            _ = failed.stop(at: 1)
            failed.finish(.failure(failure))
            t.expect(failed.failure == failure && failed.draft == nil, "\(failure) → 无草稿")
        }

        t.section("V-07", "取消清空这一句的一切")
        var cancelled = VoiceDraftSession()
        _ = cancelled.start(at: 0)
        cancelled.update("说了一半")
        cancelled.cancel()
        t.expect(cancelled.phase == .idle && cancelled.partial.isEmpty && cancelled.draft == nil &&
                 cancelled.failure == nil && cancelled.startedAt == nil, "取消后回到空闲")

        t.section("V-08", "草稿只由页面采用；清草稿只在空闲时生效")
        var cleared = VoiceDraftSession()
        _ = cleared.start(at: 0)
        _ = cleared.stop(at: 1)
        cleared.finish(.success("一句话"))
        cleared.clearDraft()
        t.expect(cleared.draft == nil, "空闲时可清草稿")
        t.expect(cleared.failure == nil, "清草稿不改变失败状态")
        cleared.finish(.success("已在空闲，忽略"))
        t.expect(cleared.draft == nil, "清掉之后旧结果不会再回来")
        _ = cleared.start(at: 2)
        t.expect(cleared.draft == nil && cleared.phase == .listening, "开始新一句时草稿交给页面，状态机不再持有")

        t.finish()
    }
}
