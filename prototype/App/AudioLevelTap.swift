// 正在播放的真实波形：录正在放的那一个播放器的声音，算出每帧 5 个电平（设计稿《正在播放》“波形要系统音频录制”，工作包 NP-6）。
//
// - 设置里“跟着声音跳”默认关；打开时才问系统音频录制（隐私与安全性 › 系统音频录制）。没权限 = 一个 tap 都不建。
// - macOS 14.2 起的 CoreAudio 进程 tap：只接推送流报的那一个播放器（按 bundle id 找进程对象，容忍子进程），
//   混成单声道，挂在一个私有聚合设备上（“声音”设置里看不见），不带任何子设备（不碰麦克风，也不碰输出设备）。
// - 只在紧凑的封面耳或大卡露着、而且在放时开；暂停 3 秒、收回、锁屏、全屏、减少动态效果就拆。
// - 声音不留下：离开录音那一路的只有每帧 5 个数，每秒 30 次；不写盘、不写运行记录、不发送。
// - 没权限、tap 失败、蓝牙输出 + Spotify（照稿先跳过，待真机核实）：右耳画静止取色点，绝不画假的。
// - 不轮询：建、拆都跟着事件走；暂停的 3 秒宽限是一次性定时器（带容差），拆了就停。
// 读取点（进程列表、建 tap、授权私有接口、设置项）都已登记在 tools/privacy/registry.json 的 music-levels / settings。

import Foundation
import CoreAudio
import AppKit
import Darwin

// MARK: - 系统音频录制的授权（TCC 私有接口，经 dlsym；读不到 = unavailable，一律当没权限）

enum AudioCaptureAccess {
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
    private static let service = "kTCCServiceAudioCapture"

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_LAZY) else { return nil }
        return dlsym(handle, name)
    }

    /// 现在有没有授权。不弹窗；要跨进程问一次系统，别在每帧里调。
    static func current() -> AudioCapturePermission {
        guard #available(macOS 14.2, *), let raw = symbol("TCCAccessPreflight") else { return .unavailable }
        let preflight = unsafeBitCast(raw, to: Preflight.self)
        switch preflight(service as CFString, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .undetermined
        }
    }

    /// 请系统弹窗问一次。回调在任意线程上；没有这个接口时直接回 false。
    static func request(_ done: @escaping @Sendable (Bool) -> Void) {
        guard #available(macOS 14.2, *), let raw = symbol("TCCAccessRequest") else { done(false); return }
        let request = unsafeBitCast(raw, to: Request.self)
        request(service as CFString, nil) { granted in done(granted) }
    }

    /// 系统设置里“系统音频录制”那一页。
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
}

// MARK: - 系统事实（只读类型和进程号，不读设备名）

enum AudioLevelSystem {
    /// 默认输出是不是蓝牙（只读传输方式，不读名字）。读不到当不是。
    static func defaultOutputIsBluetooth() -> Bool {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let device = uint(system, kAudioHardwarePropertyDefaultOutputDevice), device != 0,
              let transport = uint(device, kAudioDevicePropertyTransportType) else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// 播放器（以及同一个 bundle id 的其它实例）的进程号；在主线程上取，交给 tap 认子进程。
    @MainActor
    static func appPIDs(bundleID: String) -> Set<pid_t> {
        Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier))
    }

    /// 默认输出换了（插拔 AirPods、在“播放到”里选了别的）：在主线程上叫一声。返回的闭包撤掉监听。
    @MainActor
    static func watchDefaultOutput(_ changed: @escaping @MainActor () -> Void) -> () -> Void {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { changed() }
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectAddPropertyListenerBlock(system, &address, DispatchQueue.main, block) == noErr else { return {} }
        return {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectRemovePropertyListenerBlock(system, &address, DispatchQueue.main, block)
        }
    }

    static func uint(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    /// 系统记的“负责进程”（网页内容进程、音频服务进程的负责人是浏览器本身）。私有符号经 dlsym，读不到是 nil。
    static func responsiblePID(of pid: pid_t) -> pid_t? {
        typealias Responsible = @convention(c) (pid_t) -> pid_t
        guard let handle = dlopen(nil, RTLD_LAZY), let raw = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        let value = unsafeBitCast(raw, to: Responsible.self)(pid)
        return value > 0 ? value : nil
    }
}

// MARK: - 一个 tap

/// 录音那一路。start / stop 都只排进自己的串行队列，主线程不等 CoreAudio。
protocol AudioLevelTapping: AnyObject {
    func start(bundleID: String, appPIDs: Set<pid_t>)
    func stop()
}

/// IO 队列上的样本 → 5 个电平。只在 IO 队列上碰。
private final class AudioLevelSink: @unchecked Sendable {
    private var meter: AudioLevelMeter
    private var mono: [Float]
    private let channels: Int
    private let deliver: @Sendable ([Double]) -> Void

    init(sampleRate: Double, channels: Int, deliver: @escaping @Sendable ([Double]) -> Void) {
        meter = AudioLevelMeter(sampleRate: sampleRate)
        mono = Array(repeating: 0, count: 4096)
        self.channels = max(1, channels)
        self.deliver = deliver
    }

    func consume(_ input: UnsafePointer<AudioBufferList>) {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = list.first, let data = first.mData else { return }
        let frameCount: Int
        if list.count > 1 {
            // 非交错：每个声道一个缓冲区，平均成单声道。
            frameCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            ensure(frameCount)
            for index in 0..<frameCount { mono[index] = 0 }
            var used = 0
            for buffer in list {
                guard let pointer = buffer.mData?.assumingMemoryBound(to: Float.self),
                      Int(buffer.mDataByteSize) / MemoryLayout<Float>.size >= frameCount else { continue }
                for index in 0..<frameCount { mono[index] += pointer[index] }
                used += 1
            }
            guard used > 0 else { return }
            let scale = 1 / Float(used)
            for index in 0..<frameCount { mono[index] *= scale }
        } else {
            let perFrame = max(1, Int(first.mNumberChannels))
            let samples = data.assumingMemoryBound(to: Float.self)
            frameCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size / perFrame
            if perFrame == 1 {
                if let levels = meter.push(UnsafeBufferPointer(start: samples, count: frameCount)) { deliver(levels) }
                return
            }
            ensure(frameCount)
            let scale = 1 / Float(perFrame)
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<perFrame { sum += samples[frame * perFrame + channel] }
                mono[frame] = sum * scale
            }
        }
        let levels = mono.withUnsafeBufferPointer { meter.push(UnsafeBufferPointer(rebasing: $0[0..<frameCount])) }
        if let levels { deliver(levels) }
    }

    private func ensure(_ count: Int) {
        if mono.count < count { mono = Array(repeating: 0, count: count) }
    }
}

/// CoreAudio 进程 tap + 私有聚合设备。建、拆都在 control 队列上；样本在 io 队列上（CoreAudio 同步派发）。
@available(macOS 14.2, *)
final class AudioProcessTap: AudioLevelTapping, @unchecked Sendable {
    private let control = DispatchQueue(label: "com.windowshade.audio-levels.control", qos: .utility)
    private let io = DispatchQueue(label: "com.windowshade.audio-levels.io", qos: .userInitiated)
    private let deliver: @Sendable ([Double]) -> Void
    private let failed: @Sendable () -> Void
    // 以下只在 control 队列上碰。
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var stopped = false

    init(deliver: @escaping @Sendable ([Double]) -> Void, failed: @escaping @Sendable () -> Void) {
        self.deliver = deliver
        self.failed = failed
    }

    func start(bundleID: String, appPIDs: Set<pid_t>) {
        control.async { [self] in
            guard !stopped, tapID == AudioObjectID(kAudioObjectUnknown) else { return }
            if !build(bundleID: bundleID, appPIDs: appPIDs) {
                teardown()
                failed()
            }
        }
    }

    func stop() {
        control.async { [self] in
            stopped = true
            teardown()
        }
    }

    /// 找进程对象 → 建单声道私有 tap → 建只挂这个 tap 的私有聚合设备 → 挂 IO 块 → 开始。任何一步失败返回 false。
    private func build(bundleID: String, appPIDs: Set<pid_t>) -> Bool {
        let processes = Self.processObjects(bundleID: bundleID, appPIDs: appPIDs)
        guard !processes.isEmpty else { return false }
        let description = CATapDescription(monoMixdownOfProcesses: processes)
        description.name = "WindowShade"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr, tap != AudioObjectID(kAudioObjectUnknown) else { return false }
        tapID = tap
        guard let format = Self.format(of: tap), format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32,
              format.mSampleRate.isFinite, format.mSampleRate > 0 else { return false }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "WindowShade",
            kAudioAggregateDeviceUIDKey: "com.windowshade.levels." + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[String: Any]](),
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device) == noErr,
              device != AudioObjectID(kAudioObjectUnknown) else { return false }
        aggregateID = device
        let sink = AudioLevelSink(sampleRate: format.mSampleRate, channels: Int(format.mChannelsPerFrame), deliver: deliver)
        var proc: AudioDeviceIOProcID?
        guard AudioDeviceCreateIOProcIDWithBlock(&proc, device, io, { _, input, _, _, _ in sink.consume(input) }) == noErr,
              let proc else { return false }
        procID = proc
        return AudioDeviceStart(device, proc) == noErr
    }

    private func teardown() {
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            if let procID {
                _ = AudioDeviceStop(aggregateID, procID)
                _ = AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) { _ = AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private static func format(of tap: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr else { return nil }
        return format
    }

    /// 发过声音的进程里，属于这个播放器的那些（它自己、它的子 bundle、负责进程是它的）。
    private static func processObjects(bundleID: String, appPIDs: Set<pid_t>) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0, size <= 16384,
              Int(size) % MemoryLayout<AudioObjectID>.size == 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = objects.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { return [] }
        return objects.filter { object in
            let bundle = AudioLevelSystem.string(object, kAudioProcessPropertyBundleID)
            let pid = AudioLevelSystem.uint(object, kAudioProcessPropertyPID).map { pid_t(bitPattern: $0) }
            let responsible = pid.flatMap { appPIDs.contains($0) ? $0 : AudioLevelSystem.responsiblePID(of: $0) }
            return AudioLevelGate.matches(processBundleID: bundle, responsiblePID: responsible, target: bundleID, appPIDs: appPIDs)
        }
    }
}

// MARK: - 什么时候录

/// 跟着刘海的事实建、拆 tap，并把右耳该画的样子（模式 + 5 个电平）交给刘海。只在主线程上。
@MainActor
final class AudioLevelController {
    nonisolated static let enabledKey = "Notch.nowPlaying.followSound"
    /// 设置里“跟着声音跳”，默认关。
    nonisolated static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// 刘海那边的事实。
    struct Context: Equatable, Sendable {
        var earVisible: Bool
        var bundleID: String?
        var playing: Bool
        var locked: Bool
        var fullScreen: Bool
        var reducedMotion: Bool

        static let hidden = Context(earVisible: false, bundleID: nil, playing: false, locked: false, fullScreen: false,
                                    reducedMotion: false)
    }

    typealias TapFactory = @MainActor (_ deliver: @escaping @Sendable ([Double]) -> Void,
                                       _ failed: @escaping @Sendable () -> Void) -> AudioLevelTapping?

    /// 右耳的样子变了（含每秒 30 次的电平）。
    var onWave: ((NowPlayingWave) -> Void)?
    /// 每交来一批电平时顺手再问一次刘海的现状（耳朵收了、卡关了也能拆）；不另起定时器。
    var contextProvider: (() -> Context)?
    private(set) var wave = NowPlayingWave.dots
    /// 建过几个 tap（测试和探针看它）。
    private(set) var tapsMade = 0
    var isTapping: Bool { tap != nil }

    private let defaults: UserDefaults
    private let permission: @MainActor () -> AudioCapturePermission
    private let requestAccess: @MainActor (@escaping @Sendable (Bool) -> Void) -> Void
    private let bluetoothOutput: @MainActor () -> Bool
    private let appPIDs: @MainActor (String) -> Set<pid_t>
    private let watchOutput: @MainActor (@escaping @MainActor () -> Void) -> () -> Void
    private let makeTap: TapFactory
    private let now: @MainActor () -> TimeInterval

    private var context = Context.hidden
    private var tap: AudioLevelTapping?
    private var tapBundle: String?
    private var generation = 0
    private var levels: [Double]?
    private var pausedAt: TimeInterval?
    private var graceTimer: Timer?
    private var failedBundle: String?
    private var permissionCache: AudioCapturePermission?
    private var stopWatchingOutput: (() -> Void)?
    private var deliveries = 0

    init(defaults: UserDefaults = .standard,
         permission: @escaping @MainActor () -> AudioCapturePermission = { AudioCaptureAccess.current() },
         requestAccess: @escaping @MainActor (@escaping @Sendable (Bool) -> Void) -> Void = { AudioCaptureAccess.request($0) },
         bluetoothOutput: @escaping @MainActor () -> Bool = { AudioLevelSystem.defaultOutputIsBluetooth() },
         appPIDs: @escaping @MainActor (String) -> Set<pid_t> = { AudioLevelSystem.appPIDs(bundleID: $0) },
         watchOutput: @escaping @MainActor (@escaping @MainActor () -> Void) -> () -> Void = { AudioLevelSystem.watchDefaultOutput($0) },
         makeTap: @escaping TapFactory = { AudioLevelController.systemTap(deliver: $0, failed: $1) },
         now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults
        self.permission = permission
        self.requestAccess = requestAccess
        self.bluetoothOutput = bluetoothOutput
        self.appPIDs = appPIDs
        self.watchOutput = watchOutput
        self.makeTap = makeTap
        self.now = now
    }

    nonisolated static func systemTap(deliver: @escaping @Sendable ([Double]) -> Void,
                                      failed: @escaping @Sendable () -> Void) -> AudioLevelTapping? {
        guard #available(macOS 14.2, *) else { return nil }
        return AudioProcessTap(deliver: deliver, failed: failed)
    }

    var followSound: Bool { defaults.bool(forKey: Self.enabledKey) }

    /// 设置里切了“跟着声音跳”。打开时：还没问过就请系统弹窗；返回此刻的授权（拒绝过的，调用方带去系统设置）。
    @discardableResult
    func setEnabled(_ on: Bool) -> AudioCapturePermission {
        defaults.set(on, forKey: Self.enabledKey)
        permissionCache = nil
        failedBundle = nil
        var state = AudioCapturePermission.unavailable
        if on {
            state = permission()
            permissionCache = state
            if state == .undetermined {
                requestAccess { [weak self] _ in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self?.permissionCache = nil
                            self?.reevaluate()
                        }
                    }
                }
            }
        }
        reevaluate()
        return state
    }

    /// 刘海的事实变了（活动、耳朵、锁屏、全屏、大卡）。
    func update(_ next: Context) {
        if next.playing {
            // 暂停后接着放：上次没录成的再试一次，授权也重新问一次。
            if pausedAt != nil || !context.playing { failedBundle = nil; permissionCache = nil }
            pausedAt = nil
        } else if pausedAt == nil {
            pausedAt = now()
        }
        if next.bundleID != context.bundleID { failedBundle = nil }
        context = next
        reevaluate()
    }

    func reevaluate() {
        let at = now()
        var facts = AudioLevelGate.Facts(
            followSound: followSound, permission: .unavailable, earVisible: context.earVisible, playing: context.playing,
            pausedFor: pausedAt.map { max(0, at - $0) }, locked: context.locked, fullScreen: context.fullScreen,
            reducedMotion: context.reducedMotion, bundleID: context.bundleID, bluetoothOutput: false)
        let skippable = facts.followSound && facts.earVisible && facts.bundleID.map { AudioLevelGate.bluetoothSkips.contains($0) } == true
        if skippable { facts.bluetoothOutput = bluetoothOutput() }
        // 只有别的条件都满足、或要分“静止点 / 填充色点”时才问授权（跨进程），问过就记着，直到开关或播放状态变。
        if facts.followSound, facts.earVisible, facts.playing || tap != nil {
            let state = permissionCache ?? permission()
            permissionCache = state
            facts.permission = state
        }
        let want = AudioLevelGate.wantsTap(facts, running: tap != nil)
        if want, let bundle = facts.bundleID, failedBundle != bundle {
            if tap == nil || tapBundle != bundle { startTap(bundle) }
        } else if !want, tap != nil {
            stopTap()
        }
        scheduleGrace(facts)
        // 蓝牙 + Spotify 这一条要跟着默认输出变：只在会用到时听，用不到就撤。
        if skippable, stopWatchingOutput == nil {
            stopWatchingOutput = watchOutput { [weak self] in self?.reevaluate() }
        } else if !skippable, let stop = stopWatchingOutput {
            stop()
            stopWatchingOutput = nil
        }
        publish(facts)
    }

    private func publish(_ facts: AudioLevelGate.Facts) {
        let live = tap != nil && levels != nil
        let mode = AudioLevelGate.mode(facts, tapLive: live)
        let next = NowPlayingWave(mode: mode, levels: mode == .live ? (levels ?? []) : [])
        guard next != wave else { return }
        wave = next
        onWave?(next)
    }

    private func startTap(_ bundle: String) {
        stopTap()
        generation += 1
        let token = generation
        let deliver: @Sendable ([Double]) -> Void = { [weak self] levels in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.received(levels, generation: token) } }
        }
        let failed: @Sendable () -> Void = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.tapFailed(generation: token) } }
        }
        guard let made = makeTap(deliver, failed) else {
            failedBundle = bundle
            return
        }
        tapsMade += 1
        tap = made
        tapBundle = bundle
        made.start(bundleID: bundle, appPIDs: appPIDs(bundle))
    }

    private func stopTap() {
        generation += 1
        tap?.stop()
        tap = nil
        tapBundle = nil
        levels = nil
        deliveries = 0
    }

    private func received(_ next: [Double], generation token: Int) {
        guard token == generation, tap != nil else { return }
        levels = next
        deliveries += 1
        // 大约每秒对一次刘海的现状：耳朵收了、大卡关了，不必等下一条通知。
        if deliveries % 30 == 0, let fresh = contextProvider?(), fresh != context {
            update(fresh)
            return
        }
        if wave.mode == .live {
            let updated = NowPlayingWave(mode: .live, levels: next)
            wave = updated
            onWave?(updated)
        } else {
            reevaluate()
        }
    }

    private func tapFailed(generation token: Int) {
        guard token == generation, let bundle = tapBundle else { return }
        failedBundle = bundle
        stopTap()
        reevaluate()
    }

    /// 暂停着、tap 还在：到 3 秒那一刻再看一次（一次性，容差 0.1 秒）。其余情况不留定时器。
    private func scheduleGrace(_ facts: AudioLevelGate.Facts) {
        guard tap != nil, !facts.playing, let paused = facts.pausedFor else {
            graceTimer?.invalidate(); graceTimer = nil
            return
        }
        guard graceTimer == nil else { return }
        let remaining = max(0.05, AudioLevelGate.pauseGraceSeconds - paused)
        let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.graceTimer = nil
                self?.reevaluate()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        graceTimer = timer
    }

    /// 宽限到了（测试用：不等真的定时器）。
    func graceElapsedForTesting() {
        graceTimer?.invalidate(); graceTimer = nil
        reevaluate()
    }

    /// 退出、关掉实时活动时：拆掉一切。
    func shutDown() {
        context = .hidden
        pausedAt = nil
        stopTap()
        graceTimer?.invalidate(); graceTimer = nil
        stopWatchingOutput?(); stopWatchingOutput = nil
        wave = .dots
    }
}
