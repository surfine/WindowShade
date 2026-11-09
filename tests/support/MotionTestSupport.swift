// 只给不依赖 WS2 协议的动效测试用：TestSuite 的同一套输出格式。
// 只编进测试二进制；不得放进 prototype/。
import Foundation

struct TestSuite {
    let name: String
    private(set) var assertions = 0
    private(set) var cases = 0
    private(set) var failures = 0
    init(_ name: String) { self.name = name }
    mutating func section(_ id: String, _ description: String) {
        cases += 1; print("CASE \(id) | \(description)")
    }
    mutating func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if condition() { print("ok   \(message)") }
        else { failures += 1; print("FAIL \(message)") }
    }
    func finish() {
        print("\(failures == 0 ? "PASS" : "FAIL") \(name): \(cases) cases, \(assertions) assertions, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
