// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
import IOKit.hid
final class RemoteHIDReader {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))
    // 不自动调用；Aaron 明确启用选定设备后才进入。
    func openAppleRemote(productID: Int) -> IOReturn {
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDProductIDKey: productID
        ] as CFDictionary)
        return IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
    func close() { _ = IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
    // 匹配回调、单设备选择、run loop 和 hidutil 所有权事务由正式桥补齐。
}
