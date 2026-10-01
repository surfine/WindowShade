// 诊断基础设施：日志、主线程活动标记、慢调用门限日志与卡顿哨兵。

import Cocoa

final class WindowShadeLogger {
    static let shared = WindowShadeLogger()

    private let url = URL(fileURLWithPath: getenv("WINDOWSHADE_LOG_PATH").map { String(cString: $0) } ?? "/tmp/windowshade.log")
    private let queue = DispatchQueue(label: "WindowShade.log", qos: .utility)
    private var handle: FileHandle?
    private let maxLogSize: UInt64 = 5 * 1024 * 1024

    // 时间戳在后台队列格式化；Date() 捕获发生在调用线程，保证反映真实记录时刻。
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func write(_ s: String) {
        let now = Date()
        queue.async { [weak self] in
            guard let self else { return }
            let line = "\(self.timeFormatter.string(from: now)) \(s)\n"
            guard let data = line.data(using: .utf8) else { return }
            self.append(data)
        }
    }

    func flushAndClose() {
        queue.sync {
            try? handle?.synchronize()
            try? handle?.close()
            handle = nil
        }
    }

    private func append(_ data: Data) {
        if handle == nil {
            openHandle()
        }
        // 超限轮转：当前文件改名 .1（覆盖旧备份）后开新文件，避免长期运行的
        // 菜单栏工具把 /tmp 日志无限写大、挤占磁盘。
        if let handle, handle.offsetInFile + UInt64(data.count) > maxLogSize {
            rotate()
        }
        handle?.write(data)
    }

    private func rotate() {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        let backup = URL(fileURLWithPath: url.path + ".1")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
        openHandle()
    }

    private func openHandle() {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
    }
}

func wlog(_ s: String) {
    WindowShadeLogger.shared.write(s)
}

// 主线程正在做什么。卡顿哨兵只能在阻塞结束之后才拿到控制权，光报时长无法定位；
// 记下当前活动之后，「stall ≈1054ms」就变成「stall ≈1054ms 期间=duo: desktop show」。
// 只在主线程记账，因此不需要加锁。
enum MainThreadActivity {
    private struct Span {
        let label: String
        let start: CFAbsoluteTime
        let end: CFAbsoluteTime
    }

    private static var stack: [(label: String, start: CFAbsoluteTime)] = []
    private static var recent: [Span] = []
    private static let maxSpans = 512

    static func push(_ label: String) {
        guard Thread.isMainThread else { return }
        stack.append((label, CFAbsoluteTimeGetCurrent()))
    }

    static func pop() {
        guard Thread.isMainThread, let item = stack.popLast() else { return }
        recent.append(Span(label: item.label, start: item.start, end: CFAbsoluteTimeGetCurrent()))
        if recent.count > maxSpans { recent.removeFirst(recent.count - maxSpans) }
    }

    /// 卡顿窗口里累计占用最久的标记，附带次数与占比。
    /// 报「最后结束的那个」会误导：几秒的连续忙碌通常由几十次短调用组成，
    /// 末尾那次往往只是恰好排在最后，而不是真正的大头。
    static func attribution(since: CFAbsoluteTime, until: CFAbsoluteTime) -> String {
        var totals: [String: (seconds: Double, count: Int)] = [:]
        func accumulate(_ label: String, from start: CFAbsoluteTime, to end: CFAbsoluteTime) {
            let overlap = min(end, until) - max(start, since)
            guard overlap > 0 else { return }
            var entry = totals[label] ?? (0, 0)
            entry.seconds += overlap
            entry.count += 1
            totals[label] = entry
        }
        for span in recent { accumulate(span.label, from: span.start, to: span.end) }
        for active in stack { accumulate(active.label, from: active.start, to: until) }
        guard let top = totals.max(by: { $0.value.seconds < $1.value.seconds }) else { return "未标记" }
        let window = until - since
        let share = window > 0 ? Int((top.value.seconds / window * 100).rounded()) : 0
        return "\(top.key)×\(top.value.count) 占 \(share)%"
    }
}

/// 给主线程上那些自己不打日志的同步段落加标记，只为卡顿归因，不产生日志。
@discardableResult
func marking<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
    MainThreadActivity.push(label)
    defer { MainThreadActivity.pop() }
    return try body()
}

// 包裹疑似昂贵的同步块；超过阈值才记日志，避免刷屏。
@discardableResult
func logIfSlow<T>(_ label: String, threshold: TimeInterval = 0.05, _ body: () -> T) -> T {
    let start = CFAbsoluteTimeGetCurrent()
    MainThreadActivity.push(label)
    let result = body()
    MainThreadActivity.pop()
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    if elapsed >= threshold {
        wlog("slow: \(label) took \(Int(elapsed * 1000))ms")
    }
    return result
}

// 主线程卡顿哨兵：主 RunLoop 的 observer 在每次活动回调时测量与上次活动的间隔，
// 上次状态为"非休眠等待"且间隔 >0.5s 即为真卡顿（主线程被同步调用阻塞后恢复）。
// 由主线程恢复后自我报告：空闲休眠（wasWaiting=true 的长间隔）与 App Nap 不会
// 误报，也不依赖任何后台计时器（后台计时器本身会被 App Nap 节流产生假长间隔）。
// 状态只在主线程访问，无锁；每次 RunLoop 活动仅一次取时和比较。
final class MainThreadStallSentinel {
    static let shared = MainThreadStallSentinel()

    private var observer: CFRunLoopObserver?
    private var lastActivityAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var wasWaiting = true

    func start() {
        guard observer == nil else { return }
        let activities: CFRunLoopActivity = [.beforeTimers, .beforeSources, .beforeWaiting, .afterWaiting]
        let obs = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, activities.rawValue, true, 0) { [weak self] _, activity in
            guard let self else { return }
            let now = CFAbsoluteTimeGetCurrent()
            // 真阻塞（卡在回调/同步调用里）期间 RunLoop 不可能入睡，恢复后的首个回调
            // 必然不是 afterWaiting；反之，以 afterWaiting 结束的长间隔一律是休眠唤醒
            // （即使因回调时序没先看到 beforeWaiting），不是卡顿，不报告。
            if !self.wasWaiting, activity != .afterWaiting, now - self.lastActivityAt > 0.5 {
                let blame = MainThreadActivity.attribution(since: self.lastActivityAt, until: now)
                wlog("main-thread stall ≈\(Int((now - self.lastActivityAt) * 1000))ms 期间=\(blame)")
            }
            self.lastActivityAt = now
            self.wasWaiting = activity == .beforeWaiting
            MainThreadSampler.shared.beat(waiting: self.wasWaiting)
        }
        observer = obs
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, CFRunLoopMode.commonModes)
        MainThreadSampler.shared.start()
    }
}

// 卡顿时抓主线程的调用栈。哨兵只能在卡顿结束后报时长，“期间=未标记”说不出是谁；
// 这里另起一条看门狗线程，主线程超过 250ms 没回到 RunLoop（又不是在睡觉）时，暂停它一下，
// 沿帧指针链抄下返回地址，马上放开，再在看门狗线程上查符号写进日志。
// 一次卡顿最多抓 4 张（每张至少隔 200ms）：一秒多的长卡顿能自己分成几段，
// 不会像以前那样只留下第一张（2026-10-01：CoreAudio 那张抓到了，同一次卡顿的后半段完全看不见）。
// 平时每 50ms 只读一次时间戳。自家代码记“镜像+偏移”，用 atos 对着构建出来的程序就能还原到行。
final class MainThreadSampler: @unchecked Sendable {
    static let shared = MainThreadSampler()

    private var lock = os_unfair_lock()
    private var beatAt = CFAbsoluteTimeGetCurrent()
    private var busy = false
    private var samples = 0
    private var lastSampleAt: CFAbsoluteTime = 0
    private var mainThread: thread_act_t = 0
    private var stackLow: UInt = 0
    private var stackHigh: UInt = 0
    private var started = false

    /// 在主线程上调用一次。
    func start() {
        guard Thread.isMainThread, !started else { return }
        started = true
        mainThread = mach_thread_self()
        let top = UInt(bitPattern: pthread_get_stackaddr_np(pthread_self()))
        stackHigh = top
        stackLow = top - UInt(pthread_get_stacksize_np(pthread_self()))
        let watchdog = Thread { [weak self] in self?.watch() }
        watchdog.name = "WindowShade.stall-sampler"
        watchdog.qualityOfService = .utility
        watchdog.start()
    }

    /// 主线程每次 RunLoop 活动时调用。
    func beat(waiting: Bool) {
        os_unfair_lock_lock(&lock)
        beatAt = CFAbsoluteTimeGetCurrent()
        busy = !waiting
        samples = 0
        lastSampleAt = 0
        os_unfair_lock_unlock(&lock)
    }

    private func watch() {
        while true {
            // 200ms：卡顿阈值是 250ms，这个粒度够（检测到的时间点是 250–450ms，报的是真实卡了多久），
            // 但唤醒从 20 次/秒降到 5 次/秒——锁屏空闲那 0.1% 里相当一部分就是这类唤醒
            // （2026-10-01 量过：把铰链/AirPods 这些真活儿都拿掉之后，剩下的基本是定时器）。
            usleep(200_000)
            let now = CFAbsoluteTimeGetCurrent()
            os_unfair_lock_lock(&lock)
            let stuck = busy ? now - beatAt : 0
            let takeSample = busy && stuck > 0.25 && samples < 4 && now - lastSampleAt >= 0.2
            if takeSample { samples += 1; lastSampleAt = now }
            let index = samples
            os_unfair_lock_unlock(&lock)
            guard takeSample else { continue }
            let frames = captureMainStack()
            guard !frames.isEmpty else { continue }
            let described = frames.prefix(18).map(Self.describe)
            // 主线程其实在等输入：菜单、拖动这类跟踪循环跑在私有的 RunLoop 模式里，看不到它入睡，但它是闲着的，不算卡顿。
            if described.contains(where: { $0.contains("ReceiveNextEventCommon") || $0.contains("BlockUntilNextEventMatchingListInMode") }) {
                // 哨兵只看 runloop 活动，分辨不出「跟踪循环」和「真冻结」，两边会给出矛盾的两行日志。
                // 这里把它如实记成 tracking（2026-10-01 排查 5 秒级卡顿时被这两行绕进去过）。
                if index == 1 {
                    wlog("main-thread tracking ≈\(Int(stuck * 1000))ms (menu or drag tracking; main thread is waiting for input, not frozen)")
                }
                continue
            }
            wlog("main-thread stall sample \(index)/4 ≈\(Int(stuck * 1000))ms: \(described.joined(separator: " ← "))")
        }
    }

    /// 暂停主线程，抄下返回地址，立刻放开。暂停期间不做任何可能拿锁的事（查符号放在放开之后）。
    private func captureMainStack() -> [UInt] {
        guard mainThread != 0, thread_suspend(mainThread) == KERN_SUCCESS else { return [] }
        var frames: [UInt] = []
        frames.reserveCapacity(64)
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(mainThread, ARM_THREAD_STATE64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            frames.append(Self.strip(UInt(state.__pc)))
            frames.append(Self.strip(UInt(state.__lr)))
            var fp = UInt(state.__fp)
            for _ in 0..<60 {
                guard fp >= stackLow, fp + 16 <= stackHigh, fp % 8 == 0,
                      let slot = UnsafePointer<UInt>(bitPattern: fp) else { break }
                let next = slot[0]
                let ret = Self.strip(slot[1])
                if ret == 0 { break }
                frames.append(ret)
                if next <= fp { break }
                fp = next
            }
        }
        thread_resume(mainThread)
        return frames
    }

    /// 去掉指针认证位（系统库的返回地址带签名）。
    private static func strip(_ address: UInt) -> UInt { address & 0x0000_7FFF_FFFF_FFFF }

    private static func describe(_ address: UInt) -> String {
        var info = Dl_info()
        guard dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0 else { return String(format: "0x%lx", address) }
        let image = info.dli_fname.map { URL(fileURLWithPath: String(cString: $0)).lastPathComponent } ?? "?"
        let offset = address - UInt(bitPattern: info.dli_fbase)
        // 自家程序记偏移（atos 还原）；系统库记符号名更直接。
        if image == "WindowShade" || info.dli_sname == nil {
            return "\(image)+0x\(String(offset, radix: 16))"
        }
        let name = String(cString: info.dli_sname!)
        return "\(image):\(name.count > 60 ? String(name.prefix(60)) + "…" : name)"
    }
}
