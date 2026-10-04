import Foundation
import IOKit
import IOKit.usb

/// 隔离探针：从 IORegistry 列出 USB/HID 指针类设备的 VID/PID，不装事件 tap、不打开 HID 会话。
/// 用法：`bash tools/probes/run-probe.sh WheelAssociationProbe`
/// 退出 0 = 列到了候选；退出 2 = 一个都没有。不把结果写成“已确认滚轮”。

@main
enum WheelAssociationProbe {
    static func main() {
        print("SPEC_CANDIDATE product 0x0323 = Magic Mouse on this Mac (docs/handoff/deepseek-input.md)")
        print("SPEC_CANDIDATE product 0x0315 = Siri Remote gen 3 (not a wheel)")
        print("STATUS none of these rows are verifiedPerEvent yet (D14)")
        var rows: [(String, String, String)] = []
        for plane in [kIOUSBPlane, kIOServicePlane] {
            var root: io_registry_entry_t = 0
            root = IORegistryGetRootEntry(kIOMainPortDefault)
            guard root != 0 else { continue }
            defer { IOObjectRelease(root) }
            var child: io_iterator_t = 0
            guard IORegistryEntryCreateIterator(root, plane, IOOptionBits(kIORegistryIterateRecursively), &child) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(child) }
            var entry = IOIteratorNext(child)
            while entry != 0 {
                defer {
                    IOObjectRelease(entry)
                    entry = IOIteratorNext(child)
                }
                let vendor = intProp(entry, "idVendor") ?? intProp(entry, kUSBVendorID)
                let product = intProp(entry, "idProduct") ?? intProp(entry, kUSBProductID)
                guard let vendor, let product else { continue }
                let name = stringProp(entry, "USB Product Name")
                    ?? stringProp(entry, "Product")
                    ?? stringProp(entry, "IOClass")
                    ?? "?"
                // 先列全部带 VID/PID 的节点；是否滚轮由主模型对照真机再定，这里不猜。
                let key = String(format: "%04x:%04x:%@", vendor, product, name)
                if !rows.contains(where: { $0.0 == key }) {
                    rows.append((key,
                                 String(format: "0x%04x", vendor),
                                 String(format: "0x%04x", product)))
                    print("DEVICE vendor=\(String(format: "0x%04x", vendor)) product=\(String(format: "0x%04x", product)) name=\(name)")
                }
            }
        }
        print("DEVICE_COUNT \(rows.count)")
        print("NEXT record Aaron's wheel VID/PID here; do not enable ScrollTap until per-event association exists")
        exit(rows.isEmpty ? 2 : 0)
    }

    private static func intProp(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        guard let raw = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        if let n = raw as? NSNumber { return n.intValue }
        return nil
    }

    private static func stringProp(_ entry: io_registry_entry_t, _ key: String) -> String? {
        guard let raw = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else {
            return nil
        }
        return raw
    }
}
