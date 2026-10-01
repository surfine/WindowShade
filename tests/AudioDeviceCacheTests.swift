// AirPods 那段结果的缓存语义：CoreAudio 枚举设备一次 1.74ms，每 2 秒问一次就是常驻约 0.11% 单核，
// 所以只让它在「脏了」或超过 maxAge 时重算。这里钉住的就是那三个动作：
// 新建即脏、store 之后能在 maxAge 内复用、markDirty 之后必须重算、超龄必须重算，以及并发下不崩。
import Foundation

@main
struct AudioDeviceCacheTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        let cache = AudioDeviceCache()
        expect(cache.take(maxAge: 30) == nil, "a fresh cache is dirty, so the first poll recomputes")

        cache.store([])
        expect(cache.take(maxAge: 30)?.isEmpty == true, "after storing, an empty result is reused inside maxAge")

        cache.markDirty()
        expect(cache.take(maxAge: 30) == nil, "a device change marks it dirty and forces the next recompute")

        cache.store([])
        expect(cache.take(maxAge: 0) == nil, "and an entry older than maxAge is not reused")
        cache.store([])
        expect(cache.take(maxAge: 5)?.isEmpty == true, "a fresh store is reusable again")

        // 枚举途中设备又变了：这次的结果照存，但不能把那次变化吞掉、一直用到 30 秒兜底。
        cache.markDirty()
        expect(cache.take(maxAge: 30) == nil, "a change starts a recompute")
        cache.markDirty()
        cache.store([])
        expect(cache.take(maxAge: 30) == nil, "a change that lands mid-recompute forces one more recompute")
        cache.store([])
        expect(cache.take(maxAge: 30)?.isEmpty == true, "and after that clean recompute the cache is reused")

        // 并发：真实的调用点是「其它线程 markDirty、worker 线程 take/store」，这里照那个形状打一遍。
        let shared = AudioDeviceCache()
        shared.store([])
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            if index % 2 == 0 { shared.markDirty() } else { _ = shared.take(maxAge: 30); shared.store([]) }
        }
        expect(true, "concurrent markDirty / take / store do not crash")

        if failures == 0 { print("PASS: the audio device cache only recomputes when it is dirty or stale") }
        else { print("FAILED \(failures)"); exit(1) }
    }
}
