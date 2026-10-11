import Foundation

@main struct ProfileValueTests {
    @MainActor static func main() throws {
        func json(_ value: WS2OPACK.Value) -> Any {
            switch value {
            case .dictionary(let d): return d.mapValues(json)
            case .array(let a): return a.map(json)
            case .string(let s): return s
            case .uint(let n): return n
            case .real(let n): return n
            case .bool(let b): return b
            default: return NSNull()
            }
        }
        var records: [[String: Any]] = []
        for policy in [RemoteProbeConfiguration.ReplyPolicy.current, .upstreamReference] {
            for request in [false, true] {
                for xid: UInt64? in [nil, 9] {
                    for method in RemoteSessionProfile.allowed.sorted() + ["UnknownMethod"] {
                        let handler = RemoteProfileHandler(name: "test", identifier: "test", replyPolicy: policy)
                        let content: [String: WS2OPACK.Value]
                        switch method {
                        case "_interest": content = ["_regEvents": .array([.string("MediaControlStatus"), .string("SystemStatus")])]
                        case "MediaControlCommand", "_mcc": content = ["_mcc": .uint(5)]
                        case "_hidC": content = ["_hidC": .uint(6), "_hBtS": .uint(1)]
                        case "_hidT": content = ["_tPh": .uint(1), "_cx": .real(0.3), "_cy": .real(0.4)]
                        default: content = [:]
                        }
                        let output = try handler.handle(.init(identifier: method, content: content, transaction: xid, isRequest: request))
                        records.append(["policy": policy.rawValue, "request": request, "xid": xid as Any? ?? NSNull(), "method": method, "output": output.map(json)])
                    }
                }
            }
        }
        let subscription = RemoteProfileHandler(name: "test", identifier: "test", replyPolicy: .upstreamReference)
        func interest(_ content: [String: WS2OPACK.Value]) throws -> [WS2OPACK.Value] {
            try subscription.handle(.init(identifier: "_interest", content: content, transaction: 7, isRequest: true))
        }
        let registration: [String: WS2OPACK.Value] = ["_regEvents": .array([.string("SystemStatus"), .string("unknown")])]
        let expectedStatus: [WS2OPACK.Value] = [.dictionary(["_i": .string("SystemStatus"), "_t": .uint(1), "_x": .uint(7), "_c": .dictionary(["state": .uint(3)])])]
        let initial = try interest(registration)
        precondition(initial == expectedStatus)
        let duplicate = try interest(registration)
        precondition(duplicate.isEmpty)
        let removed = try interest(["_deregEvents": .array([.string("SystemStatus")])])
        precondition(removed.isEmpty)
        let again = try interest(registration)
        precondition(again == expectedStatus)
        for first in ["TVRCSessionStart", "_touchStart"] {
            let independent = RemoteProfileHandler(name: "test", identifier: "test")
            _ = try independent.handle(.init(identifier: first, content: [:], transaction: nil, isRequest: false))
            precondition(independent.profile.active && !independent.profile.systemInfo)
        }
        let unknownMedia = try subscription.handle(.init(identifier: "_mcc", content: ["_mcc": .uint(999)], transaction: nil, isRequest: false))
        precondition(unknownMedia == [.dictionary(["_i": .string("_mcc"), "_t": .uint(3), "_rT": .uint(0), "_c": .dictionary([:])])])
        let h = RemoteProfileHandler(name: "test", identifier: "test")
        func send(_ method: String, _ content: [String: WS2OPACK.Value] = [:]) throws {
            _ = try h.handle(.init(identifier: method, content: content, transaction: nil, isRequest: false))
        }
        func bad(_ method: String, _ content: [String: WS2OPACK.Value]) throws {
            do { try send(method, content); fatalError("accepted malformed \(method)") }
            catch is RemoteSessionProfile.Failure {}
        }
        try bad("_sessionStart", ["_sid": .uint(1), "sid": .uint(2)])
        try bad("_sessionStart", ["_sid": .uint(UInt64(UInt32.max) + 1)])
        try bad("_sessionStart", ["_srvT": .string("wrong")])
        try send("_sessionStart", ["sid": .uint(42)])
        precondition(h.profile.session! & 0xffffffff == 42)
        try bad("_sessionStop", ["_sid": .uint(42)])
        try send("_hidC", ["_hidC": .uint(6), "_hBtS": .uint(1)])
        try send("_hidC", ["_hidC": .uint(999), "_hBtS": .uint(1)])
        try send("_hidC", [:])
        let point: [String: WS2OPACK.Value] = ["_cx": .real(0.4), "_cy": .real(0.6)]
        for phase: UInt64 in [2, 1, 2, 4, 4, 99] {
            try send("_hidT", point.merging(["_tPh": .uint(phase)]) { _, rhs in rhs })
        }
        try send("_hidT", ["_tPh": .uint(1), "_cx": .real(.infinity), "_cy": .real(0)])
        precondition(h.profile.inputCounts.valid == 4)
        precondition(h.profile.inputCounts.summary["messages"] == 10)
        precondition(h.profile.inputCounts.summary["unknown"] == 2)
        precondition(h.profile.inputCounts.summary["invalid"] == 4)
        try send("_sessionStop", ["_sid": .uint(h.profile.session!)])
        try bad("_hidC", ["_hidC": .uint(6), "_hBtS": .uint(2)])
        try send("TVRCSessionStart")
        try send("_hidC", ["_hidC": .uint(6), "_hBtS": .uint(2)])
        try send("UnknownMethod")
        precondition(h.unknownCounts["messages"] == 1)
        h.reset()
        precondition(h.profile.inputCounts.valid == 0 && h.profile.counts.isEmpty && h.unknownCounts.isEmpty)
        let bytes = try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
        FileHandle.standardOutput.write(bytes)
    }
}
