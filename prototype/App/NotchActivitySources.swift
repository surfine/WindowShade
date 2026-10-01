import Cocoa
import Carbon
import CoreAudio
import ApplicationServices

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
    private var epoch = 0
    private var busy = false
    private var commandBusy = false
    private var workToken = ActivitySourceToken()
    private var musicApp: String?
    static let musicKey = "Notch.activities.musicEnabled"
    /// 设备列表与 AirPods 那段结果：CoreAudio 枚举一次 1.74ms（2026-10-01 实测，100 次平均），
    /// 每 2 秒问一次就是常驻约 0.11% 单核——锁屏下量到的 0.100% 基本就是它。
    /// 现在只在「设备/默认输出变了」或 30 秒兜底时才重新枚举。
    private let audioCache = AudioDeviceCache()
    private var audioListenersInstalled = false

    func start() {
        guard timer == nil else { return }
        epoch += 1
        workToken = ActivitySourceToken()
        installAudioListeners()
        timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        poll()
    }
    func stop() { workToken.cancel(); epoch += 1; timer?.invalidate(); timer = nil; musicApp = nil }
    func enableMusic() {
        UserDefaults.standard.set(true, forKey: Self.musicKey)
        guard !commandBusy else { return }
        commandBusy = true
        let ids = runningPlayers(), token = workToken
        worker.async { [weak self] in
            for id in ids where token.valid { _ = Self.authorized(id, prompt: true) }
            DispatchQueue.main.async { self?.commandBusy = false; self?.poll() }
        }
    }
    func musicCommand(_ command: NotchMusicCommand) {
        guard !commandBusy, let id = musicApp, runningPlayers().contains(id) else { return }
        commandBusy = true
        let token = workToken
        worker.async { [weak self] in
            if token.valid && Self.authorized(id, prompt: false) { _ = Self.script(id, mode: command.rawValue, token: token) }
            DispatchQueue.main.async { self?.commandBusy = false; self?.poll() }
        }
    }
    private func runningPlayers() -> [String] {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return ["com.apple.Music", "com.spotify.client"].filter { ids.contains($0) }
    }
    private func poll() {
        guard timer != nil, !busy else { return }
        busy = true
        let token = epoch, work = workToken
        let players = UserDefaults.standard.bool(forKey: Self.musicKey) ? runningPlayers() : []
        worker.async { [weak self] in
            var result: [NotchSourceSnapshot] = []
            var music: NotchSourceSnapshot?
            for id in players where work.valid && Self.authorized(id, prompt: false) {
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
                if music == nil || (music!.isPaused && !candidate.isPaused) { music = candidate }
            }
            if let music { result.append(music) }
            result.append(contentsOf: self?.audioSnapshot() ?? [])
            let snapshots = result
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard self.epoch == token, self.timer != nil else { self.poll(); return }
                self.musicApp = snapshots.first(where: { $0.kind == .music })?.detail
                self.onSnapshot?(snapshots)
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
        do { try task.run() } catch { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 2.5
        while task.isRunning && token.valid && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.025) }
        if task.isRunning { task.terminate(); if task.isRunning { kill(task.processIdentifier, SIGKILL) }; return nil }
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

    /// CoreAudio 的「设备/默认输出」变化监听：变了就把缓存标脏，下一次对账才重新枚举。
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
            _ = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &addresses[index], worker) { [audioCache] _, _ in
                    audioCache.markDirty()
                }
        }
    }

    nonisolated private func audioSnapshot() -> [NotchSourceSnapshot] {
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
                    subtitle: device == output ? "已连接 · 当前声音输出" : "已连接", symbol: "airpodspro",
                    progress: nil, isPaused: false, detail: ""))
                break
            }
            audioCache.store(airPods)
            result.append(contentsOf: airPods)
        }
        if #available(macOS 14.2, *) {
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
                        result.append(NotchSourceSnapshot(kind: .recording, title: "语音备忘录",
                            subtitle: state == true ? "录音已暂停" : (state == false ? "正在录音" : "麦克风使用中"),
                            symbol: "waveform", progress: nil, isPaused: state == true, detail: "打开语音备忘录查看录音"))
                    }
                }
            }
        }
        return result
    }
}

// Cancellation is read by a serial worker and changed by MainActor.
private final class ActivitySourceToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var valid: Bool { lock.lock(); defer { lock.unlock() }; return !cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

/// AirPods 那段结果的缓存：CoreAudio 枚举设备一次 1.74ms，2 秒问一次就是常驻约 0.11% 单核。
/// 设备或默认输出变了（CoreAudio 监听置脏）才重算，另有 `maxAge` 兜底。
private final class AudioDeviceCache: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [NotchSourceSnapshot] = []
    private var at: CFAbsoluteTime = 0
    private var dirty = true

    func markDirty() {
        lock.lock(); dirty = true; lock.unlock()
    }

    func take(maxAge: CFTimeInterval) -> [NotchSourceSnapshot]? {
        lock.lock(); defer { lock.unlock() }
        guard !dirty, CFAbsoluteTimeGetCurrent() - at < maxAge else { return nil }
        return snapshots
    }

    func store(_ value: [NotchSourceSnapshot]) {
        lock.lock()
        snapshots = value
        at = CFAbsoluteTimeGetCurrent()
        dirty = false
        lock.unlock()
    }
}
