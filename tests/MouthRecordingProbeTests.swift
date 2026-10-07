import Foundation
@main struct MouthRecordingProbeTests {
    static func frame(_ time: Double, sequence: UInt64, count: Int = 1, generation: UInt64 = 1,
                      camera: String = "test") -> FaceObservation {
        let points = (0..<12).map { index in
            let angle = Double(index) * .pi / 6
            return CGPoint(x: 0.5 + cos(angle) * 0.2, y: 0.3 + sin(angle) * 0.05)
        }
        return .init(cameraID: camera, generation: generation, sequence: sequence, observedAt: time,
                     faceCount: count, yaw: 0, pitch: 0, leftEyeOpenness: 0.2, rightEyeOpenness: 0.2,
                     faceBoundingBox: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5), confidence: 1,
                     mouthLandmarks: points, sourceFPS: 25)
    }
    static func main() throws {
        let session = UUID()
        let args = ["--record", "--camera", "test", "--session", session.uuidString,
                    "--command", "no_command", "--output", "/tmp/unused.json"]
        let options = try MouthRecordingProbeOptions(args)
        precondition(options.command == nil && options.session == session)
        for invalid in [Array(args.dropFirst()), args + ["extra"],
                        ["--record", "--camera", "test", "--session", "bad", "--command", "ui.windows", "--output", "/tmp/x"],
                        ["--record", "--camera", "test", "--session", session.uuidString, "--command", "system.unlock", "--output", "/tmp/x"]] {
            do { _ = try MouthRecordingProbeOptions(invalid); preconditionFailure() }
            catch MouthRecordingProbeError.arguments { }
        }
        var recording = MouthRecordingAccumulator(camera: "test", session: session, command: nil)
        for i in 0...50 { recording.receive(frame(10 + Double(i) / 25, sequence: UInt64(i + 1))) }
        let valid = try recording.result!.get()
        precondition(valid.valid && valid.frames.count == 51 && valid.frames.first?.time == 0)
        for invalid in [frame(10.04, sequence: 2, count: 0), frame(10.04, sequence: 2, count: 2),
                        frame(10.04, sequence: 2, generation: 2), frame(10.04, sequence: 2, camera: "wrong"),
                        frame(10.3, sequence: 2), frame(10, sequence: 2), frame(9, sequence: 2),
                        frame(10.04, sequence: 1)] {
            var interrupted = MouthRecordingAccumulator(camera: "test", session: session, command: "ui.windows")
            interrupted.receive(frame(10, sequence: 1)); interrupted.receive(invalid)
            for i in 0...50 { interrupted.receive(frame(11 + Double(i) / 25, sequence: UInt64(i + 3))) }
            do { _ = try interrupted.result!.get(); preconditionFailure("interruption was silently stitched") }
            catch MouthRecordingProbeError.interruptedSample { precondition(interrupted.frames.isEmpty) }
        }
        var missing = MouthRecordingAccumulator(camera: "test", session: session, command: nil)
        var missingFrame = frame(10, sequence: 1); missingFrame.mouthLandmarks = nil
        missing.receive(missingFrame)
        do { _ = try missing.result!.get(); preconditionFailure() }
        catch MouthRecordingProbeError.interruptedSample { }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("personal.json")
        try saveMouthRecording(valid, to: file)
        let original = try Data(contentsOf: file)
        let decoded = try JSONDecoder().decode(WS2MouthRecording.self, from: original)
        precondition(decoded == valid)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        do { try saveMouthRecording(valid, to: file); preconditionFailure("overwrote existing personal recording") }
        catch MouthRecordingProbeError.outputExists { }
        let after = try Data(contentsOf: file)
        precondition(after == original)
        print("MouthRecordingProbeTests passed: explicit arguments, uninterrupted real-frame contract, private exclusive output; no camera run")
    }
}
