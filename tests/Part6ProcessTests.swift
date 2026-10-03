import Foundation

@main struct ProcessTests {
    @MainActor static func main() async throws {
        let script = CommandLine.arguments[1], report = CommandLine.arguments[2]
        var failures: [String] = [], cases: [String] = [], assertions = 0
        func scene(_ name: String) { cases.append(name); print("SCENE \(name)") }
        func check(_ value: Bool, _ message: String) {
            assertions += 1; if !value { failures.append("\(cases.last ?? "?"): \(message)"); print("FAIL \(message)") }
        }
        func wait(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
            for _ in 0..<600 { if condition() { return true }; try? await Task.sleep(nanoseconds:5_000_000) }
            return false
        }
        func make(_ mode: String, limit: Int? = nil, mayWrite: @escaping () -> Bool = { true }) throws -> WS2DuplexProcess {
            try .init(executable:URL(fileURLWithPath:"/usr/bin/python3"),arguments:[script,mode],
                      workingDirectory:URL(fileURLWithPath:NSTemporaryDirectory()),environment:["PATH":"/usr/bin:/bin"],
                      diagnosticByteLimit:limit,mayWrite:mayWrite)
        }
        scene("PROC01 explicit bounded diagnostic tail does not block stdout")
        let tail=try make("tail",limit:4096); var tailLines:[Data]=[], tailEnds=0
        tail.onLine={tailLines.append($0)};tail.onEnd={_ in tailEnds += 1};try tail.start()
        check(await wait {tail.stopped},"process completes")
        check(tailLines == [Data("{\"complete\":true}".utf8)],"stdout unaffected")
        check((tail.diagnostics?.bytes.count ?? 0) <= 4096,"retained bound")
        check((tail.diagnostics?.observedBytes ?? 0) >= 1_048_576,"large burst observed")
        check(tail.diagnostics?.visibleText().contains("\\u{001B}") == true,"terminal escape escaped")
        tail.stop();check(tailEnds==1,"one end callback")
        scene("PROC02 default diagnostics stays disabled")
        let off=try make("tail");try off.start();check(await wait {off.stopped},"default no deadlock")
        check(off.diagnostics == nil,"no implicit retention");off.stop()
        scene("PROC03 direct child exit status is separate from protocol outcome")
        let exit7=try make("exit7");var last:[Data]=[];exit7.onLine={last.append($0)};try exit7.start()
        check(await wait {exit7.stopped && exit7.termination != nil},"exit event recorded")
        check(exit7.termination?.status==7 && exit7.termination?.wasSignalled==false,"nonzero status preserved")
        check(last == [Data("{\"last\":1}".utf8)],"final line drained");exit7.stop()
        // PROC04 is an explicit release-blocking probe in ExitInheritanceProbe.swift.
        scene("PROC05 partial final frame rejected")
        let truncated=try make("truncated");var reason:WS2DuplexProcess.End?;truncated.onEnd={reason=$0};try truncated.start()
        check(await wait {reason != nil},"partial ends");check(reason == .framing,"not successful completion");truncated.stop()
        scene("PROC06 coalesced trailing frames retain ordering")
        let many=try make("many");var count=0, ordered=true
        many.onLine={ data in if data != Data("{\"n\":\(count)}".utf8){ordered=false};count += 1 };try many.start()
        check(await wait {many.stopped},"many ends");check(count==4000 && ordered,"all ordered frames");many.stop()
        scene("PROC07 stop closes transport once and waits for independent exit evidence")
        let hold=try make("hold");var ready=false, ends=0;hold.onLine={_ in ready=true};hold.onEnd={_ in ends += 1};try hold.start()
        check(await wait {ready},"ready before stop");hold.stop();hold.stop()
        check(hold.stopped && ends==1,"stop idempotent")
        check(await wait {hold.termination != nil},"fixture direct child really exited")
        check(!hold.admit([Data("{}".utf8)],connection:hold.connection,deadline:ProcessInfo.processInfo.systemUptime+1),"no writes after stop")
        scene("PROC08 diagnostic buffer can be explicitly cleared")
        check(tail.diagnostics?.bytes.isEmpty == false,"test retained bytes")
        tail.clearDiagnostics();check(tail.diagnostics?.bytes.isEmpty == true && tail.diagnostics?.observedBytes==0,"clear")
        scene("PROC09 invalid diagnostic limit rejected before spawning")
        do {_ = try make("hold",limit:65537);check(false,"over limit refused")} catch {check(true,"over limit refused")}
        do {_ = try make("hold",limit:0);check(false,"zero refused")} catch {check(true,"zero refused")}
        scene("PROC10 late scope change blocks an admitted frame")
        var allowed=true, gatedReady=false, delivered=0
        let gated=try make("echo",mayWrite:{allowed});gated.onLine={_ in gatedReady=true};gated.onLocallyWritten={_ in delivered += 1};try gated.start()
        check(await wait {gatedReady},"gated ready")
        check(gated.admitWireFrames([Data("{}\n".utf8)],connection:gated.connection,deadline:ProcessInfo.processInfo.systemUptime+1),"queued")
        allowed=false;check(await wait {gated.stopped},"scope change closes");check(delivered==0,"not marked written");gated.stop()
        let result:[String:Any]=["scenarios":cases.count,"assertions":assertions,"failures":failures,"cases":cases,
          "boundary":"Real Python child/pipe/one short-lived fork fixture, no CLI service, Mac SDK, network, or process-tree kill"]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:report))
        print("RESULT scenarios=\(cases.count) assertions=\(assertions) failures=\(failures.count)")
        if !failures.isEmpty{exit(1)}
    }
}
