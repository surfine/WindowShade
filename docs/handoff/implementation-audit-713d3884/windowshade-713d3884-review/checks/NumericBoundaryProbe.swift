// Isolated numeric-boundary check for the 713d3884 review.
// This is NOT an AppKit integration or a patch to the application.
// The unsafe conversion matches Recovery/Rescue.swift's Double -> CGDirectDisplayID
// conversion (CGDirectDisplayID is UInt32); no user's recovery journal is opened.
import Foundation
import CoreFoundation

func finiteNumber(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let result = number.doubleValue
    return result.isFinite ? result : nil
}

func exactDisplayID(_ value: Any?) -> UInt32? {
    guard let number = finiteNumber(value),
          let id = UInt32(exactly: number), id != 0 else { return nil }
    return id
}

if CommandLine.arguments.count == 3,
   CommandLine.arguments[1] == "unsafe-u32",
   let value = Double(CommandLine.arguments[2]) {
    // Deliberately unsafe: run only as an isolated child process.
    print(UInt32(value))
    exit(0)
}

var count = 0
@MainActor func expect(_ name: String, _ result: @autoclosure () -> Bool) {
    count += 1
    guard result() else {
        print("FAIL \(name)")
        exit(1)
    }
    print("PASS \(name)")
}
expect("display-one", exactDisplayID(NSNumber(value: 1)) == 1)
expect("display-max", exactDisplayID(NSNumber(value: UInt32.max)) == UInt32.max)
expect("display-zero-rejected", exactDisplayID(NSNumber(value: 0)) == nil)
expect("display-negative-rejected", exactDisplayID(NSNumber(value: -1)) == nil)
expect("display-fraction-rejected", exactDisplayID(NSNumber(value: 1.5)) == nil)
expect("display-overflow-rejected", exactDisplayID(NSNumber(value: 4294967296.0)) == nil)
expect("display-nan-rejected", exactDisplayID(NSNumber(value: Double.nan)) == nil)
expect("display-infinity-rejected", exactDisplayID(NSNumber(value: Double.infinity)) == nil)
expect("display-negative-infinity-rejected", exactDisplayID(NSNumber(value: -Double.infinity)) == nil)
expect("display-bool-true-rejected", exactDisplayID(NSNumber(value: true)) == nil)
expect("display-bool-false-rejected", exactDisplayID(NSNumber(value: false)) == nil)
expect("display-string-rejected", exactDisplayID("1") == nil)
expect("display-missing-rejected", exactDisplayID(nil) == nil)
expect("coordinate-negative-preserved", finiteNumber(NSNumber(value: -32000.0)) == -32000)
expect("coordinate-fraction-preserved", finiteNumber(NSNumber(value: 12.25)) == 12.25)
expect("coordinate-nan-rejected", finiteNumber(NSNumber(value: Double.nan)) == nil)
expect("coordinate-bool-rejected", finiteNumber(NSNumber(value: true)) == nil)
print("SUMMARY \(count) isolated assertions passed")
