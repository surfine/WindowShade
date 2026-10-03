// Standalone macOS probe. Exact explicit VID/PID; never seizes the device or posts keys.
import Foundation
import IOKit.hid
final class HIDProbe {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault,IOOptionBits(kIOHIDOptionsTypeNone))
    var count = 0
    let started = ContinuousClock.now
    func start(vendor:Int,product:Int) -> Bool {
        IOHIDManagerSetDeviceMatching(manager,[kIOHIDVendorIDKey:vendor,kIOHIDProductIDKey:product] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager,{context,result,_,value in
            guard result == kIOReturnSuccess,let context else { return }
            let selfRef = Unmanaged<HIDProbe>.fromOpaque(context).takeUnretainedValue()
            guard selfRef.count < 2000 else { return }
            let e = IOHIDValueGetElement(value), page = IOHIDElementGetUsagePage(e)
            // Keyboard usage page is intentionally omitted even when the chosen device is composite.
            guard page != 7 else { return }
            selfRef.count += 1
            let elapsed = selfRef.started.duration(to:.now).components
            print("\(elapsed.seconds),\(IOHIDElementGetCookie(e)),\(page),\(IOHIDElementGetUsage(e)),\(IOHIDElementGetLogicalMin(e)),\(IOHIDElementGetLogicalMax(e)),\(IOHIDValueGetIntegerValue(value))")
            fflush(stdout)
        },Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager,CFRunLoopGetMain(),CFRunLoopMode.defaultMode.rawValue)
        return IOHIDManagerOpen(manager,IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
    }
    func stop() {
        IOHIDManagerUnscheduleFromRunLoop(manager,CFRunLoopGetMain(),CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager,IOOptionBits(kIOHIDOptionsTypeNone))
    }
}
@main struct Main {
    static func main() {
        let a = CommandLine.arguments
        guard a.count == 3,let vendor = Int(a[1]),let product = Int(a[2]),vendor > 0,product > 0 else {
            print("Usage: RemoteHIDProbe DECIMAL_VENDOR_ID DECIMAL_PRODUCT_ID"); exit(64)
        }
        let p = HIDProbe(); print("elapsed_s,cookie,usage_page,usage,logical_min,logical_max,value")
        guard p.start(vendor:vendor,product:product) else { print("open_failed"); exit(2) }
        RunLoop.main.run(until:Date().addingTimeInterval(30)); p.stop()
        print("finished,\(p.count),0,0,0,0,0"); exit(p.count > 0 ? 0 : 2)
    }
}
