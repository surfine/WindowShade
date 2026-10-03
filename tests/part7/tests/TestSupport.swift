import Foundation

@MainActor final class TestLog {
    struct Record:Codable { let name:String;let assertions:Int;let result:String }
    private(set) var assertions=0
    private(set) var records:[Record]=[]
    private var began=0, name=""
    func begin(_ name:String) { self.name=name;began=assertions }
    func check(_ value:@autoclosure()->Bool,_ reason:String) {
        assertions += 1
        guard value() else { fatalError("FAIL \(name): \(reason)") }
    }
    func end() { records.append(.init(name:name,assertions:assertions-began,result:"PASS"));print("PASS \(name) [\(assertions-began)]") }
    func save(_ url:URL) throws {
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(records).write(to:url)
        print("TOTAL \(records.count) scenarios, \(assertions) assertions")
    }
}
@MainActor func until(_ predicate:()->Bool,timeout:Double=5) async -> Bool {
    let start=ProcessInfo.processInfo.systemUptime
    while !predicate(),ProcessInfo.processInfo.systemUptime-start<timeout { try? await Task.sleep(nanoseconds:10_000_000) }
    return predicate()
}
