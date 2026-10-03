import Foundation
/// 在临时 fixture 里测试的比较后写入状态机；不直接执行 hidutil。
struct HIDMappingTransaction: Sendable {
    enum Failure: Error { case nonUniqueDevice, stale, notOwned, malformed }
    struct Device: Equatable, Sendable { let registryID: UInt64; let vendor: Int; let product: Int }
    struct Write: Equatable, Sendable { let device: Device; let expected: Data; let replacement: Data }
    private(set) var active: (device:Device,original:Data,applied:Data)?
    mutating func prepare(device: Device, matches: [Device], current: Data, replacement: Data) throws -> Write {
        guard active == nil, matches.count == 1, matches.first == device,device.registryID != 0 else { throw Failure.nonUniqueDevice }
        guard current.count <= 65_536, replacement.count <= 65_536,
              (try? JSONSerialization.jsonObject(with:current)) != nil,
              (try? JSONSerialization.jsonObject(with:replacement)) != nil else { throw Failure.malformed }
        // prepare 不取得所有权；只有写后读回匹配，commit 才登记。
        return Write(device:device,expected:current,replacement:replacement)
    }
    mutating func commit(_ write: Write, readback: Data) throws {
        guard active == nil, readback == write.replacement else { throw Failure.stale }
        active = (write.device,write.expected,write.replacement)
    }
    func restore(device: Device, current: Data) throws -> Write {
        guard let active,active.device == device else { throw Failure.notOwned }
        guard current == active.applied else { throw Failure.stale }
        return Write(device:device,expected:active.applied,replacement:active.original)
    }
    mutating func restored(_ write: Write, readback: Data) throws {
        guard let active,write.device == active.device,write.expected == active.applied,
              write.replacement == active.original,readback == active.original else { throw Failure.stale }
        self.active = nil
    }
}
