// 诊断基础设施：日志、主线程活动标记、慢调用门限日志与卡顿哨兵。

import Cocoa

/// @unchecked Sendable 的理由：全部可变成员只在 queue 内访问；write 只捕获不可变字符串和 Date。
final class WindowShadeLogger: @unchecked Sendable {
    static let shared = WindowShadeLogger()
    private let queue = DispatchQueue(label: "WindowShade.log", qos: .utility)
    private var writer: SecureLogFile?
    private var disabled = false
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    func write(_ s: String) {
        let now = Date()
        queue.async { [weak self] in
            guard let self, !self.disabled else { return }
            do {
                if self.writer == nil { self.writer = try self.openWriter() }
                let line = "\(self.timeFormatter.string(from: now)) \(s)\n"
                try self.writer?.append(Data(line.utf8))
            } catch {
                // 不递归 wlog；不向公用位置回退，也不把这一行交给统一日志。
                self.writer?.closeFiles(); self.writer = nil; self.disabled = true
            }
        }
    }
    func flushAndClose() {
        // 和旧调用合同相同：只由外部非日志队列调用。关闭后不再开启文件。
        queue.sync { writer?.closeFiles(); writer = nil; disabled = true }
    }
    private func openWriter() throws -> SecureLogFile {
        if let override = getenv("WINDOWSHADE_LOG_PATH") {
            // 开发覆盖仍支持，但必须给专用、受保护、已存在的父目录。
            return try SecureLogFile(path: String(cString: override))
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WindowShade", isDirectory: true)
        // 创建只保证路径存在。SecureLogFile 随后逐级用 descriptor + NOFOLLOW 验证，未验证前不写日志。
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return try SecureLogFile(path: directory.appendingPathComponent("windowshade.log").path)
    }
}

func wlog(_ s: String) {
    WindowShadeLogger.shared.write(s)
}

/// 计时统一走单调时钟。`CFAbsoluteTimeGetCurrent`/`Date` 会随系统时间调整跳变，
/// 拿它测「主线程卡了多久」会在对时、时区或 NTP 修正时凭空造出一次假卡顿。
enum MonotonicClock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        if info.denom == 0 { info.numer = 1; info.denom = 1 }
        return info
    }()
    static func now() -> Double {
        Double(mach_absolute_time()) * Double(timebase.numer) / Double(timebase.denom)
            / 1_000_000_000
    }
}

/// 诊断开关。深度抓栈会暂停主线程、且本身有成本，只有明确要求时才启用；
/// 普通发布配置下既不建立 `WindowShade.stall-sampler` 线程，也不做周期性检查。
/// 需要时用 `WINDOWSHADE_STALL_SAMPLER=1`（或启动参数 `--stall-sampler`）打开，
/// 用 `WINDOWSHADE_STALL_SAMPLER_SECONDS=<秒>` 设总时限（默认 300，0 表示不自动停）。
enum Diagnostics {
    static func stallSamplerEnabled(
        environment: [String: String], arguments: [String]
    ) -> Bool {
        if environment["WINDOWSHADE_STALL_SAMPLER"] == "1" { return true }
        return arguments.contains("--stall-sampler")
    }

    static func stallSamplerWindow(environment: [String: String]) -> Double {
        guard let raw = environment["WINDOWSHADE_STALL_SAMPLER_SECONDS"],
            let value = Double(raw)
        else { return 300 }
        return value.isFinite ? max(0, value) : 300
    }

    static let stallSamplerOn = stallSamplerEnabled(
        environment: ProcessInfo.processInfo.environment, arguments: CommandLine.arguments)
    static let stallSamplerSeconds = stallSamplerWindow(
        environment: ProcessInfo.processInfo.environment)
}

/// 抓栈判定策略，独立成纯结构以便单测：卡顿超过阈值、且离上次抓栈够久、
/// 且这一轮还没抓满时，才抓下一张。返回序号（1 起）或 nil。
struct StallSamplerPolicy {
    let stallThreshold: Double
    let minSampleInterval: Double
    let maxSamples: Int
    private(set) var samples = 0
    private(set) var lastSampleAt = 0.0
    private var hasSampled = false

    init(stallThreshold: Double = 0.25, minSampleInterval: Double = 0.2, maxSamples: Int = 4) {
        self.stallThreshold = stallThreshold
        self.minSampleInterval = minSampleInterval
        self.maxSamples = maxSamples
    }

    mutating func reset() {
        samples = 0
        lastSampleAt = 0
        hasSampled = false
    }

    mutating func next(now: Double, stuck: Double) -> Int? {
        guard stuck > stallThreshold, samples < maxSamples else { return nil }
        // 第一张立即抓；之后每张之间至少隔 minSampleInterval（不用 0 当哨兵，免得恰好在 t=0 时绕过间隔）。
        if hasSampled, now - lastSampleAt < minSampleInterval { return nil }
        samples += 1
        lastSampleAt = now
        hasSampled = true
        return samples
    }
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

    /// 只在主线程读写：push/pop 先查 Thread.isMainThread，attribution 只由主线程上的卡顿哨兵调用。
    nonisolated(unsafe) private static var stack: [(label: String, start: CFAbsoluteTime)] = []
    nonisolated(unsafe) private static var recent: [Span] = []
    private static let maxSpans = 512

    static func push(_ label: String) {
        guard Thread.isMainThread else { return }
        stack.append((label, MonotonicClock.now()))
    }

    static func pop() {
        guard Thread.isMainThread, let item = stack.popLast() else { return }
        recent.append(Span(label: item.label, start: item.start, end: MonotonicClock.now()))
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
    let start = MonotonicClock.now()
    MainThreadActivity.push(label)
    let result = body()
    MainThreadActivity.pop()
    let elapsed = MonotonicClock.now() - start
    if elapsed >= threshold {
        wlog("slow: \(label) took \(Int(elapsed * 1000))ms")
    }
    return result
}

/// 主线程卡顿判定：把「上次活动的时刻 + 这一次是不是刚从等待回来」变成「报不报、报多久」。
/// 独立成纯结构，以便用确定性的单测覆盖「空闲休眠不误报、真阻塞要报」。
struct StallDetector {
    let threshold: Double
    private(set) var lastActivityAt: Double
    /// 上一次活动是不是 `.beforeWaiting`。是的话，接下来的长间隔只可能是休眠。
    private var previousWasBeforeWaiting: Bool

    init(threshold: Double = 0.5, now: Double) {
        self.threshold = threshold
        self.lastActivityAt = now
        // 启动时按“刚从等待回来”处理，免得把启动序列那段算成卡顿。
        self.previousWasBeforeWaiting = true
    }

    /// 每次 RunLoop 活动调用；返回这次要上报的卡顿时长（秒），不报时为 nil。
    /// 真阻塞（卡在同步调用里）期间 RunLoop 不可能入睡，恢复后首个回调必然不是 `.afterWaiting`；
    /// 反之，以 `.afterWaiting` 结束的长间隔一律是休眠唤醒，即使没先看到 `.beforeWaiting`。
    mutating func observe(now: Double, isBeforeWaiting: Bool, isAfterWaiting: Bool) -> Double? {
        let gap = now - lastActivityAt
        let reported = (!previousWasBeforeWaiting && !isAfterWaiting && gap > threshold) ? gap : nil
        lastActivityAt = now
        previousWasBeforeWaiting = isBeforeWaiting
        return reported
    }
}

// 主线程卡顿哨兵：主 RunLoop 的 observer 在每次活动回调时测量与上次活动的间隔，
// 上次状态为"非休眠等待"且间隔 >0.5s 即为真卡顿（主线程被同步调用阻塞后恢复）。
// 由主线程恢复后自我报告：空闲休眠（wasWaiting=true 的长间隔）与 App Nap 不会
// 误报，也不依赖任何后台计时器（后台计时器本身会被 App Nap 节流产生假长间隔）。
// 状态只在主线程访问，无锁；每次 RunLoop 活动仅一次取时和比较。
final class MainThreadStallSentinel {
    /// 见上：只在主线程访问。
    nonisolated(unsafe) static let shared = MainThreadStallSentinel()

    private var observer: CFRunLoopObserver?
    private var detector = StallDetector(now: MonotonicClock.now())
    /// 诊断开关在启动时定下，之后不变；关掉时每次 RunLoop 活动连一次取锁都省掉。
    private var samplesStacks = false

    func start() {
        guard observer == nil else { return }
        samplesStacks = Diagnostics.stallSamplerOn
        let activities: CFRunLoopActivity = [.beforeTimers, .beforeSources, .beforeWaiting, .afterWaiting]
        let obs = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, activities.rawValue, true, 0) { [weak self] _, activity in
            guard let self else { return }
            let now = MonotonicClock.now()
            let isBeforeWaiting = activity == .beforeWaiting
            let isAfterWaiting = activity == .afterWaiting
            if let gap = self.detector.observe(
                now: now, isBeforeWaiting: isBeforeWaiting, isAfterWaiting: isAfterWaiting)
            {
                let blame = MainThreadActivity.attribution(since: now - gap, until: now)
                wlog("main-thread stall ≈\(Int(gap * 1000))ms 期间=\(blame)")
                self.stalls += 1
                self.longestStall = max(self.longestStall, gap * 1000)
            }
            self.wasWaiting = isBeforeWaiting
            if self.samplesStacks { MainThreadSampler.shared.beat(waiting: isBeforeWaiting) }
        }
        observer = obs
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, CFRunLoopMode.commonModes)
        MainThreadSampler.shared.start()
    }

    /// 最近一次观察到的等待状态，仅诊断读取用。
    private(set) var wasWaiting = true
    /// 报过的卡顿次数与最长一次（毫秒）。资格测试读它做门槛，不再只从日志里数。
    private(set) var stalls = 0
    private(set) var longestStall = 0.0

    /// observer 装上了没有。没装上时资格测试必须记 `not_available`，不能把「没量」当 0 通过。
    var isRunning: Bool { observer != nil }

    /// 资格测试用（主线程）：读此刻的累计计数；`reset` 为真时一并归零，
    /// 让「这一段」的停顿只算这一段，不带上前面启动序列的账。
    @discardableResult
    func stallCounters(reset: Bool = false) -> (count: Int, longestMs: Double) {
        let out = (stalls, longestStall)
        if reset { stalls = 0; longestStall = 0 }
        return out
    }
}

// 卡顿时抓主线程的调用栈。哨兵只能在卡顿结束后报时长，“期间=未标记”说不出是谁；
// 这里另起一条看门狗线程，主线程超过 250ms 没回到 RunLoop（又不是在睡觉）时，暂停它一下，
// 沿帧指针链抄下返回地址，马上放开，再在看门狗线程上查符号写进日志。
// 一次卡顿最多抓 4 张（每张至少隔 200ms）：一秒多的长卡顿能自己分成几段，
// 不会像以前那样只留下第一张（2026-10-01：CoreAudio 那张抓到了，同一次卡顿的后半段完全看不见）。
// 这是一条**只在诊断开关打开时才存在**的线程；平时每 200ms 才读一次时间戳（阈值 250ms，见 StallSamplerPolicy）。
// 自家代码记“镜像+偏移”，用 atos 对着构建出来的程序就能还原到行。
final class MainThreadSampler: @unchecked Sendable {
    static let shared = MainThreadSampler()

    private var lock = os_unfair_lock()
    private var beatAt = MonotonicClock.now()
    private var busy = false
    private var policy = StallSamplerPolicy()
    private var mainThread: thread_act_t = 0
    private var stackLow: UInt = 0
    private var stackHigh: UInt = 0
    private var running = false
    private var paused = false
    /// 抓栈总时限（单调时钟秒；0 表示不自动停）。
    private var deadline = 0.0
    /// 抓栈期间写入的固定缓冲：在建立线程之前一次性备好，暂停目标线程时不再分配。
    private var scratch: [UInt] = []
    private var sleepObservers: [NSObjectProtocol] = []

    /// 抓栈缓冲的容量，等于帧指针链的最大步数加程序计数器与链接寄存器。
    private static let scratchCount = 64

    /// 在主线程上调用一次。只有诊断开关打开时才真的建立看门狗线程。
    func start() {
        guard Thread.isMainThread, Diagnostics.stallSamplerOn else { return }
        os_unfair_lock_lock(&lock)
        guard !running else {
            os_unfair_lock_unlock(&lock)
            return
        }
        running = true
        paused = false
        busy = false
        policy.reset()
        mainThread = mach_thread_self()
        let top = UInt(bitPattern: pthread_get_stackaddr_np(pthread_self()))
        stackHigh = top
        stackLow = top - UInt(pthread_get_stacksize_np(pthread_self()))
        let window = Diagnostics.stallSamplerSeconds
        deadline = window > 0 ? MonotonicClock.now() + window : 0
        beatAt = MonotonicClock.now()
        os_unfair_lock_unlock(&lock)
        // 分配必须在任何 thread_suspend 之前完成：暂停目标线程后再分配，可能正好等它持有的分配器锁。
        scratch = Array(repeating: 0, count: Self.scratchCount)
        installSleepObservers()
        let watchdog = Thread { [weak self] in self?.watch() }
        watchdog.name = "WindowShade.stall-sampler"
        watchdog.qualityOfService = .utility
        watchdog.start()
        wlog("diagnostics: stall sampler on window=\(Int(window))s")
    }

    var isRunning: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return running
    }

    /// 停止抓栈并摘掉睡眠观察者；可重复调用。诊断开关关闭时是空操作。
    func stop() {
        let observers: [NSObjectProtocol]
        os_unfair_lock_lock(&lock)
        guard running else {
            os_unfair_lock_unlock(&lock)
            return
        }
        running = false
        observers = sleepObservers
        sleepObservers = []
        os_unfair_lock_unlock(&lock)
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    }

    /// 主线程每次 RunLoop 活动时调用（只有开关打开时才会被调用）。
    func beat(waiting: Bool) {
        os_unfair_lock_lock(&lock)
        beatAt = MonotonicClock.now()
        busy = !waiting
        policy.reset()
        os_unfair_lock_unlock(&lock)
    }

    private func installSleepObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let sleep = center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.setPaused(true) }
        let wake = center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.setPaused(false) }
        os_unfair_lock_lock(&lock)
        sleepObservers = [sleep, wake]
        os_unfair_lock_unlock(&lock)
    }

    /// 睡眠期间不抓栈；醒来时把基准时间重新对到现在，避免把睡过去的那段算成卡顿。
    private func setPaused(_ value: Bool) {
        os_unfair_lock_lock(&lock)
        paused = value
        if !value {
            beatAt = MonotonicClock.now()
            busy = false
            policy.reset()
        }
        os_unfair_lock_unlock(&lock)
    }

    private func watch() {
        while true {
            // 200ms：卡顿阈值是 250ms，这个粒度够（检测到的时间点是 250–450ms，报的是真实卡了多久），
            // 但唤醒从 20 次/秒降到 5 次/秒——锁屏空闲那 0.1% 里相当一部分就是这类唤醒
            // （2026-10-01 量过：把铰链/AirPods 这些真活儿都拿掉之后，剩下的基本是定时器）。
            usleep(200_000)
            os_unfair_lock_lock(&lock)
            guard running else {
                os_unfair_lock_unlock(&lock)
                return
            }
            guard !paused else {
                os_unfair_lock_unlock(&lock)
                continue
            }
            let now = MonotonicClock.now()
            if deadline > 0, now >= deadline {
                running = false
                os_unfair_lock_unlock(&lock)
                wlog("diagnostics: stall sampler reached its time limit")
                return
            }
            let stuck = busy ? now - beatAt : 0
            let index = policy.next(now: now, stuck: stuck)
            let mainThread = self.mainThread
            os_unfair_lock_unlock(&lock)
            guard let index else { continue }
            let frames = captureMainStack(mainThread: mainThread)
            guard !frames.isEmpty else { continue }
            let described = frames.prefix(32).map(Self.describe)
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

    /// 暂停主线程，抄下返回地址，立刻放开。暂停区间只做「读寄存器/读栈 + 写预先备好的缓冲」：
    /// 不分配、不格式化、不解析符号、不写日志；`defer` 保证一定恢复，查符号与日志都排在放开之后。
    /// 仅把缓冲预先备好不足以证明整个采样器安全，这一点单独审查，不以「跑十分钟没崩」代替。
    private func captureMainStack(mainThread: thread_act_t) -> [UInt] {
        guard mainThread != 0, scratch.count >= Self.scratchCount,
            thread_suspend(mainThread) == KERN_SUCCESS
        else { return [] }
        defer { thread_resume(mainThread) }
        var written = 0
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(mainThread, ARM_THREAD_STATE64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            scratch[written] = Self.strip(UInt(state.__pc))
            written += 1
            scratch[written] = Self.strip(UInt(state.__lr))
            written += 1
            var fp = UInt(state.__fp)
            for _ in 0..<60 where written < Self.scratchCount {
                guard fp >= stackLow, fp + 16 <= stackHigh, fp % 8 == 0,
                      let slot = UnsafePointer<UInt>(bitPattern: fp) else { break }
                let next = slot[0]
                let ret = Self.strip(slot[1])
                if ret == 0 { break }
                scratch[written] = ret
                written += 1
                if next <= fp { break }
                fp = next
            }
        }
        // 复制发生在 thread_resume 之后（defer 已经生效），此处可以分配。
        return Array(scratch[0..<written])
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
