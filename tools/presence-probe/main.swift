// tools/presence-probe/main.swift
//
// 独立原生只读「在场探针」。不自证身份、不进入主 App、不改任何 App 权限。
//
// 模式：
//   （无参数）/ --capabilities  仅查询相机授权状态与候选相机是否存在，绝不开相机。
//   --observe                   仅在「已经授权」时启动选定相机 30 秒，做 ≤2Hz 人体矩形推理。
//   --help                      打印帮助。
//
// 边界：
//   - --observe 绝不调用 requestAccess；外接相机必须本次明确选择，设备元数据不是可信采集证明。
//   - 单串行 delegate 输出，alwaysDiscardsLateVideoFrames，≤2Hz 推理。
//   - 只汇总存在/未检出/未知计数；不输出或保存图像坐标、人脸模板、性别年龄体型情绪衣着。
//   - 不认证本人、不锁屏、不注入、不用麦克风/健康/定位，不修改 App 权限。
//   - 取消/失败/中断/结束都可靠关闭 capture；main 不阻塞 capture queue；SIGINT/SIGTERM 受控停止。

import Foundation
import AVFoundation
import Vision

/// 严格解析模式；只有 observe 接受一个明确的相机序号。
enum Mode {
    case capabilities
    case observe(cameraIndex: Int?)
    case help
}

enum ModeError: Error {
    case tooManyArguments
    case unknownArgument(String)
}

func parseMode(_ args: [String]) throws -> Mode {
    switch args {
    case []:
        return .capabilities
    case ["--capabilities"]:
        return .capabilities
    case ["--observe"]:
        return .observe(cameraIndex: nil)
    case ["--help"]:
        return .help
    case let pair where pair.count == 2 && pair[0] == "--observe" && pair[1].hasPrefix("--camera-index="):
        let value = String(pair[1].dropFirst("--camera-index=".count))
        guard let index = Int(value), index >= 0 else { throw ModeError.unknownArgument(pair[1]) }
        return .observe(cameraIndex: index)
    case let other where other.count > 1:
        throw ModeError.tooManyArguments
    case let other:
        throw ModeError.unknownArgument(other[0])
    }
}

/// 只读能力诊断：授权状态 + 候选相机存在性。绝不 startRunning。
func runCapabilities() -> Int32 {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    let statusText: String
    switch status {
    case .notDetermined: statusText = "notDetermined（未决定）"
    case .restricted: statusText = "restricted（受管控）"
    case .denied: statusText = "denied（已拒绝）"
    case .authorized: statusText = "authorized（已授权）"
    @unknown default: statusText = "unknown（未知枚举）"
    }

    // 只做设备发现（discovery），不打开、不 startRunning。
    let discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .external],
        mediaType: .video,
        position: .unspecified
    )
    let builtIn = discovery.devices

    print("== 相机授权状态 ==")
    print("AVCaptureDevice.authorizationStatus(for: .video): \(statusText)")
    print("== 可选相机（设备元数据不证明可信来源） ==")
    if builtIn.isEmpty {
        print("相机: 未发现")
    } else {
        print("可选相机数量: \(builtIn.count)")
        for (index, device) in builtIn.enumerated() {
            // 只报名称与类型，不含坐标、图像或生物特征。
            print("  [\(index)] \(device.localizedName) [\(device.deviceType.rawValue), transport=\(device.transportType)]")
        }
    }
    print("仅查询状态；未打开相机、未请求权限、未保存任何数据。")
    print("注意：能力为真不代表本机当前可采集，也不表示任何人正在或不在面前。")
    return 0
}

func printHelp() {
    print("""
    用法：PresenceProbe [--capabilities|--observe [--camera-index=N]|--help]
      （无参数）/ --capabilities  仅查询相机授权与候选相机存在性，绝不开相机。
      --observe                   仅在已经授权时启动选定相机 30 秒，做 ≤2Hz 只读人体矩形推理。
      --observe --camera-index=N   本次明确选择候选列表里的相机，包括显示器相机。
      --help                      打印本帮助。
    只接受一种模式；observe 可另带 --camera-index=N。退出码：0 完成；1 不可用；2 中断。
    --observe 绝不请求授权、外接相机必须明确选择，也不输出图像坐标或人脸模板。
    """)
}

// MARK: - --observe

/// 串行 delegate。所有相机回调落在同一串行队列上，避免并发状态竞争。
final class PresenceObserver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    var captureSession: AVCaptureSession { session }
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "me.aaronlau.WindowShade.presence-probe.session")

    // 由主线程写入、delegate 队列读取的标志。
    private let stopFlag = ManagedAtomicBool(false)

    // 只在 delegate 队列上访问的计数器。
    private var presentCount = 0
    private var absentCount = 0
    private var unknownCount = 0
    private var inferenceAttempts = 0
    private var frameDrops = 0
    private var lastInferenceTime = -Double.infinity

    /// 推理节流：≤2Hz，即最小间隔 0.5s。
    private let minInferenceInterval: TimeInterval = 0.5
    private let duration: TimeInterval = 30

    private var isRunning = false

    // MARK: 配置与启动

    /// 配置并启动采集。只有 already authorized 才允许走到这里。
    func start(cameraIndex: Int?) -> Bool {
        // Studio Display 可能报告 builtInWideAngleCamera；接受两种类型并明确选择外接设备。
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        let candidates = discovery.devices
        let chosen: AVCaptureDevice?
        if let index = cameraIndex {
            guard candidates.indices.contains(index) else {
                print("相机序号不可用。请重新查询设备列表。")
                return false
            }
            chosen = candidates[index] // 外接相机只允许本次显式选择。
        } else {
            let internalCandidates = candidates.filter { $0.transportType == 0x626c746e }
            chosen = internalCandidates.count == 1 ? internalCandidates.first : nil
        }

        guard let device = chosen else {
            print("未确定采样相机。请查询设备列表，再用 --observe --camera-index=N 明确选择。")
            return false
        }
        guard device.isConnected && !device.isSuspended else {
            print("相机当前不可用。未开始采集。")
            return false
        }
        print("选中相机: \(device.localizedName)（仅本次采样，不作身份授权）")

        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            guard session.canAddInput(input) else {
                print("错误：无法加入相机输入。")
                return false
            }
            session.addInput(input)

            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: queue)

            guard session.canAddOutput(output) else {
                print("错误：无法加入视频输出。")
                return false
            }
            session.addOutput(output)
        } catch {
            print("错误：创建相机输入失败：\(error.localizedDescription)")
            return false
        }

        print("启动选定相机，采样 \(Int(duration)) 秒；推理 ≤2Hz。")
        print("只汇总存在/未检出/未知，不输出图像坐标或生物特征。")
        session.startRunning()
        isRunning = session.isRunning
        return isRunning
    }

    /// 受控停止：由主线程或信号触发。加锁保证只关一次。
    private let stopLock = NSLock()
    private var didStop = false

    func stop() {
        stopLock.lock()
        if didStop {
            stopLock.unlock()
            return
        }
        didStop = true
        stopFlag.store(true)
        stopLock.unlock()

        if isRunning {
            session.stopRunning()
            isRunning = false
        }
    }

    // MARK: 推理

    /// 只做人体矩形检测，upper body only。不保存任何图像或坐标。
    private lazy var humanRectRequest: VNDetectHumanRectanglesRequest = {
        let request = VNDetectHumanRectanglesRequest()
        // 仅上半身，减少对全身姿态的依赖。
        request.upperBodyOnly = true
        return request
    }()

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if stopFlag.load() { return }

        let now = ProcessInfo.processInfo.systemUptime
        // 节流：丢弃过快到达的帧，保证 ≤2Hz 推理。
        guard now - lastInferenceTime >= minInferenceInterval else {
            frameDrops += 1
            return
        }
        lastInferenceTime = now
        inferenceAttempts += 1

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            unknownCount += 1
            return
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([humanRectRequest])
            let results = humanRectRequest.results ?? []
            if results.isEmpty {
                // 无检测结果只能记为「未检出」，不能推断无人或离位。
                absentCount += 1
            } else {
                presentCount += 1
            }
        } catch {
            unknownCount += 1
        }
    }

    func summary() {
        queue.sync { printSummary() } // stopFlag 已置位，等待最后一次推理结束。
    }

    private func printSummary() {
        print("== 观察汇总（30 秒窗口） ==")
        print("推理次数: \(inferenceAttempts)")
        print("存在（检出人体矩形）: \(presentCount)")
        print("未检出（无检测结果）: \(absentCount)")
        print("未知（无像素/推理失败）: \(unknownCount)")
        print("被节流丢弃的帧: \(frameDrops)")
        print("未检出仅表示该帧无检测结果，不代表无人/离位；未做图像质量评估，也不认证本人。")
    }
}

/// 极小的原子布尔，避免依赖额外模块。
final class ManagedAtomicBool {
    private var value: Bool
    private let lock = NSLock()
    init(_ initial: Bool) { value = initial }
    func store(_ newValue: Bool) { lock.lock(); value = newValue; lock.unlock() }
    func load() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}

/// --observe 主流程。返回进程退出码。
func runObserve(cameraIndex: Int?) -> Int32 {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    guard status == .authorized else {
        // 绝不调用 requestAccess。未授权直接拒绝进入观察。
        print("当前相机授权不是 already authorized，拒绝进入 --observe。")
        print("本探针绝不主动 requestAccess；请勿由此流程申请权限。")
        return 1
    }

    let observer = PresenceObserver()

    // 受控停止：SIGINT / SIGTERM。
    var signalStop = false
    let signalQueue = DispatchQueue.main // 与 start/stop 同队列，避免取消时又启动。
    let sources = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: signalQueue)
        source.setEventHandler {
            signalStop = true
            // 主循环随后统一 stop 与汇总。
        }
        source.resume()
        return source
    }
    defer { sources.forEach { $0.cancel() } }

    guard observer.start(cameraIndex: cameraIndex) else {
        observer.stop()
        return 1
    }

    // 主线程只做定时等待，不阻塞 capture queue。
    var interrupted = false
    let tokens = [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification].map { name in
        NotificationCenter.default.addObserver(forName: name, object: observer.captureSession, queue: .main) { _ in interrupted = true }
    }
    defer { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
    let deadline = ProcessInfo.processInfo.systemUptime + 30
    while ProcessInfo.processInfo.systemUptime < deadline && !signalStop && !interrupted {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
    }

    observer.stop()
    observer.summary()
    if interrupted { print("采集中断，不能作离位证据。"); return 2 }
    return 0
}

// MARK: - 入口

let rawArgs = Array(CommandLine.arguments.dropFirst())

let mode: Mode
do {
    mode = try parseMode(rawArgs)
} catch ModeError.tooManyArguments {
    print("参数错误：选择一种模式；observe 可另带 --camera-index=N。")
    exit(1)
} catch ModeError.unknownArgument(let arg) {
    print("参数错误：无法识别的参数 '\(arg)'。")
    exit(1)
} catch {
    print("参数错误。")
    exit(1)
}

switch mode {
case .capabilities:
    exit(runCapabilities())
case .observe(let cameraIndex):
    exit(runObserve(cameraIndex: cameraIndex))
case .help:
    printHelp()
    exit(0)
}
