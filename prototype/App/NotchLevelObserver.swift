// 输出音量、屏幕亮度变化 → 同一颗岛上的合成提示。
// 不拦系统键，读取点已登记：音量读 Core Audio 公开标量；亮度经 DisplayServices 读当前屏
//（仓库里其它硬件形状读取同一类私有桥，失败就静默）。

import AudioToolbox
import Cocoa
import CoreAudio
import Darwin

@MainActor
final class NotchLevelObserver {
    var onVolume: ((Double) -> Void)?
    var onBrightness: ((Double) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var lastVolume: Float = -1
    private var lastBrightness: Float = -1
    private var started = false
    private var brightnessTimer: Timer?
    private let getBrightness: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)?

    private lazy var onDefaultDevice: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated {
            guard let self else { return }
            self.detachVolume()
            self.refreshDevice()
            self.attachVolume()
            self.pollVolume(initial: true)
        }
    }

    private lazy var onVolumeChange: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated { self?.pollVolume(initial: false) }
    }

    init() {
        if let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
           let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            getBrightness = unsafeBitCast(
                symbol, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
        } else {
            getBrightness = nil
        }
    }

    func start() {
        guard !started else { return }
        started = true
        refreshDevice()
        var defaultAddress = Self.defaultDeviceAddress
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddress, DispatchQueue.main, onDefaultDevice)
        attachVolume()
        pollVolume(initial: true)
        pollBrightness(initial: true)
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollBrightness(initial: false) }
        }
        if let brightnessTimer { RunLoop.main.add(brightnessTimer, forMode: .common) }
    }

    func stop() {
        guard started else { return }
        detachVolume()
        var defaultAddress = Self.defaultDeviceAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddress, DispatchQueue.main, onDefaultDevice)
        brightnessTimer?.invalidate()
        brightnessTimer = nil
        started = false
    }

    private func refreshDevice() {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.defaultDeviceAddress
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr
        else { return }
        device = deviceID
    }

    private func attachVolume() {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        var address = Self.volumeAddress
        AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, onVolumeChange)
    }

    private func detachVolume() {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        var address = Self.volumeAddress
        AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, onVolumeChange)
    }

    private func pollVolume(initial: Bool) {
        guard let value = Self.readVolume(device) else { return }
        if initial || lastVolume < 0 {
            lastVolume = value
            return
        }
        guard abs(value - lastVolume) >= 0.005 else { return }
        lastVolume = value
        onVolume?(Double(value))
    }

    private func pollBrightness(initial: Bool) {
        guard let value = readBrightness() else { return }
        if initial || lastBrightness < 0 {
            lastBrightness = value
            return
        }
        guard abs(value - lastBrightness) >= 0.008 else { return }
        lastBrightness = value
        onBrightness?(Double(value))
    }

    private func readBrightness() -> Float? {
        guard let getBrightness else { return nil }
        // 指针所在那块可调亮度的屏；没有就内建屏。
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == CGMainDisplayID() }
            ?? NSScreen.main
        guard let screen,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return nil }
        var value: Float = 0
        guard getBrightness(id, &value) == 0 else { return nil }
        return min(1, max(0, value))
    }

    private static var defaultDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func readVolume(_ device: AudioObjectID) -> Float? {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        var address = volumeAddress
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return min(1, max(0, value))
    }
}
