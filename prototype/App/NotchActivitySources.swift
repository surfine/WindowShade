import Cocoa
import Carbon
import CoreAudio
import ApplicationServices
import Synchronization

// A snapshot reports evidence, not a guessed recording/transport state.
struct NotchSourceSnapshot: Sendable, Equatable {
    let kind: NotchActivityKind
    let title: String
    let subtitle: String
    let symbol: String
    let progress: Double?
    let isPaused: Bool
    let detail: String
}
enum NotchMusicCommand: String { case playPause, previous, next }

@MainActor
final class NotchActivitySources {
    var onSnapshot: (([NotchSourceSnapshot]) -> Void)?
    private let worker = DispatchQueue(label: "com.windowshade.activities.sources", qos: .utility)
    private var timer: Timer?
    /// 这一轮用的是哪一档、间隔多少（PERF-08）。档位没变就不重建 timer，免得把倒数重置。
    private(set) var currentTier: NotchActivityTier = .idle
    private(set) var tickInterval: TimeInterval = 0
    /// 真的问过几次系统。空闲时这两项应当停住不动，测试和探针都看它。
    private(set) var polls: UInt64 = 0
    private var running = false
    private var epoch = 0
    private var busy = false
    /// 对账途中又来了一次通知：这一轮结束再来一轮，不丢变更也不排队。
    private var pendingPoll = false
    /// 上一次交付给宿主的快照条数：画面上有卡片就不算空闲。
    private var lastSnapshotCount = 0
    private var commandBusy = false
    private var workToken = ActivitySourceToken()
    private var musicApp: String?
    static let musicKey = NotchNowPlayingDefaults.musicKey
    /// 日程（CAL-2）：默认关；没授权时不建日历仓库对象。画面属 CAL-3，这里只暴露来源。
    static let calendarKey = "Notch.activities.calendarEnabled"
    let calendar = CalendarSource()
    /// 音乐：问播放器要启动一次 osascript（几十毫秒），所以只在播放器发通知（换曲、播放、暂停）、
    /// 播放器开关、点了控制、或 30 秒兜底时才问；其余时候进度条按上次读到的位置和经过的时间推算。
    private var musicDirty = true
    private var musicRead: (snapshot: NotchSourceSnapshot, position: Double?, duration: Double, at: TimeInterval)?
    private var musicReadAt: TimeInterval = 0
    private var musicObservers: [NSObjectProtocol] = []
    /// 设备列表与 AirPods 那段结果：CoreAudio 枚举一次 1.74ms（2026-10-01 实测，100 次平均），
    /// 每 2 秒问一次就是常驻约 0.11% 单核——锁屏下量到的 0.100% 基本就是它。
    /// 现在只在「设备/默认输出变了」或 30 秒兜底时才重新枚举。
    private let audioCache = AudioDeviceCache()
    private var audioListenersInstalled = false
    /// 计划 2-1：所有播放器的推送流。健康时音乐不再去问播放器；挂了就回到下面的通知 + 兜底轮询。
    private let nowPlaying = NowPlayingStream()
    /// 正在播放的封面（NP-2）：换曲时取一次，只留最新一张在内存；推送流没开时什么都不做。
    private let artwork = NowPlayingArtwork()
    /// 封面取到、换掉或丢掉时通知（紧凑左耳的封面和右耳的取色点读它）。
    var onArtwork: ((NowPlayingArtworkImage?) -> Void)?
    var nowPlayingArtwork: NowPlayingArtworkImage? { artwork.latest }

    func start() {
        guard !running else { return }
        running = true
        epoch += 1
        workToken = ActivitySourceToken()
        installAudioListeners()
        installMusicObservers()
        artwork.onChange = { [weak self] image in self?.onArtwork?(image) }
        nowPlaying.onUpdate = { [weak self] info in
            self?.artwork.trackChanged(to: info)
            self?.streamChanged()
        }
        nowPlaying.onHealthChange = { [weak self] healthy in
            if !healthy { self?.artwork.clear() }
            self?.musicChanged()
        }
        // 推送判坏了（NP-4）：退路上的 Music / Spotify 此时才可能问“自动化”授权，重新对账一次。
        nowPlaying.onGiveUp = { [weak self] in self?.musicChanged() }
        syncNowPlayingStream()
        syncCalendar()
        currentTier = .idle
        scheduleTick()
        poll()
    }
    func stop() {
        running = false
        nowPlaying.stop()
        artwork.clear()
        calendar.stop()
        workToken.cancel(); epoch += 1; timer?.invalidate(); timer = nil; tickInterval = 0
        musicApp = nil; musicRead = nil; musicDirty = true; lastSnapshotCount = 0
    }

    /// 按当前档位排下一次 tick。档位没变就什么都不做（现有 timer 继续走）。
    private func scheduleTick() {
        let interval = NotchActivityPollPolicy.interval(for: currentTier)
        guard running, timer == nil || tickInterval != interval else { return }
        timer?.invalidate()
        let next = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        // 容忍度让系统把这次唤醒并到别的唤醒上；空闲档的 30 秒本来就不急。
        next.tolerance = NotchActivityPollPolicy.tolerance(for: interval)
        RunLoop.main.add(next, forMode: .common)
        timer = next
        tickInterval = interval
    }

    /// 一轮问完之后按刚看到的情况换档；换档才重建 timer。
    private func updateTier(hasPlayer: Bool, hasRecordingSource: Bool) {
        let tier = NotchActivityPollPolicy.tier(hasPlayer: hasPlayer,
                                                hasRecordingSource: hasRecordingSource,
                                                hasVisibleCard: lastSnapshotCount > 0)
        guard tier != currentTier else { return }
        currentTier = tier
        scheduleTick()
    }

    /// Music、Spotify 换曲、播放、暂停时会发分布式通知；播放器开关看 NSWorkspace。都只是把“该重新问一次”标上。
    private func installMusicObservers() {
        guard musicObservers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            musicObservers.append(distributed.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.musicChanged() }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            musicObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                // 语音备忘录开没开决定要不要跟录音状态；空闲档的兜底 tick 是 30 秒，等不起。
                if id == "com.apple.VoiceMemos" {
                    MainActor.assumeIsolated { self?.sourcesChanged() }
                    return
                }
                guard id == "com.apple.Music" || id == "com.spotify.client" else { return }
                MainActor.assumeIsolated { self?.musicChanged() }
            })
        }
    }

    private func musicChanged() {
        musicDirty = true
        syncNowPlayingStream()
        if running { poll() }
    }

    /// 日程开关开着、活动在跑、且已授权才启动来源；其余一律停掉。设置里改开关后调用。
    func syncCalendar() {
        let lead = CalendarSettings.lead, leadChanged = calendar.lead != lead
        calendar.lead = lead
        if running && UserDefaults.standard.bool(forKey: Self.calendarKey) { calendar.start() } else { calendar.stop() }
        // 提前量变了：下一个“该出现”的时刻跟着挪，要重查一次。
        if leadChanged && calendar.isRunning { calendar.reload() }
    }

    /// 推送流只在实时活动在跑、音乐开关开着、推送开关开着时启动；其余时候停掉子进程。
    private func syncNowPlayingStream() {
        if running && NotchNowPlayingDefaults.musicEnabled(in: .standard) && NowPlayingStream.isEnabled {
            nowPlaying.start()
        } else {
            nowPlaying.stop()
            artwork.clear()
        }
    }

    /// 推送来了新现状：直接对账一次，不去问播放器。
    private func streamChanged() {
        if running { poll() }
    }

    /// 推送流的现状映射成卡片快照。detail 是来源 App，点卡片时打开它。
    private static func snapshot(_ info: NowPlayingInfo, epoch: Double) -> NotchSourceSnapshot {
        NotchSourceSnapshot(kind: .music, title: info.title, subtitle: info.artist, symbol: "music.note",
                            progress: info.progress(atEpoch: epoch), isPaused: !info.isPlaying, detail: info.bundleID)
    }

    /// 设备或来源出现／消失：标脏之后立刻对账一次，不等兜底 tick。
    private func sourcesChanged() {
        audioCache.markDirty()
        if running { poll() }
    }

    /// 没去问播放器时，用上次读到的结果推算现在的进度（播放中才往前走）。
    private func extrapolatedMusic(now: TimeInterval) -> NotchSourceSnapshot? {
        guard let read = musicRead else { return nil }
        let s = read.snapshot
        guard !s.isPaused, let position = read.position, read.duration > 0 else { return s }
        let progress = min(1, max(0, (position + now - read.at) / read.duration))
        return NotchSourceSnapshot(kind: s.kind, title: s.title, subtitle: s.subtitle, symbol: s.symbol,
                                   progress: progress, isPaused: s.isPaused, detail: s.detail)
    }
    func enableMusic() {
        UserDefaults.standard.set(true, forKey: Self.musicKey)
        guard !commandBusy else { return }
        commandBusy = true
        let ids = runningPlayers(), token = workToken
        worker.async { [weak self] in
            for id in ids where token.valid { _ = Self.authorized(id, prompt: true) }
            DispatchQueue.main.async { self?.commandBusy = false; self?.musicChanged() }
        }
    }
    /// 设置里改了“正在播放”开关：对账一次，推送流跟着起停。
    func musicSettingChanged() { musicChanged() }

    // MARK: 大卡要的现状（NP-4）

    /// 推送流此刻健康：进度条能拖（跳转走 MediaRemote）、封面有。退路上的 Music / Spotify 不让跳。
    var nowPlayingStreamHealthy: Bool { nowPlaying.isHealthy }

    /// 这首的位置和怎么往前走。推送流健康时用推送给的；否则用上次问播放器读到的。
    var nowPlayingTimeline: NowPlayingTimeline? {
        let epoch = Date().timeIntervalSince1970
        if nowPlaying.isHealthy, let info = nowPlaying.latest { return NowPlayingTimeline(info: info, receivedAtEpoch: epoch) }
        guard let read = musicRead, let position = read.position else { return nil }
        let ago = ProcessInfo.processInfo.systemUptime - read.at
        return NowPlayingTimeline(duration: read.duration > 0 ? read.duration : nil, elapsed: position, stamp: epoch - ago,
                                  rate: read.snapshot.isPaused ? 0 : 1)
    }

    /// 松手那一下才调：跳到某个位置（秒）。只有推送流健康时有效。
    func seek(toSeconds seconds: Double) {
        guard nowPlaying.isHealthy, let adapter = NowPlayingStream.locateAdapter() else { return }
        let token = workToken
        worker.async { [weak self] in
            if token.valid { NowPlayingStream.seek(toSeconds: seconds, adapter: adapter) }
            DispatchQueue.main.async { self?.musicChanged() }
        }
    }

    func musicCommand(_ command: NotchMusicCommand) {
        guard !commandBusy, let id = musicApp else { return }
        // 推送流健康时，控制也走适配器：任何正在报告的播放器都能控制，不需要自动化授权。
        if nowPlaying.isHealthy, let adapter = NowPlayingStream.locateAdapter() {
            commandBusy = true
            let token = workToken
            worker.async { [weak self] in
                if token.valid { NowPlayingStream.send(command, adapter: adapter) }
                DispatchQueue.main.async { self?.commandBusy = false; self?.musicChanged() }
            }
            return
        }
        guard runningPlayers().contains(id) else { return }
        commandBusy = true
        let token = workToken
        worker.async { [weak self] in
            if token.valid && Self.authorized(id, prompt: false) { _ = Self.script(id, mode: command.rawValue, token: token) }
            DispatchQueue.main.async { self?.commandBusy = false; self?.musicChanged() }
        }
    }
    private func runningPlayers() -> [String] {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return ["com.apple.Music", "com.spotify.client"].filter { ids.contains($0) }
    }
    private func poll() {
        guard running else { return }
        if busy { pendingPoll = true; return }
        busy = true
        polls &+= 1
        let token = epoch, work = workToken
        let now = ProcessInfo.processInfo.systemUptime
        let musicEnabled = NotchNowPlayingDefaults.musicEnabled(in: .standard)
        let allowPrompt = musicEnabled && nowPlaying.allowsAutomationPrompt
        let source = NotchActivityPollPolicy.musicSource(musicEnabled: musicEnabled, streamHealthy: nowPlaying.isHealthy)
        let enabledPlayers = source == .scripts ? runningPlayers() : []
        // 只有该问的时候才启动 osascript；不问就用推算的结果。
        // 推送流健康时完全不问。
        let askPlayers = NotchActivityPollPolicy.shouldAskScripts(source: source, hasRunningPlayers: !enabledPlayers.isEmpty,
                                                                  dirty: musicDirty, sinceLastRead: now - musicReadAt)
        let players = askPlayers ? enabledPlayers : []
        let kept: NotchSourceSnapshot?
        switch source {
        case .stream: kept = nowPlaying.latest.map { Self.snapshot($0, epoch: Date().timeIntervalSince1970) }
        case .scripts: kept = enabledPlayers.isEmpty ? nil : (askPlayers ? nil : extrapolatedMusic(now: now))
        case .none: kept = nil
        }
        if askPlayers { musicDirty = false; musicReadAt = now }
        if enabledPlayers.isEmpty { musicRead = nil }
        let hadPlayer = NotchActivityPollPolicy.hasProgressingPlayer(
            source: source, streamPlaying: nowPlaying.latest?.isPlaying == true, hasRunningPlayers: !enabledPlayers.isEmpty)
        // 语音备忘录没开着，就不用把系统里所有音频进程列一遍（每 2 秒列一次约占一个核的 1.7%）。
        let voiceMemos = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.VoiceMemos").isEmpty
        worker.async { [weak self] in
            var result: [NotchSourceSnapshot] = []
            var music: NotchSourceSnapshot? = kept
            var raw: (position: Double?, duration: Double)?
            for id in players where work.valid && Self.authorized(id, prompt: allowPrompt) {
                guard let data = Self.script(id, mode: "read", token: work),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let title = obj["title"] as? String, !title.isEmpty,
                      let state = obj["state"] as? String, ["playing", "paused"].contains(state) else { continue }
                let duration = (obj["duration"] as? Double ?? 0) / (id == "com.spotify.client" ? 1000 : 1)
                let position = obj["position"] as? Double
                let progress: Double? = duration.isFinite && duration > 0 && position?.isFinite == true
                    ? min(1, max(0, position! / duration)) : nil
                let candidate = NotchSourceSnapshot(kind: .music, title: title,
                    subtitle: obj["artist"] as? String ?? "", symbol: "music.note",
                    progress: progress, isPaused: state == "paused", detail: id)
                if music == nil || (music!.isPaused && !candidate.isPaused) { music = candidate; raw = (position, duration) }
            }
            if let music { result.append(music) }
            result.append(contentsOf: self?.audioSnapshot(voiceMemos: voiceMemos) ?? [])
            let snapshots = result
            let readMusic = players.isEmpty ? nil : music
            let readRaw = raw
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard self.epoch == token, self.running else { self.poll(); return }
                if !players.isEmpty {
                    self.musicRead = readMusic.map { ($0, readRaw?.position, readRaw?.duration ?? 0, now) }
                }
                self.musicApp = snapshots.first(where: { $0.kind == .music })?.detail
                self.lastSnapshotCount = snapshots.count
                self.onSnapshot?(snapshots)
                self.updateTier(hasPlayer: hadPlayer, hasRecordingSource: voiceMemos)
                if self.pendingPoll { self.pendingPoll = false; self.poll() }
            }
        }
    }

    nonisolated private static func authorized(_ id: String, prompt: Bool) -> Bool {
        var target = AEAddressDesc()
        let result = id.utf8CString.withUnsafeBufferPointer {
            AECreateDesc(DescType(typeApplicationBundleID), $0.baseAddress, $0.count - 1, &target)
        }
        guard result == noErr else { return false }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, prompt) == noErr
    }

    // Fixed script + arguments: song metadata never becomes executable source.
    nonisolated private static func script(_ id: String, mode: String, token: ActivitySourceToken) -> Data? {
        let script = #"""
        function run(argv) {
          var a = Application(argv[0]);
          if (!a.running()) return '{}';
          var mode = argv[1];
          if (mode === 'playPause') { a.playpause(); return '{}'; }
          if (mode === 'previous') { a.previousTrack(); return '{}'; }
          if (mode === 'next') { a.nextTrack(); return '{}'; }
          var s = String(a.playerState());
          if (s !== 'playing' && s !== 'paused') return '{}';
          var t = a.currentTrack;
          return JSON.stringify({title:String(t.name()).slice(0,256),artist:String(t.artist()).slice(0,256),
                                 state:s,duration:Number(t.duration()),position:Number(a.playerPosition())});
        }
        """#
        guard token.valid else { return nil }
        let task = Process()
        let out = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-l", "JavaScript", "-e", script, id, mode]
        task.standardOutput = out; task.standardError = FileHandle.nullDevice
        // 等它结束：用结束回调和信号量，不再每 25 毫秒醒一次来查。
        let finished = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in finished.signal() }
        do { try task.run() } catch { return nil }
        _ = finished.wait(timeout: .now() + 2.5)
        if task.isRunning || !token.valid { task.terminate(); if task.isRunning { kill(task.processIdentifier, SIGKILL) }; return nil }
        guard task.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return data.count <= 4096 ? data : nil
    }

    nonisolated private static func uint(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
    nonisolated private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    /// Only explicit recording controls confirm recording. A generic playback Pause button doesn't.
    nonisolated private static func recordingState(pid: pid_t) -> Bool? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.06)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.18
        var queue = [app], visited = 0
        func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success else { return nil }
            return value
        }
        while !queue.isEmpty, visited < 32, ProcessInfo.processInfo.systemUptime < deadline {
            let node = queue.removeFirst(); visited += 1
            if attribute(node, kAXRoleAttribute) as? String == kAXButtonRole, attribute(node, kAXEnabledAttribute) as? Bool == true {
                let label = (attribute(node, kAXDescriptionAttribute) as? String ?? attribute(node, kAXTitleAttribute) as? String ?? "").lowercased()
                if ["继续录音", "继续录制", "resume recording"].contains(label) { return true }
                if ["暂停录音", "暂停录制", "停止录音", "停止录制", "pause recording", "stop recording"].contains(label) { return false }
            }
            if let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(max(0, 32 - visited - queue.count)))
            }
        }
        return nil
    }

    /// CoreAudio 的「设备/默认输出」变化监听：变了就把缓存标脏并立刻对账一次。
    /// 只装一次，不拆——这台 App 只有一个 `NotchActivitySources` 实例，进程退出时监听自然消失，
    /// 拆的时候还要原样留着 block 才能摘掉，收益不值得那份复杂度。
    private func installAudioListeners() {
        guard !audioListenersInstalled else { return }
        audioListenersInstalled = true
        var addresses: [AudioObjectPropertyAddress] = [
            AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain),
            AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain),
        ]
        for index in addresses.indices {
            // 监听块排在主队列上：除了置脏，还要立刻对账。空闲档的兜底 tick 是 30 秒，
            // 不能让 AirPods 插上来等半分钟才出现。
            _ = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &addresses[index], .main) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.sourcesChanged() }
                }
        }
    }

    nonisolated private func audioSnapshot(voiceMemos: Bool) -> [NotchSourceSnapshot] {
        var result: [NotchSourceSnapshot] = []
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        // AirPods 那段只在缓存脏了或超过 30 秒兜底时重算（枚举设备要 1.74ms，见 audioCache 的注释）。
        if let cached = audioCache.take(maxAge: 30) {
            result.append(contentsOf: cached)
        } else {
            let output = Self.uint(systemObject, kAudioHardwarePropertyDefaultOutputDevice)
            var devicesAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var devicesSize: UInt32 = 0
            var devices: [AudioObjectID] = []
            if AudioObjectGetPropertyDataSize(systemObject, &devicesAddress, 0, nil, &devicesSize) == noErr,
               devicesSize > 0, devicesSize <= 1024, Int(devicesSize) % MemoryLayout<AudioObjectID>.size == 0 {
                devices = [AudioObjectID](repeating: 0, count: Int(devicesSize) / MemoryLayout<AudioObjectID>.size)
                let status = devices.withUnsafeMutableBytes {
                    AudioObjectGetPropertyData(systemObject, &devicesAddress, 0, nil, &devicesSize, $0.baseAddress!)
                }
                if status != noErr { devices = [] }
            }
            if let output { devices = [output] + devices.filter { $0 != output } }
            var airPods: [NotchSourceSnapshot] = []
            for device in devices {
                guard Self.uint(device, kAudioDevicePropertyDeviceIsAlive) == 1,
                      let transport = Self.uint(device, kAudioDevicePropertyTransportType),
                      [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE].contains(transport),
                      let name = Self.string(device, kAudioObjectPropertyName), name.localizedCaseInsensitiveContains("AirPods") else { continue }
                airPods.append(NotchSourceSnapshot(kind: .airPods, title: name,
                    subtitle: device == output ? WSL10n.text("source.airpods.connected.current", zh: "已连接 · 当前声音输出") : WSL10n.text("source.connected", zh: "已连接"), symbol: "airpodspro",
                    progress: nil, isPaused: false, detail: ""))
                break
            }
            audioCache.store(airPods)
            result.append(contentsOf: airPods)
        }
        if voiceMemos {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            let system = AudioObjectID(kAudioObjectSystemObject)
            if AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0, size <= 16384,
               Int(size) % MemoryLayout<AudioObjectID>.size == 0 {
                var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
                let status = objects.withUnsafeMutableBytes { bytes in
                    AudioObjectGetPropertyData(system, &address, 0, nil, &size, bytes.baseAddress!)
                }
                if status == noErr, let object = objects.first(where: { Self.string($0, kAudioProcessPropertyBundleID) == "com.apple.VoiceMemos" }) {
                    let input = Self.uint(object, kAudioProcessPropertyIsRunningInput) == 1
                    let state = Self.uint(object, kAudioProcessPropertyPID).flatMap { Self.recordingState(pid: pid_t($0)) }
                    if input || state != nil {
                        result.append(NotchSourceSnapshot(kind: .recording, title: WSL10n.text("source.voiceMemos", zh: "语音备忘录"),
                            subtitle: state == true ? WSL10n.text("source.recording.paused", zh: "录音已暂停") : (state == false ? WSL10n.text("source.recording.recording", zh: "正在录音") : WSL10n.text("source.recording.micBusy", zh: "麦克风使用中")),
                            symbol: "waveform", progress: nil, isPaused: state == true, detail: WSL10n.text("launchpad.openVoiceMemos", zh: "打开语音备忘录查看录音")))
                    }
                }
            }
        }
        return result
    }
}

// Cancellation is read by a serial worker and changed by MainActor.
// 规格 M3：取消标记进 Mutex，去掉 @unchecked Sendable。
private final class ActivitySourceToken: Sendable {
    private let cancelled = Mutex(false)
    var valid: Bool { cancelled.withLock { !$0 } }
    func cancel() { cancelled.withLock { $0 = true } }
}

/// AirPods 那段结果的缓存：CoreAudio 枚举设备一次 1.74ms，2 秒问一次就是常驻约 0.11% 单核。
/// 设备或默认输出变了（CoreAudio 监听置脏）才重算，另有 `maxAge` 兜底。
// 规格 M3：缓存状态整组进 Mutex，去掉 @unchecked Sendable。
final class AudioDeviceCache: Sendable {
    private struct State {
        var snapshots: [NotchSourceSnapshot] = []
        var at: CFAbsoluteTime = 0
        var dirty = true
        /// 每次置脏加一。store 只在「从 take 到 store 之间没有新的置脏」时才清脏：
        /// 枚举途中设备又变了，这次结果照存，但下一次仍会重算，而不是等 30 秒兜底。
        var generation = 0
        var takenGeneration = 0
    }
    private let state = Mutex(State())

    func markDirty() {
        state.withLock { $0.dirty = true; $0.generation += 1 }
    }

    func take(maxAge: CFTimeInterval) -> [NotchSourceSnapshot]? {
        state.withLock { s in
            guard !s.dirty, CFAbsoluteTimeGetCurrent() - s.at < maxAge else {
                s.takenGeneration = s.generation
                return nil
            }
            return s.snapshots
        }
    }

    func store(_ value: [NotchSourceSnapshot]) {
        state.withLock { s in
            s.snapshots = value
            s.at = CFAbsoluteTimeGetCurrent()
            if s.generation == s.takenGeneration { s.dirty = false }
        }
    }
}
