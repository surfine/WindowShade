import Foundation
@main struct WireProfileTests {
    static func main() throws {
        let zero = WS2.Instant.zero
        var failures:[String]=[], checks=0, emitted:[Data]=[]
        func check(_ v:Bool,_ m:String) { checks += 1;if !v{failures.append(m)} }
        func json(_ value:WireJSON) throws -> Data { try JSONEncoder().encode(value)+Data([10]) }
        func ready() throws -> CodexWire {
            var w=CodexWire();try w.initialize(now:zero);_ = w.drain()
            _ = try w.ingest(json(.object(["id":.integer(1),"result":.object([:])])),now:zero);_ = w.drain()
            _ = try w.ingest(json(.object(["id":.integer(2),"result":.object(["data":.array([
                .object(["model":.string("test-model"),"supportedReasoningEfforts":.array([.object(["reasoningEffort":.string("medium")])])])])])])),now:zero)
            return w
        }
        var start=try ready();try start.startThread(cwd:"/tmp/fixture-project",model:"test-model",now:zero)
        let sf=start.drain();emitted += sf;let a=try JSONDecoder().decode(WireJSON.self,from:sf[0])
        check(a["params"]?["sandbox"] == .string("read-only"),"start sandbox")
        check(a["params"]?["approvalPolicy"] == .string("on-request"),"start policy")
        check(a["params"]?["approvalsReviewer"] == .string("user"),"start reviewer")
        _ = try start.ingest(json(.object(["id":.integer(3),"result":.object(["thread":.object(["id":.string("t")])])])),now:zero)
        try start.startTurn(text:"Synthetic request",model:"test-model",effort:"medium",now:zero)
        let tf=start.drain();emitted += tf;let b=try JSONDecoder().decode(WireJSON.self,from:tf[0])
        check(b["params"]?["sandboxPolicy"]?["type"] == .string("readOnly"),"turn sandbox")
        check(b["params"]?["sandboxPolicy"]?["networkAccess"] == .bool(false),"turn network")
        check(b["params"]?["approvalsReviewer"] == .string("user"),"turn reviewer")
        var resume=try ready();try resume.resumeThread(id:"known-thread",now:zero)
        let rf=resume.drain();emitted += rf;let c=try JSONDecoder().decode(WireJSON.self,from:rf[0])
        check(c["params"]?["sandbox"] == .string("read-only"),"resume sandbox")
        check(c["params"]?["approvalsReviewer"] == .string("user"),"resume reviewer")
        var pagination=CodexWire();try pagination.initialize(now:zero);_ = pagination.drain()
        _ = try pagination.ingest(json(.object(["id":.integer(1),"result":.object([:])])),now:zero);_ = pagination.drain()
        _ = try pagination.ingest(json(.object(["id":.integer(2),"result":.object(["data":.array([]),"nextCursor":.string("next")])])),now:zero)
        let pf=pagination.drain();emitted += pf;let d=try JSONDecoder().decode(WireJSON.self,from:pf[0])
        check(d["params"]?["includeHidden"] == .bool(false),"pagination retains filter")
        var invalid=try ready()
        do {try invalid.startThread(cwd:"/tmp/a\0b",model:"test-model",now:zero);check(false,"NUL cwd rejected")}catch{check(true,"NUL cwd rejected")}
        check(invalid.drain().isEmpty,"invalid request not emitted")
        let report:[String:Any]=["scenarios":5,"assertions":checks,"failures":failures,"boundary":"Synthetic CodexWire fixtures; no real CLI or sandbox enforcement"]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
        try emitted.reduce(Data(),+).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        print("RESULT scenarios=5 assertions=\(checks) failures=\(failures.count)");if !failures.isEmpty{exit(1)}
    }
}
