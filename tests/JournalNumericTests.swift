// R01：恢复日志数值边界。编译 JournalNumeric.swift，不打开真实 journal、不启动 AppKit 救援。
import Foundation
import CoreGraphics

@main
struct JournalNumericTests {
    static var failures = 0
    static func expect(_ name: String, _ ok: @autoclosure () -> Bool) {
        if ok() { print("PASS \(name)") }
        else { failures += 1; print("FAIL \(name)") }
    }

    static func main() {
        displayIDs()
        coordinates()
        sizesAndAlpha()
        spaceIDs()
        geometryIsolation()
        formatting()
        if failures == 0 {
            print("SUMMARY JournalNumeric boundary assertions passed")
        } else {
            print("FAILED \(failures)")
            exit(1)
        }
    }

    static func displayIDs() {
        expect("display-one", JournalNumeric.displayID(NSNumber(value: 1)) == 1)
        expect("display-max", JournalNumeric.displayID(NSNumber(value: UInt32.max)) == UInt32.max)
        expect("display-zero-rejected", JournalNumeric.displayID(NSNumber(value: 0)) == nil)
        expect("display-negative-rejected", JournalNumeric.displayID(NSNumber(value: -1)) == nil)
        expect("display-fraction-rejected", JournalNumeric.displayID(NSNumber(value: 1.5)) == nil)
        expect("display-overflow-rejected", JournalNumeric.displayID(NSNumber(value: 4294967296.0)) == nil)
        expect("display-nan-rejected", JournalNumeric.displayID(NSNumber(value: Double.nan)) == nil)
        expect("display-infinity-rejected", JournalNumeric.displayID(NSNumber(value: Double.infinity)) == nil)
        expect("display-negative-infinity-rejected", JournalNumeric.displayID(NSNumber(value: -Double.infinity)) == nil)
        expect("display-bool-true-rejected", JournalNumeric.displayID(NSNumber(value: true)) == nil)
        expect("display-bool-false-rejected", JournalNumeric.displayID(NSNumber(value: false)) == nil)
        expect("display-string-rejected", JournalNumeric.displayID("1") == nil)
        expect("display-missing-rejected", JournalNumeric.displayID(nil) == nil)
        expect("window-id-matches", JournalNumeric.windowID(NSNumber(value: 42)) == 42)
    }

    static func coordinates() {
        expect("coordinate-negative-preserved", JournalNumeric.coordinate(NSNumber(value: -32000.0)) == -32000)
        expect("coordinate-fraction-preserved", JournalNumeric.coordinate(NSNumber(value: 12.25)) == 12.25)
        expect("coordinate-nan-rejected", JournalNumeric.coordinate(NSNumber(value: Double.nan)) == nil)
        expect("coordinate-bool-rejected", JournalNumeric.coordinate(NSNumber(value: true)) == nil)
    }

    static func sizesAndAlpha() {
        expect("size-positive", JournalNumeric.positiveSize(NSNumber(value: 800)) == 800)
        expect("size-zero-rejected", JournalNumeric.positiveSize(NSNumber(value: 0)) == nil)
        expect("size-negative-rejected", JournalNumeric.positiveSize(NSNumber(value: -10)) == nil)
        expect("alpha-mid", JournalNumeric.alpha(NSNumber(value: 0.5)) == 0.5)
        expect("alpha-over-rejected", JournalNumeric.alpha(NSNumber(value: 1.5)) == nil)
        expect("alpha-nan-rejected", JournalNumeric.alpha(NSNumber(value: Double.nan)) == nil)
    }

    static func spaceIDs() {
        expect("space-uint64", JournalNumeric.spaceID(UInt64(9_007_199_254_740_992)) == 9_007_199_254_740_992)
        expect("space-old-double", JournalNumeric.spaceID(NSNumber(value: 42.0)) == 42)
        expect("space-fraction-rejected", JournalNumeric.spaceID(NSNumber(value: 3.5)) == nil)
        expect("space-negative-rejected", JournalNumeric.spaceID(NSNumber(value: -1)) == nil)
        expect("space-bool-rejected", JournalNumeric.spaceID(NSNumber(value: true)) == nil)
        expect("space-nsnumber-uint", JournalNumeric.spaceID(NSNumber(value: UInt64(1001))) == 1001)
    }

    static func geometryIsolation() {
        let fallback = CGPoint(x: 100, y: 200)
        let size = CGSize(width: 640, height: 480)
        let good: [String: Any] = [
            "originalX": -32000.0,
            "originalY": -32000.0,
            "originalWidth": 640.0,
            "originalHeight": 480.0,
            "displayID": NSNumber(value: 1)
        ]
        let g = JournalNumeric.rescueGeometry(good, fallbackOrigin: fallback, fallbackSize: size)
        expect("geometry-parking-kept", g?.origin.x == -32000 && g?.displayID == 1)

        let badDisplay: [String: Any] = [
            "originalX": 10.0, "originalY": 10.0,
            "originalWidth": 100.0, "originalHeight": 100.0,
            "displayID": NSNumber(value: Double.nan)
        ]
        expect("geometry-bad-display-isolated",
               JournalNumeric.rescueGeometry(badDisplay, fallbackOrigin: fallback, fallbackSize: size) == nil)

        let mixedBadAlpha: [String: Any] = [
            "originalX": 10.0, "originalY": 10.0,
            "originalWidth": 100.0, "originalHeight": 100.0,
            "originalAlpha": NSNumber(value: Double.infinity)
        ]
        expect("geometry-bad-alpha-isolated",
               JournalNumeric.rescueGeometry(mixedBadAlpha, fallbackOrigin: fallback, fallbackSize: size) == nil)

        let noDisplay: [String: Any] = [
            "originalX": 10.0, "originalY": 20.0,
            "originalWidth": 100.0, "originalHeight": 80.0
        ]
        let g2 = JournalNumeric.rescueGeometry(noDisplay, fallbackOrigin: fallback, fallbackSize: size)
        expect("geometry-missing-display-ok", g2?.displayID == nil && g2?.origin.y == 20)
    }

    static func formatting() {
        expect("format-finite", JournalNumeric.formatPoint(CGPoint(x: 1.2, y: -3.8)) == "(1,-4)")
        let nanPoint = CGPoint(x: CGFloat.nan, y: 0)
        expect("format-nan-safe", JournalNumeric.formatPoint(nanPoint).contains("nan"))
    }
}
