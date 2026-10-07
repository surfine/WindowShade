import Foundation
import Darwin

/// Explicit personal recording only. No image/audio, identity decision, or command execution.
struct MouthRecordingProbeOptions {
    let camera: String
    let session: UUID
    let command: String?
    let output: URL
    init(_ arguments: [String]) throws {
        guard arguments.first == "--record", arguments.count == 9 else { throw MouthRecordingProbeError.arguments }
        var values: [String: String] = [:]
        for index in stride(from: 1, to: arguments.count, by: 2) {
            let key = arguments[index]
            guard ["--camera", "--session", "--command", "--output"].contains(key),
                  values[key] == nil, !arguments[index + 1].isEmpty else { throw MouthRecordingProbeError.arguments }
            values[key] = arguments[index + 1]
        }
        guard let camera = values["--camera"], let sessionText = values["--session"],
              let session = UUID(uuidString: sessionText), let command = values["--command"],
              command == "no_command" || WS2SilentPhrases.starterCommandIDs.contains(command),
              let output = values["--output"] else { throw MouthRecordingProbeError.arguments }
        self.camera = camera; self.session = session; self.command = command == "no_command" ? nil : command
        self.output = URL(fileURLWithPath: output)
    }
}

enum MouthRecordingProbeError: Error, CustomStringConvertible {
    case arguments, interruptedSample, invalidRecording, timedOut, outputExists, outputWrite
    var description: String {
        switch self {
        case .arguments: return "必须显式指定 --record、--camera、--session UUID、--command 和 --output 新文件。"
        case .interruptedSample: return "人脸、嘴部或帧时序中断；本次作废，没有拼接或保存。"
        case .invalidRecording: return "有效连续帧不足；本次没有保存。"
        case .timedOut: return "采集超时；本次没有保存。"
        case .outputExists: return "输出已存在，不覆盖。"
        case .outputWrite: return "无法写入新的个人录制文件。"
        }
    }
}

struct MouthRecordingAccumulator {
    let camera: String
    let session: UUID
    let command: String?
    private var generation: UInt64?
    private var sequence: UInt64?
    private var firstTime: Double?
    private var lastTime: Double?
    private(set) var frames: [WS2MouthFrame] = []
    private(set) var result: Result<WS2MouthRecording, MouthRecordingProbeError>?

    mutating func receive(_ observation: FaceObservation) {
        guard result == nil else { return }
        guard observation.cameraID == camera, observation.faceCount == 1,
              observation.observedAt.isFinite,
              generation.map({ $0 == observation.generation }) ?? true,
              sequence.map({ observation.sequence > $0 }) ?? true,
              lastTime.map({ observation.observedAt > $0 && observation.observedAt - $0 <= 0.25 }) ?? true,
              let mouth = observation.mouthLandmarks,
              let frame = WS2MouthFrame.make(time: observation.observedAt - (firstTime ?? observation.observedAt), points: mouth),
              frames.first.map({ $0.values.count == frame.values.count }) ?? true else {
            result = .failure(.interruptedSample); frames.removeAll(); return
        }
        firstTime = firstTime ?? observation.observedAt; lastTime = observation.observedAt
        generation = observation.generation; sequence = observation.sequence
        frames.append(frame)
        if frame.time >= 2 {
            let recording = WS2MouthRecording(session: session, commandID: command, frames: frames)
            result = recording.valid ? .success(recording) : .failure(.invalidRecording)
        } else if frames.count >= 100 {
            result = .failure(.invalidRecording); frames.removeAll()
        }
    }
}

/// O_EXCL also protects the final write against a file appearing after argument validation.
func saveMouthRecording(_ recording: WS2MouthRecording, to url: URL) throws {
    guard recording.valid else { throw MouthRecordingProbeError.invalidRecording }
    let data = try JSONEncoder().encode(recording)
    let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
        throw errno == EEXIST ? MouthRecordingProbeError.outputExists : MouthRecordingProbeError.outputWrite
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
    catch { try? handle.close(); try? FileManager.default.removeItem(at: url); throw MouthRecordingProbeError.outputWrite }
}

#if !MOUTH_RECORDING_TESTS
@main @MainActor struct MouthRecordingProbe {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] {
            print("--record --camera DEVICE_ID --session UUID --command ID|no_command --output NEW.json")
            print("命令：" + WS2SilentPhrases.starterCommandIDs.joined(separator: ", "))
            print("仅采集约两秒个人嘴部几何；跨时段验收使用新的 session UUID。不会执行命令或验证身份。")
            return
        }
        let source = FaceObservationSource()
        defer { source.stop() }
        do {
            let options = try MouthRecordingProbeOptions(args)
            guard !FileManager.default.fileExists(atPath: options.output.path) else { throw MouthRecordingProbeError.outputExists }
            print("个人录入：请正对指定相机，准备默念；不会开启麦克风。")
            if FaceObservationSource.authorizationStatus == .notDetermined {
                guard await source.requestAuthorization() else { throw FaceObservationSourceError.authorizationDenied }
            }
            var capture = MouthRecordingAccumulator(camera: options.camera, session: options.session, command: options.command)
            var captureError: Error?
            _ = try await source.subscribe(deviceID: options.camera, purpose: .command, validFor: 8,
                onObservation: { sample in capture.receive(sample) }, onFailure: { error in captureError = error })
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while capture.result == nil && captureError == nil && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            source.stop()
            if let captureError { throw captureError }
            guard let result = capture.result else { throw MouthRecordingProbeError.timedOut }
            let recording = try result.get()
            try saveMouthRecording(recording, to: options.output)
            let duration = recording.frames.last!.time - recording.frames.first!.time
            let observedFPS = Double(recording.frames.count - 1) / duration
            print(String(format: "已保存个人录入：%d 帧，%.2f 秒，实际投递 %.1f 帧/秒。未做识别或资格判断。", recording.frames.count, duration, observedFPS))
        } catch {
            source.stop()
            print("未保存：\(error)")
            exit(2)
        }
    }
}
#endif
