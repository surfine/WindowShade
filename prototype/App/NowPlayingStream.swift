import Cocoa

/// 正在播放的推送流（计划 2-1）：所有播放器，换曲、播放、暂停时系统推过来，不用定时去问。
///
/// 做法来自 ungive/mediaremote-adapter（BSD-3，源码在 prototype/Vendor/mediaremote-adapter/，
/// 固定提交见那里的 UPSTREAM.md）：macOS 15.4 起第三方进程直接调私有的 MediaRemote 会被拒，
/// 但系统自带的 perl 可以；所以让 perl 加载适配器框架，跑 `stream` 子命令，
/// 每次变化吐一行 JSON。Atoll 的 NowPlayingController（GPL）是同一思路，这里只借思路、没抄代码。
///
/// 边界：
/// - 默认开（`Notch.activities.nowPlayingStream` 没设过时是开，显式设过的不变；NP-4，Aaron 2026-10-09），
///   而且只在实时活动在跑、音乐开关开着时才启动。
/// - App 包里没有适配器（`Contents/Resources/` 里的 perl 脚本与
///   `Contents/Frameworks/MediaRemoteAdapter.framework`）就什么都不做，音乐照旧问 Music / Spotify。
/// - 子进程挂了按 1、2、4……秒重启，连续失败 8 次就留在问播放器的退路上，直到下次启动。
/// - 行解析在读管道的后台队列上做，主线程只收一份解析好的 `NowPlayingInfo`。
/// - 带 --no-artwork：推送流里封面不出子进程；解析器也只留白名单里的几个键。
///   封面换曲时由 NowPlayingArtwork 另用 adapter 的 get 取一次（4 MB 上限，缩到 128，只留最新一张在内存）。
@MainActor
final class NowPlayingStream {
    nonisolated static let enabledKey = NotchNowPlayingDefaults.streamKey
    nonisolated static var isEnabled: Bool { NotchNowPlayingDefaults.streamEnabled(in: .standard) }
    /// 只有显式开过才算：离开就锁暂停媒体沿用老行为，不因默认值变了就多读一个播放器。
    nonisolated static var isExplicitlyEnabled: Bool { NotchNowPlayingDefaults.streamExplicitlyEnabled(in: .standard) }

    struct Adapter: Sendable {
        let script: URL
        let framework: URL
    }

    /// 适配器在 App 包里的位置；两样都在才算有。
    nonisolated static func locateAdapter(in bundle: Bundle = .main) -> Adapter? {
        guard let resources = bundle.resourceURL, let frameworks = bundle.privateFrameworksURL else { return nil }
        let script = resources.appendingPathComponent("mediaremote-adapter.pl")
        let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
        let binary = framework.appendingPathComponent("MediaRemoteAdapter")
        let files = FileManager.default
        guard files.isReadableFile(atPath: script.path), files.fileExists(atPath: binary.path) else { return nil }
        return Adapter(script: script, framework: framework)
    }

    var onUpdate: ((NowPlayingInfo?) -> Void)?
    var onHealthChange: ((Bool) -> Void)?
    /// 判坏了（启动 10 秒内没有第一行，或 60 秒内退出 3 次）：来源去退路上读 Music / Spotify，那时才可能问“自动化”授权。
    var onGiveUp: (() -> Void)?
    /// 子进程在跑、而且吐过至少一行有效数据。
    private(set) var isHealthy = false
    private(set) var latest: NowPlayingInfo?

    private var wanted = false
    private var process: Process?
    private var generation = 0
    private var failures = 0
    private var healthySince: TimeInterval?
    /// 从什么时候起一直没有数据（启动时、或最近一次断开时）；健康时 nil。判坏用它。
    private var unhealthySince: TimeInterval?
    private var exitStamps: [TimeInterval] = []
    private var adapterPresent = false
    private var verdictTimer: Timer?
    private var restartTimer: Timer?
    private var terminateObserver: NSObjectProtocol?

    func start() {
        guard !wanted, Self.isEnabled, Self.locateAdapter() != nil else { return }
        wanted = true
        failures = 0
        exitStamps = []
        adapterPresent = true
        markUnhealthy()
        if terminateObserver == nil {
            terminateObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.stop() }
                }
        }
        launch()
    }

    func stop() {
        guard wanted || process != nil else { return }
        wanted = false
        restartTimer?.invalidate(); restartTimer = nil
        verdictTimer?.invalidate(); verdictTimer = nil
        unhealthySince = nil
        exitStamps = []
        generation += 1
        terminateChild()
        latest = nil
        setHealthy(false)
    }

    private func launch() {
        guard wanted, process == nil, let adapter = Self.locateAdapter() else { return }
        generation += 1
        let token = generation
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [adapter.script.path, adapter.framework.path,
                          "stream", "--no-diff", "--no-artwork", "--micros", "--debounce=150"]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        let reader = NowPlayingStreamReader()
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
            guard let info = reader.feed(chunk) else { return }
            DispatchQueue.main.async { self?.received(info, token: token) }
        }
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.exited(token: token) }
        }
        do {
            try task.run()
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
            exited(token: token)
            return
        }
        process = task
    }

    private func received(_ info: NowPlayingInfo?, token: Int) {
        guard token == generation, wanted else { return }
        latest = info
        if !isHealthy { healthySince = ProcessInfo.processInfo.systemUptime }
        unhealthySince = nil
        verdictTimer?.invalidate(); verdictTimer = nil
        setHealthy(true)
        onUpdate?(info)
    }

    private func exited(token: Int) {
        guard token == generation else { return }
        if let pipe = process?.standardOutput as? Pipe { pipe.fileHandleForReading.readabilityHandler = nil }
        process = nil
        let now = ProcessInfo.processInfo.systemUptime
        if let since = healthySince, now - since >= NotchActivityPollPolicy.streamStableAfter { failures = 0 }
        healthySince = nil
        failures += 1
        exitStamps.append(now)
        exitStamps = exitStamps.filter { now - $0 <= NowPlayingStreamVerdict.failureWindow }
        latest = nil
        markUnhealthy()
        setHealthy(false)
        if isGivenUp { onGiveUp?() }
        guard wanted, let delay = NotchActivityPollPolicy.streamRestartDelay(failures: failures) else { return }
        restartTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restartTimer = nil
                self?.launch()
            }
        }
        timer.tolerance = min(10, delay / 4)
        RunLoop.main.add(timer, forMode: .common)
        restartTimer = timer
    }

    /// 可以为退路（Music / Spotify）问“自动化”授权吗：推送流开着（默认开）、而且已经坏了或根本没装适配器。
    /// 推送正常、启动后 10 秒的观察期里一次都不问。
    var allowsAutomationPrompt: Bool {
        guard Self.isEnabled else { return false }
        return wanted ? isGivenUp : Self.locateAdapter() == nil
    }

    /// 判坏：适配器不在包里、60 秒内退出 3 次、或一直没有数据超过 10 秒。启动前（没要求它跑）不算坏。
    var isGivenUp: Bool {
        guard wanted else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        return NowPlayingStreamVerdict.isGivenUp(adapterPresent: adapterPresent,
                                                 unhealthyFor: unhealthySince.map { now - $0 },
                                                 recentExits: NowPlayingStreamVerdict.exits(in: exitStamps, now: now))
    }

    /// 没有数据的这一段从现在算起；排一次性的判坏检查（10 秒后），健康了或停了就撤。
    private func markUnhealthy() {
        if unhealthySince == nil { unhealthySince = ProcessInfo.processInfo.systemUptime }
        guard verdictTimer == nil else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - (unhealthySince ?? 0)
        let delay = max(0.5, NowPlayingStreamVerdict.firstLineDeadline - elapsed)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.verdictTimer = nil
                if self.wanted, !self.isHealthy, self.isGivenUp { self.onGiveUp?() }
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        verdictTimer = timer
    }

    private func terminateChild() {
        guard let task = process else { return }
        process = nil
        if let pipe = task.standardOutput as? Pipe { pipe.fileHandleForReading.readabilityHandler = nil }
        task.terminationHandler = nil
        // 适配器收到 SIGTERM 会停掉自己的 run loop 正常退出。
        if task.isRunning { task.terminate() }
    }

    private func setHealthy(_ healthy: Bool) {
        guard healthy != isHealthy else { return }
        isHealthy = healthy
        onHealthChange?(healthy)
    }

    /// 给正在报告的播放器发一个控制命令（MediaRemote 的 MRCommand 编号）。阻塞调用，只在后台队列用。
    nonisolated static func send(_ command: NotchMusicCommand, adapter: Adapter) {
        let id: String
        switch command {
        case .playPause: id = "2"
        case .next: id = "4"
        case .previous: id = "5"
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [adapter.script.path, adapter.framework.path, "send", id]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in finished.signal() }
        do { try task.run() } catch { return }
        if finished.wait(timeout: .now() + 2.5) == .timedOut, task.isRunning {
            task.terminate()
        }
    }
}

extension NowPlayingStream {
    /// 跳到播放器里的某个位置（秒）。走适配器的 `seek`（MediaRemote 的 setElapsedTime，参数是微秒）。
    /// 阻塞调用，只在后台队列用；松手那一下才调。
    nonisolated static func seek(toSeconds seconds: Double, adapter: Adapter) {
        guard seconds.isFinite, seconds >= 0, seconds < 86_400 * 10 else { return }
        let micros = Int((seconds * 1_000_000).rounded())
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [adapter.script.path, adapter.framework.path, "seek", String(micros)]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in finished.signal() }
        do { try task.run() } catch { return }
        if finished.wait(timeout: .now() + 2.5) == .timedOut, task.isRunning {
            task.terminate()
        }
    }
}

/// 读管道那一侧的状态：切行、解析，只把每块数据里最后一份现状交出去。
/// readabilityHandler 在系统的后台队列上串行调用；锁只为满足 Sendable，不会争用。
private final class NowPlayingStreamReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = NowPlayingLineBuffer()
    private var parser = NowPlayingStreamParser()

    /// 这块数据里有有效行就返回最后一份现状（外层 nil 表示没有可交付的更新）。
    func feed(_ chunk: Data) -> NowPlayingInfo?? {
        lock.lock(); defer { lock.unlock() }
        var result: NowPlayingInfo?? = nil
        for line in buffer.append(chunk) {
            if case .update(let info) = parser.consume(line) { result = .some(info) }
        }
        return result
    }
}
