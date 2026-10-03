import Foundation
/// Negative capability probe. Exit 2 is a real unresolved gap, NOT a passed feature test.
@main struct ExitInheritanceProbe {
    @MainActor static func main() async throws {
        let start = ProcessInfo.processInfo.systemUptime
        let process = try WS2DuplexProcess(executable:URL(fileURLWithPath:"/usr/bin/python3"),
            arguments:[CommandLine.arguments[1],"inherited"],workingDirectory:URL(fileURLWithPath:NSTemporaryDirectory()),
            environment:["PATH":"/usr/bin:/bin"],mayWrite:{true})
        var received:[String]=[]
        process.onLine = { received.append(String(decoding:$0,as:UTF8.self)) }
        try process.start()
        for _ in 0..<600 {
            if process.stopped && process.termination != nil { break }
            try? await Task.sleep(nanoseconds:5_000_000)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime-start
        let gap = elapsed >= 0.7 || received.contains("{\"late\":1}") || process.termination == nil
        let report:[String:Any] = ["probe":"PROC04","status":gap ? "BLOCKED" : "OBSERVED_PASS",
            "elapsedSeconds":elapsed,"receivedLines":received,"directChildExitObserved":process.termination != nil,
            "notProven":"Mac behavior; tree cleanup; immediate direct-child exit notification",
            "criterion":"close before the fixture descendant's 0.8s late write; test tolerance <0.7s"]
        process.stop();try? await Task.sleep(nanoseconds:850_000_000)
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        print("PROC04 \(gap ? "BLOCKED" : "OBSERVED_PASS") elapsed=\(elapsed)")
        if gap { exit(2) }
    }
}
