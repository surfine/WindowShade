import Foundation
import CoreAudio

/// 系统“声音输出”里能选的设备，和切换默认输出（设计稿《正在播放》“音量与输出设备”，工作包 NP-4）。
///
/// - 列表只列系统声音设置里选得到的设备（AirPods、这台 Mac、显示器、连上的音箱）：有输出声道、没被藏起来、能当默认输出。
///   系统选不到的隔空播放音箱不列，我们不自己去连。
/// - 设备名里可能有人名（“小明的 AirPods”）：只在内存里，不写运行记录，不发送。
/// - 只在点开“播放到”列表、或打开大卡要认当前设备类型的那一下读；没有常驻监听、没有定时读取。
/// - 切换 = 把系统默认输出（和系统提示音输出）换成所选设备，和在“声音”设置里点一下是同一件事。
enum AudioOutputRoutes {
    /// 能选的设备，系统给的顺序；当前默认输出打勾。读不到就是空的。
    static func list() -> [AudioOutputRoute] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let current = uint(system, kAudioHardwarePropertyDefaultOutputDevice)
        var routes: [AudioOutputRoute] = []
        for device in deviceIDs() where isSelectableOutput(device) {
            guard let uid = string(device, kAudioDevicePropertyDeviceUID), let name = string(device, kAudioObjectPropertyName) else { continue }
            let kind = AudioOutputList.kind(transport: transport(of: device), name: name)
            routes.append(AudioOutputRoute(id: device, uid: uid, name: name, kind: kind, isCurrent: device == current))
        }
        return AudioOutputList.rows(from: routes)
    }

    /// 当前默认输出是哪一类（为了换控制行右端的图标）。只读传输方式和名字来分类，名字不留下。读不到是 nil。
    static func currentKind() -> AudioOutputKind? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let current = uint(system, kAudioHardwarePropertyDefaultOutputDevice), current != 0 else { return nil }
        return AudioOutputList.kind(transport: transport(of: current), name: string(current, kAudioObjectPropertyName) ?? "")
    }

    /// 把默认输出换成这个设备。设备已经不在了（刚拔掉）返回 false。
    @discardableResult
    static func select(_ route: AudioOutputRoute) -> Bool {
        // 设备号可能在列表打开后变过：用 uid 重新对一次。
        guard let live = deviceIDs().first(where: { string($0, kAudioDevicePropertyDeviceUID) == route.uid }),
              isSelectableOutput(live) else { return false }
        let output = setDefault(kAudioHardwarePropertyDefaultOutputDevice, live)
        // 系统提示音输出跟着换，和“声音”设置里点一下一致；这一步失败不算失败。
        _ = setDefault(kAudioHardwarePropertyDefaultSystemOutputDevice, live)
        return output
    }

    // MARK: - CoreAudio

    private static func setDefault(_ selector: AudioObjectPropertySelector, _ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value = device
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                UInt32(MemoryLayout<AudioObjectID>.size), &value)
        return status == noErr
    }

    private static func deviceIDs() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0, size <= 4096,
              Int(size) % MemoryLayout<AudioObjectID>.size == 0 else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = devices.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!) }
        return status == noErr ? devices : []
    }

    /// 有输出声道、活着、没被藏起来、能当默认输出。
    private static func isSelectableOutput(_ device: AudioObjectID) -> Bool {
        guard uint(device, kAudioDevicePropertyDeviceIsAlive) != 0, uint(device, kAudioDevicePropertyIsHidden) != 1,
              outputChannels(of: device) > 0 else { return false }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
                                                 mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value == 1
    }

    private static func outputChannels(of device: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size >= UInt32(MemoryLayout<AudioBufferList>.size),
              size <= 4096 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func transport(of device: AudioObjectID) -> AudioOutputTransport {
        switch uint(device, kAudioDevicePropertyTransportType) ?? 0 {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .display
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return .virtual
        default: return .other
        }
    }

    private static func uint(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
