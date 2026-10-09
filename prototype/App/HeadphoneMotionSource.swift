// WindowShade 2.1 · 耳机头动来源。只在静音操作页开着、且开发者开关打开时读 AirPods 的头部朝向。
// 事件驱动：系统有新姿态才回调，没有定时器；页面关掉、耳机断开就停，停了不留任何样本。
// 点头、摇头走 WS2HeadGesture.recognize（经 WS2HeadMotionFeed），与相机探针是同一个识别入口。
// 耳机只用一个匿名序号区分“换了一副”，不读也不记名字或标识。
import Cocoa
import CoreMotion

@MainActor
final class HeadphoneMotionSource: NSObject, CMHeadphoneMotionManagerDelegate {
    private let manager = CMHeadphoneMotionManager()
    private var feed = WS2HeadMotionFeed()
    private var generation = 0
    private var running = false
    private var onRecognition: ((WS2HeadRecognition) -> Void)?
    private var now: (@MainActor () -> WS2.Instant)?

    /// 开始读。已经在读就先停再开，保证回调只有一份。
    func start(now: @escaping @MainActor () -> WS2.Instant, onRecognition: @escaping (WS2HeadRecognition) -> Void) {
        stop()
        guard manager.isDeviceMotionAvailable,
              CMHeadphoneMotionManager.authorizationStatus() != .denied,
              CMHeadphoneMotionManager.authorizationStatus() != .restricted else { return }
        self.now = now
        self.onRecognition = onRecognition
        running = true
        generation += 1
        manager.delegate = self
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            // 在回调线程里先取出纯数字，再回到主线程；CMDeviceMotion 本身不跨线程传。
            guard let attitude = motion?.attitude else { return }
            let pitch = attitude.pitch
            let yaw = attitude.yaw
            MainActor.assumeIsolated { self?.ingest(pitch: pitch, yaw: yaw) }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopDeviceMotionUpdates()
        manager.delegate = nil
        feed.reset()
        onRecognition = nil
        now = nil
    }

    private func ingest(pitch: Double, yaw: Double) {
        guard running, let now, let display = Self.pointerDisplay() else { return }
        let source = WS2HeadSource.other("hp-\(generation)")
        let output = feed.ingest(display: display, source: source, pitchRadians: pitch, yawRadians: yaw, at: now())
        if let recognition = output.recognition { onRecognition?(recognition) }
    }

    /// 指针所在显示器的编号。找不到就不记这一帧。
    private static func pointerDisplay() -> UInt32? {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return number.uint32Value
    }

    // MARK: CMHeadphoneMotionManagerDelegate

    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        // 回调所在线程没有保证，所以派回主线程，不用 assumeIsolated。
        Task { @MainActor [weak self] in
            guard let self, self.running else { return }
            // 换了一副耳机：序号加一，基线和半截动作都作废。
            self.generation += 1
            self.feed.reset()
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            guard let self, self.running else { return }
            self.feed.reset()
        }
    }
}
