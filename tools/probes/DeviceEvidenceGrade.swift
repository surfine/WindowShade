// 隔离探针：只给一份观察记录分级。不扫描蓝牙，不配对，不代填，不解锁。
// 缺的字段保持 unknown，不会写成 no 或 yes。
import Foundation

@main
struct DeviceEvidenceGrade {
    static func main() {
        let data: Data
        if CommandLine.arguments.count > 1 {
            fputs("usage: DeviceEvidenceGrade < observation.json\n", stderr)
            fputs("does not scan, pair, or unlock\n", stderr)
            exit(64)
        }
        data = FileHandle.standardInput.readDataToEndOfFile()
        guard !data.isEmpty else {
            fputs("missing observation json on stdin\n", stderr)
            exit(64)
        }
        let decoder = JSONDecoder()
        let observation: WS2DeviceObservation
        do {
            observation = try decoder.decode(WS2DeviceObservation.self, from: data)
        } catch {
            fputs("observation json rejected\n", stderr)
            exit(2)
        }
        let grade = WS2DeviceEvidence.grade(observation)
        print("saw_named_advertisement=\(label(grade.sawNamedAdvertisement))")
        print("received_response=\(label(grade.receivedResponse))")
        print("rssi=\(label(grade.rssi))")
        print("enrolled_identity=\(label(grade.enrolledIdentity))")
        print("near_by_calibration=\(label(grade.nearByCalibration))")
        print("secure_ranging=\(label(grade.secureRanging))")
        print("device_factor=\(label(grade.deviceFactor))")
        print("auto_unlock=refused")
    }

    static func label(_ fact: WS2DeviceEvidence.Fact) -> String {
        switch fact {
        case .unknown: return "unknown"
        case .no: return "no"
        case .yes: return "yes"
        }
    }
}
