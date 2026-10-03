import Foundation

@MainActor final class AllowedBox { var value = true }

@main struct ProcessTests {
    @MainActor static func main() async throws {
        let script = CommandLine.arguments[1], report = CommandLine.arguments[2]
        var scenarios = 0, checks = 0, failures: [String] = []
        func check(_ value: Bool, _ reason: String) { checks += 1; if !value { failures.append(reason); print("FAIL \(reason)") } }
        func wait(_ predicate: @escaping @MainActor () -> Bool) async -> Bool {
            for _ in 0..<400 {
                if predicate() { return true }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }; return false
        }
        func make(_ mode: String, mayWrite: @escaping @MainActor () -> Bool = { true }) throws -> WS2DuplexProcess {
            try WS2DuplexProcess(executable:URL(fileURLWithPath:"/usr/bin/python3"),arguments:[script,mode],
                workingDirectory:URL(fileURLWithPath:NSTemporaryDirectory()),environment:["PATH":"/usr/bin:/bin"],mayWrite:mayWrite)
        }
        scenarios += 1; print("SCENE IO01 split response, simultaneous write, stderr burst")
        let p = try make("duplex"); var lines: [Data] = []; var end: WS2DuplexProcess.End?; var admitted = false
        p.onLine = { bytes in
            lines.append(bytes)
            if lines.count == 1 {
                admitted = p.admitWireFrames([Data("{\"decision\":\"decline\"}\n".utf8)],connection:p.connection,
                    deadline:ProcessInfo.processInfo.systemUptime+1)
            }
        }; p.onEnd = { end = $0 }; try p.start()
        check(await wait { end != nil },"child completes without read/write deadlock")
        check(admitted && lines.count == 2,"approval reply and response received")
        check(lines.last.flatMap { String(data:$0,encoding:.utf8) }?.contains("decline") == true,"exact synthetic decline echoed")
        p.stop()
        scenarios += 1; print("SCENE IO02 pipe backpressure deadline closes without retry")
        let blocked = try make("blocked"); var blockedEnd: WS2DuplexProcess.End?; var ready = false
        blocked.onLine = { _ in ready = true }; blocked.onEnd = { blockedEnd = $0 }; try blocked.start()
        check(await wait { ready },"blocked child ready")
        check(blocked.admit([Data(repeating:120,count:1_000_000)],connection:blocked.connection,
            deadline:ProcessInfo.processInfo.systemUptime+0.10),"large frame admitted")
        check(await wait { blockedEnd != nil },"deadline fired independently of read readiness")
        check(blockedEnd == .timeout,"timeout closes")
        check(!blocked.admit([Data([1])],connection:blocked.connection,deadline:ProcessInfo.processInfo.systemUptime+1),"closed never replays")
        blocked.stop()
        scenarios += 1; print("SCENE IO03 truncated EOF rejected")
        let partial = try make("partial"); var partialEnd: WS2DuplexProcess.End?; var partialLines = 0
        partial.onLine = { _ in partialLines += 1 }; partial.onEnd = { partialEnd = $0 }; try partial.start()
        check(await wait { partialEnd != nil },"partial EOF observed")
        check(partialEnd == .framing && partialLines == 0,"partial line not delivered")
        partial.stop()
        scenarios += 1; print("SCENE IO04 EPIPE does not kill parent with SIGPIPE")
        let broken = try make("broken"); var brokenEnd: WS2DuplexProcess.End?; var brokenReady = false
        broken.onLine = { _ in brokenReady = true }; broken.onEnd = { brokenEnd = $0 }; try broken.start()
        check(await wait { brokenReady },"stdin closed in child")
        _ = broken.admit([Data([1])],connection:broken.connection,deadline:ProcessInfo.processInfo.systemUptime+1)
        check(await wait { brokenEnd != nil },"EPIPE handled")
        if case .io = brokenEnd { check(true,"I/O end") } else { check(false,"I/O end") }
        broken.stop()
        scenarios += 1; print("SCENE IO05 multiple coalesced lines delivered in order")
        let multi = try make("multi"); var multiLines: [Data] = []; var multiEnd: WS2DuplexProcess.End?
        multi.onLine = { multiLines.append($0) }; multi.onEnd = { multiEnd = $0 }; try multi.start()
        check(await wait { multiEnd != nil },"EOF after coalesced data")
        check(multiLines == ["{\"a\":1}","{\"b\":2}","{\"c\":3}"].map { Data($0.utf8) },"ordered split")
        multi.stop()
        scenarios += 1; print("SCENE IO06 oversized incoming line rejected")
        let huge = try make("oversized"); var hugeEnd: WS2DuplexProcess.End?
        huge.onEnd = { hugeEnd = $0 }; try huge.start()
        check(await wait { hugeEnd != nil },"oversize callback")
        check(hugeEnd == .framing,"memory bound closes")
        huge.stop()
        scenarios += 1; print("SCENE IO07 final write gate and stale epoch")
        let allowed = AllowedBox(); let gated = try make("blocked", mayWrite:{allowed.value}); var gatedReady = false
        gated.onLine = { _ in gatedReady = true }; try gated.start()
        check(await wait { gatedReady },"gated ready")
        check(!gated.admit([Data([1])],connection:UUID(),deadline:ProcessInfo.processInfo.systemUptime+1),"stale epoch")
        check(!gated.admitWireFrames([Data("{}\n{}\n".utf8)],connection:gated.connection,
            deadline:ProcessInfo.processInfo.systemUptime+1),"one line per wire frame")
        check(gated.admit([Data([1])],connection:gated.connection,deadline:ProcessInfo.processInfo.systemUptime+1),"queued before revoke")
        allowed.value = false
        check(await wait { gated.stopped },"revoked before actual write")
        gated.stop()
        scenarios += 1; print("SCENE IO08 per-batch context gate checked after admission")
        let batchAllowed = AllowedBox(); let batch = try make("blocked"); var batchReady = false; var localWrites = 0
        batch.onLine = { _ in batchReady = true }; batch.onLocallyWritten = { _ in localWrites += 1 }; try batch.start()
        check(await wait { batchReady },"batch child ready")
        check(batch.admitWireFrames([Data("{}\n".utf8)],connection:batch.connection,
            deadline:ProcessInfo.processInfo.systemUptime+1,binding:{batchAllowed.value}),"bound batch admitted")
        batchAllowed.value = false
        check(await wait { batch.stopped },"changed context closes queued batch")
        check(localWrites == 0,"revoked batch not marked locally written")
        batch.stop()
        let result: [String:Any] = ["scenarios":scenarios,"assertions":checks,"failures":failures,
            "backend":"owned Python fixture; no real assistant or network"]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:report))
        print("RESULT scenarios=\(scenarios) assertions=\(checks) failures=\(failures.count)")
        if !failures.isEmpty { Foundation.exit(1) }
    }
}
