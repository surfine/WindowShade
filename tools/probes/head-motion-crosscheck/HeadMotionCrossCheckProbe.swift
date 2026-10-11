// 真机探针 ID-07：同时记录镜头 yaw（Vision，与 App 同一个请求）和 AirPods yaw（CMHeadphoneMotionManager），
// 按提示左转、右转，打印两路的符号和起转时差，用来定 HeadMotionCrossCheck.cameraToHeadSign、
// WS2HeadMotionMath 的耳机符号和 FaceGestureTracker 的左右判定。
// 不存图像、不写文件、不记耳机名字或标识；跑完就停相机和耳机。
import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Vision
@preconcurrency import CoreMotion
import CoreMedia

struct Stamp: Sendable { var t: Double; var yaw: Double }

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var camera: [Stamp] = []
    private var head: [Stamp] = []
    private(set) var cameraRejected = 0
    func addCamera(_ s: Stamp) { lock.lock(); camera.append(s); lock.unlock() }
    func rejectCamera() { lock.lock(); cameraRejected += 1; lock.unlock() }
    func addHead(_ s: Stamp) { lock.lock(); head.append(s); lock.unlock() }
    func slice(from: Double, to: Double) -> (camera: [Stamp], head: [Stamp]) {
        lock.lock(); defer { lock.unlock() }
        return (camera.filter { $0.t >= from && $0.t <= to }, head.filter { $0.t >= from && $0.t <= to })
    }
    var counts: (camera: Int, head: Int, rejected: Int) {
        lock.lock(); defer { lock.unlock() }
        return (camera.count, head.count, cameraRejected)
    }
}

final class CameraSide: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "probe.headmotion.camera", qos: .userInitiated)
    let recorder: Recorder
    var session: AVCaptureSession?
    init(recorder: Recorder) { self.recorder = recorder }

    func open(id: String?) -> Bool {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                       mediaType: .video, position: .unspecified).devices
        guard let device = id.flatMap({ wanted in devices.first { $0.uniqueID == wanted } }) ?? devices.first,
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        let session = AVCaptureSession()
        session.beginConfiguration()
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input); session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        session.commitConfiguration()
        self.session = session
        session.startRunning()
        print("camera: \(device.localizedName) mirrored=\(output.connection(with: .video)?.isVideoMirrored ?? false)")
        return session.isRunning
    }

    func close() { session?.stopRunning(); session = nil }

    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = sample.imageBuffer, let clock = session?.synchronizationClock else { recorder.rejectCamera(); return }
        // 与 App 的 FaceObservationSource 一样换到主机时钟；CMDeviceMotion.timestamp 也是开机以来的秒数。
        let t = CMSyncConvertTime(CMSampleBufferGetPresentationTimeStamp(sample), from: clock, to: CMClockGetHostTimeClock()).seconds
        let request = VNDetectFaceLandmarksRequest()
        do { try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request]) } catch { recorder.rejectCamera(); return }
        guard t.isFinite, let faces = request.results, faces.count == 1,
              let yaw = faces[0].yaw?.doubleValue, yaw.isFinite else { recorder.rejectCamera(); return }
        recorder.addCamera(Stamp(t: t, yaw: yaw))
    }
}

/// 相对第一个样本的最大偏转（带符号）和第一次转到一半的时刻。耳机 yaw 是弧度，在 ±π 处回绕。
func swing(_ s: [Stamp], wrap: Bool) -> (peak: Double, onset: Double)? {
    guard let base = s.first?.yaw, s.count >= 2 else { return nil }
    func d(_ y: Double) -> Double {
        var v = y - base
        if wrap { v = v.truncatingRemainder(dividingBy: 2 * .pi); if v > .pi { v -= 2 * .pi } else if v <= -.pi { v += 2 * .pi } }
        return v
    }
    var peak = 0.0
    for x in s where abs(d(x.yaw)) > abs(peak) { peak = d(x.yaw) }
    guard peak != 0, let onset = s.first(where: { d($0.yaw) * (peak > 0 ? 1 : -1) >= abs(peak) / 2 }) else { return nil }
    return (peak, onset.t)
}

func sign(_ v: Double?) -> Int { guard let v else { return 0 }; return v > 0 ? 1 : (v < 0 ? -1 : 0) }

func emit(_ fields: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
          let line = String(data: data, encoding: .utf8) else { return }
    print(line); fflush(stdout)
}

func uptime() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

func say(_ text: String, seconds: Double) -> (Double, Double) {
    print(">>> \(text)"); fflush(stdout)
    let start = uptime()
    Thread.sleep(forTimeInterval: seconds)
    return (start, uptime())
}

func summarize(_ name: String, _ values: [Int]) -> String {
    let up = values.filter { $0 > 0 }.count, down = values.filter { $0 < 0 }.count
    return "\(name): increased \(up)/\(values.count), decreased \(down)/\(values.count)"
}

func verdict(majority values: [Int]) -> Int {
    let up = values.filter { $0 > 0 }.count, down = values.filter { $0 < 0 }.count
    if up > 0 && down == 0 { return 1 }
    if down > 0 && up == 0 { return -1 }
    return 0
}

@main
struct HeadMotionCrossCheckProbe {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        var rounds = 3, cameraID: String?
        while !args.isEmpty {
            let a = args.removeFirst()
            switch a {
            case "--rounds": rounds = max(1, min(10, Int(args.first ?? "") ?? 3)); if !args.isEmpty { args.removeFirst() }
            case "--camera": cameraID = args.first; if !args.isEmpty { args.removeFirst() }
            default: print("usage: run.sh [--rounds N] [--camera UNIQUE_ID] | --check"); exit(64)
            }
        }

        let access = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var granted = false
        AVCaptureDevice.requestAccess(for: .video) { granted = $0; access.signal() }
        access.wait()
        guard granted else { print("STOP camera permission denied"); exit(2) }

        let recorder = Recorder()
        let camera = CameraSide(recorder: recorder)
        guard camera.open(id: cameraID) else { print("STOP camera unavailable"); exit(3) }
        defer { camera.close() }

        let headphones = CMHeadphoneMotionManager()
        let motionQueue = OperationQueue()
        motionQueue.maxConcurrentOperationCount = 1
        print("headphones: motion available=\(headphones.isDeviceMotionAvailable) authorization=\(CMHeadphoneMotionManager.authorizationStatus().rawValue) (0 notDetermined, 1 restricted, 2 denied, 3 authorized)")
        if headphones.isDeviceMotionAvailable {
            headphones.startDeviceMotionUpdates(to: motionQueue) { motion, _ in
                guard let motion else { return }
                recorder.addHead(Stamp(t: motion.timestamp, yaw: motion.attitude.yaw))
            }
        }
        defer { headphones.stopDeviceMotionUpdates() }

        print("Wear AirPods (Pro / 3rd gen / Max) and sit facing the camera, one face only.")
        print("'left' / 'right' always mean YOUR OWN left / right, not the screen's.")
        _ = say("look straight at the camera", seconds: 3)
        let warm = recorder.counts
        print("warm-up: camera samples=\(warm.camera) rejected=\(warm.rejected) headphone samples=\(warm.head)")
        if warm.head == 0 { print("NOTE no headphone samples yet — the camera half is still recorded; head columns will be empty") }

        var cameraLeft: [Int] = [], cameraRight: [Int] = [], headLeft: [Int] = [], headRight: [Int] = []
        var ws2Left: [Int] = [], ws2Right: [Int] = [], lags: [Double] = []
        for round in 1...rounds {
            for side in ["left", "right"] {
                _ = say("hold still, facing the camera", seconds: 1.5)
                let (start, end) = say("turn your head to YOUR \(side.uppercased()), hold, then back to centre", seconds: 3)
                let s = recorder.slice(from: start - 0.3, to: end)
                let c = swing(s.camera, wrap: false), h = swing(s.head, wrap: true)
                // WS2HeadMotionMath 换算后的耳机 yaw（约定向右为正）。
                let ws2 = h.flatMap { WS2HeadMotionMath.degrees(pitchRadians: 0, yawRadians: $0.peak)?.yaw }
                let lagMs: Double? = (c != nil && h != nil) ? (h!.onset - c!.onset) * 1000 : nil
                // 用当前常量跑一遍纯逻辑，看现在的约定下会判成什么。
                let origin = start - 0.3
                func rel(_ t: Double) -> WS2.Instant { WS2.Instant(seconds: max(0, t - origin)) ?? .zero }
                let camSamples = s.camera.map { HeadMotionYawSample(at: rel($0.t), yaw: $0.yaw) }
                let headSamples = s.head.compactMap { x in
                    WS2HeadMotionMath.degrees(pitchRadians: 0, yawRadians: x.yaw).map { HeadMotionYawSample(at: rel(x.t), yaw: $0.yaw) }
                }
                let v = HeadMotionCrossCheck.verdict(camera: camSamples, head: headSamples)
                emit(["round": round, "turn": side, "camera_n": s.camera.count, "head_n": s.head.count,
                      "camera_raw_peak_rad": c?.peak ?? NSNull(), "camera_raw_sign": sign(c?.peak),
                      "head_raw_peak_rad": h?.peak ?? NSNull(), "head_raw_sign": sign(h?.peak),
                      "head_ws2_sign": sign(ws2), "onset_lag_ms_head_minus_camera": lagMs ?? NSNull(),
                      "crosscheck_with_current_constant": String(describing: v)])
                if side == "left" { cameraLeft.append(sign(c?.peak)); headLeft.append(sign(h?.peak)); ws2Left.append(sign(ws2)) }
                else { cameraRight.append(sign(c?.peak)); headRight.append(sign(h?.peak)); ws2Right.append(sign(ws2)) }
                if let lagMs { lags.append(lagMs) }
            }
        }

        print("== summary (raw signs; 0 = not enough movement or no data)")
        print(summarize("turn LEFT  · camera Vision yaw", cameraLeft))
        print(summarize("turn RIGHT · camera Vision yaw", cameraRight))
        print(summarize("turn LEFT  · AirPods CMAttitude yaw", headLeft))
        print(summarize("turn RIGHT · AirPods CMAttitude yaw", headRight))

        let camLeft = verdict(majority: cameraLeft), camRight = verdict(majority: cameraRight)
        if camLeft != 0, camRight == -camLeft {
            // FaceGestureTracker 现在把“向左”判成 Vision yaw 减小。
            print("FaceGestureTracker.turnLeft expects camera yaw to DECREASE: \(camLeft < 0 ? "matches" : "REVERSED — swap the turnLeft/turnRight deltas")")
        } else { print("FaceGestureTracker left/right: inconclusive (camera signs not consistent)") }
        let hdLeft = verdict(majority: headLeft), hdRight = verdict(majority: headRight)
        if hdLeft != 0, hdRight == -hdLeft {
            // WS2HeadMotionMath 现在假设 CMAttitude yaw 向左为正。
            print("WS2HeadMotionMath expects AirPods yaw to INCREASE on a left turn: \(hdLeft > 0 ? "matches" : "REVERSED — drop the minus on yaw")")
        } else { print("WS2HeadMotionMath yaw sign: inconclusive (no headphone data or signs not consistent)") }
        let w2Right = verdict(majority: ws2Right)
        if camRight != 0, w2Right != 0, camLeft == -camRight, verdict(majority: ws2Left) == -w2Right {
            let suggested = camRight == w2Right ? 1 : -1
            print("HeadMotionCrossCheck.cameraToHeadSign: current \(Int(HeadMotionCrossCheck.cameraToHeadSign)), suggested \(suggested) (with today's WS2HeadMotionMath sign)")
        } else { print("HeadMotionCrossCheck.cameraToHeadSign: inconclusive") }
        if !lags.isEmpty {
            let sorted = lags.sorted()
            print(String(format: "onset lag head−camera ms: n=%d min=%.0f median=%.0f max=%.0f (maximumOnsetLag today = %d ms)",
                         sorted.count, sorted[0], sorted[sorted.count / 2], sorted[sorted.count - 1],
                         Int(HeadMotionCrossCheck.maximumOnsetLag / WS2.Duration.millisecond)))
        }
        print("Only change the constants after two runs agree; set HeadMotionCrossCheck.signMeasured = true in the same commit.")
    }
}
