import Foundation
import IOBluetooth

// iAP2/MFi 探针（隔离工具，不进 App）：对一台已配对的 iPhone 打开 iAP2 RFCOMM 通道，
// 走 marker 探测 → 链路同步 → 识别（0x1D）→ MFi 认证（0xAA），只汇报阶段，不接媒体、不 CarPlay。
//
// 用法：
//   iap2-probe --list
//   iap2-probe --identity-dir <dir> --address <AA:BB:CC:DD:EE:FF> [--seconds 60] [--ssid <名称>]
// 身份目录放用户自备的 identity.pk8 与 certificate.p7b；工具不检查来源，也不打印身份内容。
// 需要终端有蓝牙权限（系统设置 > 隐私与安全 > 蓝牙）。

func note(_ text: String) {
    FileHandle.standardError.write(("iap2: " + text + "\n").data(using: .utf8)!)
}

enum Phase: String {
    case linkDetect = "链路探测"
    case identify = "识别"
    case mfi = "MFi认证"
    case done = "完成"
}

// 可变状态只在主队列读写；IOBluetooth 回调一律跳主队列再碰状态。
final class Probe: NSObject, IOBluetoothRFCOMMChannelDelegate, @unchecked Sendable {
    let identity: Iap2MfiIdentity
    let ssid: String
    let deadline: Date
    var phase: Phase = .linkDetect
    var link = Iap2Link()
    var finished = false
    var exitCode = 0
    var csmBuffer: [UInt8] = []
    var channel: IOBluetoothRFCOMMChannel?

    init(identity: Iap2MfiIdentity, ssid: String, seconds: Double) {
        self.identity = identity
        self.ssid = ssid
        self.deadline = Date().addingTimeInterval(seconds)
        super.init()
    }

    func start(device: IOBluetoothDevice, channelID: BluetoothRFCOMMChannelID) -> Bool {
        var pointer: IOBluetoothRFCOMMChannel?
        let status = device.openRFCOMMChannelAsync(&pointer, withChannelID: channelID, delegate: self)
        guard status == kIOReturnSuccess, let pointer else {
            note("RFCOMM 打开失败（0x\(String(status, radix: 16))）")
            return false
        }
        channel = pointer
        return true
    }

    // MARK: RFCOMM 回调（IOBluetooth 线程）

    func rfcommChannelOpenComplete(_ sender: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard error == kIOReturnSuccess else {
            note("RFCOMM 打开完成但失败（0x\(String(error, radix: 16))）")
            exitCode = 3
            finished = true
            return
        }
        note("RFCOMM 通道已打开")
        DispatchQueue.main.async { self.beginProtocol() }
    }

    func rfcommChannelData(_ sender: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let pointer = dataPointer.assumingMemoryBound(to: UInt8.self)
        let bytes = [UInt8](UnsafeBufferPointer(start: pointer, count: dataLength))
        DispatchQueue.main.async { self.handleBytes(bytes) }
    }

    func rfcommChannelClosed(_ sender: IOBluetoothRFCOMMChannel!) {
        DispatchQueue.main.async {
            note("RFCOMM 通道关闭")
            if self.phase != .done { self.exitCode = 4 }
            self.finished = true
        }
    }

    // MARK: 协议（主线程）

    func beginProtocol() {
        link.start()
        drain()
        note("开始：marker 已发，等 iPhone")
    }

    func handleBytes(_ bytes: [UInt8]) {
        guard !finished else { return }
        link.feed(bytes)
        pumpEvents()
        drain()
    }

    func drain() {
        let out = link.takeOutput()
        if !out.isEmpty, let channel {
            var buffer = out
            channel.writeSync(&buffer, length: UInt16(buffer.count))
        }
    }

    func pumpEvents() {
        while let event = link.pollEvent() {
            switch event {
            case .ready:
                phase = .identify
                note("链路同步完成（对方出窗 \(link.peerSynchronization?.maxOutgoing ?? 0)）")
            case .control(let payload):
                handleControl(payload)
            case .dead(let reason):
                note("链路死了：\(reason)（阶段 \(phase.rawValue)）")
                if phase != .done { exitCode = 5 }
                finished = true
            }
        }
    }

    func handleControl(_ payload: [UInt8]) {
        csmBuffer += payload
        let (frames, consumed) = Iap2Csm.parse(from: csmBuffer)
        csmBuffer.removeFirst(consumed)
        for frame in frames {
            switch frame.messageId {
            case Iap2Csm.Identify.start:
                note("iPhone 发 0x1D00 开始识别")
                let mac = (IOBluetoothHostController.default()?.addressAsString() ?? "00:00:00:00:00:00")
                    .uppercased().replacingOccurrences(of: "-", with: ":")
                let reply = Iap2Csm.identificationInformation(
                    name: "WindowShade Probe", model: "WS2", manufacturer: "WindowShade",
                    serialNumber: "WS2-PROBE-1", firmwareVersion: "0.1", hardwareVersion: "0.1",
                    externalAccessoryProtocol: "me.aaron.windowshade.probe",
                    bluetoothMac: mac, ssid: ssid)
                link.sendControl(reply.encoded)
            case Iap2Csm.Identify.accepted:
                phase = .mfi
                note("识别通过（0x1D02）")
            case Iap2Csm.Identify.rejected:
                let rejected = frame.parameters.map { String(format: "0x%04x", $0.id) }.joined(separator: " ")
                note("识别被拒（0x1D03），被拒参数：\(rejected)")
                exitCode = 6
                finished = true
            case Iap2Csm.Mfi.requestCertificate:
                note("iPhone 要证书（0xAA00）")
                link.sendControl(Iap2Csm.accessoryCertificate(identity.certificate).encoded)
            case Iap2Csm.Mfi.requestChallenge:
                guard let challenge = Iap2Csm.challenge(of: frame),
                      (1...Iap2Csm.Mfi.maximumChallengeBytes).contains(challenge.count) else {
                    note("挑战载荷长度不合法")
                    exitCode = 7
                    finished = true
                    return
                }
                note("iPhone 发挑战（0xAA02，\(challenge.count) 字节）")
                do {
                    let signature = try identity.sign(digest: challenge)
                    link.sendControl(Iap2Csm.authenticationResponse(signature).encoded)
                } catch {
                    note("签名失败：\(error)")
                    exitCode = 7
                    finished = true
                }
            case Iap2Csm.Mfi.succeeded:
                phase = .done
                note("MFi 认证通过（0xAA05）—— iPhone 认了这个身份")
                finished = true
            case Iap2Csm.Mfi.failed:
                note("MFi 认证失败（0xAA04）—— iPhone 拒了这个身份")
                exitCode = 8
                finished = true
            default:
                note(String(format: "别的消息 0x%04x（阶段 %@）", frame.messageId, phase.rawValue))
            }
            drain()
        }
    }
}

// MARK: 入口

let arguments = CommandLine.arguments
func flagValue(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

if arguments.contains("--list") {
    guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
        note("配对设备列表拿不到（检查终端的蓝牙权限）")
        exit(2)
    }
    for device in devices {
        let address = (device.addressString ?? "").uppercased().replacingOccurrences(of: "-", with: ":")
        print("\(address) \(device.name ?? "")")
    }
    exit(0)
}

guard let identityDir = flagValue("--identity-dir") else {
    note("需要 --identity-dir（用户自备 identity.pk8 + certificate.p7b）")
    exit(64)
}
guard let address = flagValue("--address") else {
    note("需要 --address（已配对 iPhone 的蓝牙地址，--list 可列）")
    exit(64)
}
let seconds = Double(flagValue("--seconds") ?? "60") ?? 60
let ssid = flagValue("--ssid") ?? "WindowShade"

let identity: Iap2MfiIdentity
do {
    identity = try Iap2MfiIdentity(directory: identityDir)
    note("身份自检通过：私钥能签、证书公钥能验（证书 \(identity.certificate.count) 字节）")
} catch {
    note("身份加载失败：\(error)")
    exit(2)
}

let normalized = address.replacingOccurrences(of: ":", with: "-").lowercased()
guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
      let device = devices.first(where: { ($0.addressString ?? "").lowercased() == normalized }) else {
    note("没找到已配对的设备 \(address)（--list 查看；iPhone 要先配对）")
    exit(2)
}

let iap2UUID = IOBluetoothSDPUUID(data: Data([
    0x00, 0x00, 0x00, 0x00, 0xde, 0xca, 0xfa, 0xde,
    0xde, 0xca, 0xde, 0xaf, 0xde, 0xca, 0xca, 0xfe]))
guard let record = device.getServiceRecord(for: iap2UUID) else {
    note("这台设备没有 iAP2 服务（不是 iPhone，或没解锁亮屏）")
    exit(3)
}
var channelID: BluetoothRFCOMMChannelID = 0
guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
    note("读不到 RFCOMM 通道号")
    exit(3)
}
note("iAP2 SDP 记录在，RFCOMM 通道 \(channelID)")

let probe = Probe(identity: identity, ssid: ssid, seconds: seconds)
guard probe.start(device: device, channelID: channelID) else { exit(3) }

while !probe.finished, Date() < probe.deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
}

if probe.phase == .done {
    print("RESULT authenticated")
} else {
    print("RESULT incomplete phase=\(probe.phase.rawValue) exit=\(probe.exitCode)")
}
exit(probe.phase == .done ? 0 : Int32(probe.exitCode == 0 ? 9 : probe.exitCode))
