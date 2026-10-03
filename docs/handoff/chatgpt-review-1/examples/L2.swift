// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
import CoreBluetooth
// 所有 CB 对象留在串行队列内；此骨架不扫描、不申请权限、不伪造 iPhone 服务。
final class PresencePeripheralReader: NSObject, CBPeripheralDelegate {
    let queue = DispatchQueue(label: "windowshade.presence.reader")
    func read(_ characteristic: CBCharacteristic, on peripheral: CBPeripheral) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        guard peripheral.state == .connected,
              characteristic.properties.contains(.read) else { return false }
        peripheral.readValue(for: characteristic)
        return true
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        // 在这里关联唯一在途 request/epoch；只把值类型结果交给状态机。
    }
}
