import CoreMediaIO
import QuartzCore

/// 现在有没有任何 App 在用摄像头（视频通话）。读系统公开的“设备正在被谁运行”标志位：
/// 不打开摄像头、不取画面，所以不需要摄像头权限，也不会弹授权。只在要弹提醒时才读，读一次缓存一秒，不轮询。
@MainActor
final class CameraInUseProbe {
    static let shared = CameraInUseProbe()
    private var cached = false
    private var cachedAt: CFTimeInterval = -.infinity

    func isInUse() -> Bool {
        let now = CACurrentMediaTime()
        if now - cachedAt < CameraQuietPolicy.cacheSeconds { return cached }
        cached = Self.anyCameraRunning()
        cachedAt = now
        return cached
    }

    nonisolated static func anyCameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == 0 else { return false }
        for device in devices {
            var running: UInt32 = 0
            let runningSize = UInt32(MemoryLayout<UInt32>.size)
            var flag = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var got: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &flag, 0, nil, runningSize, &got, &running) == 0, running != 0 { return true }
        }
        return false
    }
}
