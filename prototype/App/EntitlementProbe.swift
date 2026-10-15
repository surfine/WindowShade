// 规格 C3 的真机核对：主程序开了 hardened runtime 之后，Apple Events 与摄像头还能不能用。
// 只在显式传 --entitlement-probe 时进入，不在正常启动里出现。
// Apple Events：只查已有授权、不弹窗（AEDeterminePermissionToAutomateTarget, prompt=false）。
// 摄像头：只在已经授权时开 1 秒取帧，数收到几帧；没授权就只报状态，不请求授权。
import AVFoundation
import Cocoa

@MainActor
final class EntitlementProbe {
    private let frames = FrameCounter()
    private var session: AVCaptureSession?

    func run() {
        for id in ["com.apple.Music", "com.spotify.client"] {
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
            print("entitlement-probe: apple-events target=\(id) running=\(running) status=\(Self.automationStatus(id))")
        }
        // 只查授权记录看不出 entitlement 在不在，所以照 App 读 Music 的真实路径实际发一次：子进程跑一段只读脚本。
        print("entitlement-probe: apple-events send Music.playerState -> \(Self.askMusicPlayerState())")
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("entitlement-probe: camera authorization=\(status.rawValue)")
        guard status == .authorized, let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("entitlement-probe: camera frames=skipped")
            exit(0)
        }
        let capture = AVCaptureSession()
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(frames, queue: DispatchQueue(label: "WindowShade.entitlement-probe.camera"))
        guard capture.canAddInput(input), capture.canAddOutput(output) else {
            print("entitlement-probe: camera frames=0 (session refused input or output)")
            exit(0)
        }
        capture.addInput(input)
        capture.addOutput(output)
        session = capture
        // 探针里在主线程直接开停：会阻塞主线程半秒左右，换来不把采集会话带进别的线程。
        capture.startRunning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { exit(0) }
            let count = self.frames.count
            self.session?.stopRunning()
            print("entitlement-probe: camera frames=\(count)")
            exit(0)
        }
    }

    /// 和 NotchActivitySources 一样经脚本子进程发 Apple Event；只读播放状态，不改任何东西。
    nonisolated static func askMusicPlayerState() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", "Application('com.apple.Music').playerState()"]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return "launch-failed" }
        process.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let error = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return "exit=\(process.terminationStatus) out=\(text.trimmingCharacters(in: .whitespacesAndNewlines)) "
            + "err=\(error.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))"
    }

    /// 0 = 已允许；-1744 = 需要用户同意（还没问过）；-1743 = 不允许；-600 = 目标没在跑。
    nonisolated static func automationStatus(_ id: String) -> OSStatus {
        var target = AEAddressDesc()
        let created = id.utf8CString.withUnsafeBufferPointer {
            AECreateDesc(DescType(typeApplicationBundleID), $0.baseAddress, $0.count - 1, &target)
        }
        guard created == noErr else { return OSStatus(created) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)
    }
}

/// 只在采集队列上加一，主线程读一次；用锁保护计数。
private final class FrameCounter: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock(); value += 1; lock.unlock()
    }
}
