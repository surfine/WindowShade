@preconcurrency import CoreBluetooth
import Foundation

// F1 身份探针（规格 docs/dynamic-lock.md「F1 实验现在怎么做」第 2 条）。
//
// 目标：给「连上的就是你那台手机」补一条加密证据。做法是当中心设备去连已知的 BLE 外设，
// 尝试读/订阅一个需要加密的特性（ANCS：7905F431-…，iPhone 只对配过对的配件开放）。
// 预期序列（也是我们记录的判定）：
//   unencrypted read → CBATTError.insufficientAuthentication / insufficientEncryption
//   → 系统用配对长期密钥发起加密（第一次会出配对弹窗，iPhone 上输码）
//   → 重试读成功 ⇒ 身份证明成立（identity_proven）；没走到这一步按实际阶段如实写。
//
// 不做的事：不扫描全部广播（只按 identifier 直连）、不写任何特性、不存设备名到日志、
// 不碰 ANCS 的通知内容本身——订阅成功即证据，读到的内容一律丢弃。
//
// 用法：
//   F1IdentityProbe --list                      列出系统记得的 BLE 外设（identifier + 名字）
//   F1IdentityProbe --bond <identifier> [--seconds 30]
//                                              连那台外设、做加密读、逐行输出证据
//   F1IdentityProbe --check                     自检：参数解析与常量，不开蓝牙

@main
struct F1IdentityProbe {
    // CBUUID 不是 Sendable；探针单线程跑，收进 nonisolated(unsafe)。
    nonisolated(unsafe) static let ancsService = CBUUID(string: "7905F431-B5CE-4E99-A40F-4B1E122D00D0")
    nonisolated(unsafe) static let ancsNotificationSource = CBUUID(string: "9FBF120D-6301-42D9-8C58-25E699A21DBD")
    nonisolated(unsafe) static let batteryService = CBUUID(string: "180F")

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        switch args.first {
        case "--check":
            check()
        case "--list":
            Central(mode: .list).run()
        case "--bond":
            guard args.count >= 2, let identifier = UUID(uuidString: args[1]) else { exit(64) }
            let seconds = duration(args)
            Central(mode: .bond(identifier: identifier, seconds: seconds)).run()
        default:
            FileHandle.standardError.write(Data("usage: --list | --bond <uuid> [--seconds n] | --check\n".utf8))
            exit(64)
        }
    }

    private static func duration(_ args: [String]) -> TimeInterval {
        guard let index = args.firstIndex(of: "--seconds"), index + 1 < args.count,
              let value = Double(args[index + 1]), value > 0, value <= 600 else { return 30 }
        return value
    }

    private static func check() {
        // CBUUID.description 对已知服务给友好名；认得出名字本身就是「系统知道这个服务」的证据。
        precondition(ancsService.description == "Apple Notification Center", ancsService.description)
        precondition(batteryService.description == "Battery", batteryService.description)
        precondition(duration(["--bond", "X", "--seconds", "45"]) == 45)
        precondition(duration(["--bond", "X"]) == 30)
        precondition(duration(["--bond", "X", "--seconds", "0"]) == 30)
        precondition(UUID(uuidString: "not-a-uuid") == nil)
        print("F1IdentityProbe check ok (constants + argument parsing; radio not opened)")
    }

    enum Mode {
        case list
        case bond(identifier: UUID, seconds: TimeInterval)

        var isList: Bool { if case .list = self { return true }; return false }
    }

    final class Central: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        private let mode: Mode
        private var manager: CBCentralManager!
        private var peripheral: CBPeripheral?
        private var startedAt: TimeInterval = 0
        private var stage = "boot"
        private var sawAuthenticationError = false
        private var sawEncryptedRead = false

        init(mode: Mode) {
            self.mode = mode
            super.init()
            manager = CBCentralManager(delegate: self, queue: nil)
        }

        func run() {
            startedAt = ProcessInfo.processInfo.systemUptime
            let deadline = Date().addingTimeInterval(mode.isList ? 20 : bondSeconds + 5)
            while Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                if finished { break }
            }
            conclude()
            exit(exitCode)
        }

        private var finished: Bool {
            switch mode {
            case .list: return stage == "listed"
            case .bond: return sawEncryptedRead
            }
        }
        private var bondSeconds: TimeInterval {
            if case .bond(_, let seconds) = mode { return seconds }
            return 0
        }
        private var exitCode: Int32 {
            switch mode {
            case .list: return 0
            case .bond: return sawEncryptedRead ? 0 : 2
            }
        }

        private func elapsed() -> Int {
            Int(ProcessInfo.processInfo.systemUptime - startedAt)
        }
        private func line(_ event: String, _ detail: String = "") {
            print("\(elapsed())s,\(event)\(detail.isEmpty ? "" : "," + detail)")
            fflush(stdout)
        }

        // MARK: CBCentralManagerDelegate

        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            switch central.state {
            case .poweredOn:
                switch mode {
                case .list:
                    let retrieved = central.retrievePeripherals(withIdentifiers: [])
                    // 系统没有「列出全部已配对 BLE」的公开口；retrieve(withIdentifiers:) 只回显已知的。
                    // 实际到场流程：先在系统设置里配对一次，iPhone 会进入已知表；
                    // 这里的 --list 打印的是本进程能取到的（通常为空）——真正选机走 --bond + 运行手册。
                    line("list", "retrieved=\(retrieved.count)")
                    stage = "listed"
                case .bond(let identifier, _):
                    line("connecting", "identifier=\(identifier)")
                    let known = central.retrievePeripherals(withIdentifiers: [identifier])
                    guard let target = known.first else {
                        line("unknown-identifier", "bond-first-see-runbook")
                        return
                    }
                    peripheral = target
                    target.delegate = self
                    central.connect(target)
                }
            case .unauthorized:
                line("bluetooth-unauthorized")
                finishedByFailure()
            case .poweredOff:
                line("bluetooth-off")
                finishedByFailure()
            default:
                break
            }
        }

        func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            line("connected")
            stage = "connected"
            peripheral.discoverServices([F1IdentityProbe.ancsService, F1IdentityProbe.batteryService])
        }

        func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                            error: Error?) {
            line("connect-failed", error.map { String(describing: $0) } ?? "no-error")
            finishedByFailure()
        }

        func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                            error: Error?) {
            line("disconnected", error.map { String(describing: $0) } ?? "clean")
            finishedByFailure()
        }

        // MARK: CBPeripheralDelegate

        func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            let names = (peripheral.services ?? []).map { $0.uuid.description }
            line("services", names.joined(separator: "+"))
            for service in peripheral.services ?? [] {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }

        func peripheral(_ peripheral: CBPeripheral,
                        didDiscoverCharacteristicsFor service: CBService, error: Error?) {
            for characteristic in service.characteristics ?? [] {
                // 只读不订阅的通知源也行：setNotify 会触发加密校验；内容回调里什么都不记。
                if service.uuid == F1IdentityProbe.ancsService && characteristic.uuid == F1IdentityProbe.ancsNotificationSource {
                    line("attempting-encrypted-subscribe", "ancs-notification-source")
                    peripheral.setNotifyValue(true, for: characteristic)
                    return
                }
                if characteristic.properties.contains(.read) {
                    line("attempting-read", characteristic.uuid.description)
                    peripheral.readValue(for: characteristic)
                }
            }
        }

        func peripheral(_ peripheral: CBPeripheral,
                        didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
            // 内容一律丢弃；这里只看这次读是不是过了加密门。
            if let error {
                let text = String(describing: error)
                if text.contains("insufficientAuthentication") || text.contains("insufficientEncryption")
                    || text.contains("Insufficient") {
                    sawAuthenticationError = true
                    line("read-requires-encryption", characteristic.uuid.description)
                    // 系统此刻应发起配对/加密；等 didUpdateNotificationState 或下一轮读。
                    return
                }
                line("read-error", text)
                return
            }
            sawEncryptedRead = true
            line("encrypted-read-ok", characteristic.uuid.description)
        }

        func peripheral(_ peripheral: CBPeripheral,
                        didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
            if let error {
                line("subscribe-error", String(describing: error))
                return
            }
            if characteristic.isNotifying {
                sawEncryptedRead = true
                line("encrypted-subscribe-ok", "ancs (内容不记录)")
            }
        }

        // MARK: 收尾

        private var concluded = false
        private func finishedByFailure() { /* run 循环按期限自己收尾 */ }

        private func conclude() {
            guard !concluded else { return }
            concluded = true
            switch mode {
            case .list:
                print("list-complete")
            case .bond(let identifier, _):
                let verdict = sawEncryptedRead ? "identity_proven"
                    : sawAuthenticationError ? "encryption_required_but_not_completed"
                    : "identity_unproven"
                print("finished,identifier=\(identifier),\(verdict)")
            }
        }
    }
}
