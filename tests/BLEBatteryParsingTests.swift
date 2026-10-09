// 探针的电量字节解析：0...100 有效，其余未知。
import Foundation

@main
struct BLEBatteryParsingTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ c: Bool, _ m: String) { if c { print("ok   \(m)") } else { failures += 1; print("FAIL \(m)") } }

    static func main() {
        expect(BLEBatteryParsing.percent(Data([0])) == 0, "0 is valid")
        expect(BLEBatteryParsing.percent(Data([87])) == 87, "87 is valid")
        expect(BLEBatteryParsing.percent(Data([100])) == 100, "100 is valid")
        expect(BLEBatteryParsing.percent(Data([101])) == nil, "101 is unknown")
        expect(BLEBatteryParsing.percent(Data([255])) == nil, "255 is unknown")
        expect(BLEBatteryParsing.percent(Data()) == nil, "empty is unknown")
        expect(BLEBatteryParsing.percent(nil) == nil, "nil is unknown")
        expect(BLEBatteryParsing.percent(Data([50, 1])) == nil, "multi-byte is unknown")

        expect(BLEBatteryParsing.modelNumber(Data("iPhone15,2".utf8)) == "iPhone15,2", "model string")
        expect(BLEBatteryParsing.modelNumber(Data("iPhone15,2\u{0}\u{0}".utf8)) == "iPhone15,2", "trailing NUL trimmed")
        expect(BLEBatteryParsing.modelNumber(Data(" iPhone \n".utf8)) == "iPhone", "whitespace trimmed")
        expect(BLEBatteryParsing.modelNumber(Data()) == nil, "empty model is unknown")
        expect(BLEBatteryParsing.modelNumber(Data("\u{0}\u{0}".utf8)) == nil, "NUL-only model is unknown")
        expect(BLEBatteryParsing.modelNumber(Data([0xFF, 0xFE])) == nil, "non-UTF-8 model is unknown")
        expect(BLEBatteryParsing.modelNumber(Data("a\u{01}b".utf8)) == nil, "control chars are unknown")
        expect(BLEBatteryParsing.modelNumber(Data(String(repeating: "x", count: 100).utf8))?.count == 32, "model capped at 32")

        let t = BLEBatteryParsing.truncatedIdentifier("12345678-ABCD-0000-0000-000000000000")
        expect(!t.contains("ABCD") && t.hasPrefix("12345678"), "identifier is truncated")
        expect(BLEBatteryParsing.truncatedIdentifier("abc") == "abc", "short id unchanged")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
