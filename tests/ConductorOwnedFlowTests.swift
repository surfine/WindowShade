import Foundation

@main struct ConductorOwnedFlowTests {
    enum Failure: Error { case check(String) }
    static func check(_ value:Bool,_ label:String) throws {
        guard value else { throw Failure.check(label) }
    }
    @MainActor static func until(_ label:String,_ predicate:()->Bool) async throws {
        let deadline=ProcessInfo.processInfo.systemUptime+8
        while !predicate(),ProcessInfo.processInfo.systemUptime<deadline { try await Task.sleep(for:.milliseconds(10)) }
        try check(predicate(),label)
    }
    @MainActor static func main() async throws {
        let root=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("ws2-conductor-"+UUID().uuidString)
        let project=root.appendingPathComponent("project"),exe=root.appendingPathComponent("synthetic-codex.py")
        try FileManager.default.createDirectory(at:project,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])).write(to:exe)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:exe.path)
        var unlocked=true
        let c=WS2OwnedLaunchController(profileRoot:root.appendingPathComponent("state"),mayUse:{unlocked})
        defer { c.stop(clearPrivate:true) }
        try check(c.selectProject(project) && c.selectExecutable(exe),"select fixture")
        func launch() async throws {
            try check(c.launch(consent:true),"launch fixture")
            try await until("fixture ready") { c.phase == .ready }
            try check(c.chooseModel("fixture-a"),"choose real catalogue model")
        }
        func shutdown() async throws { c.stop();try await until("reaped") { !c.isBusy } }
        func count(_ method:String) throws -> Int {
            let url=project.appendingPathComponent("protocol.jsonl")
            return try String(contentsOf:url,encoding:.utf8).split(separator:"\n").filter { line in
                let value=try? JSONDecoder().decode(WireJSON.self,from:Data(line.utf8))
                return value?["method"]?.text==method
            }.count
        }
        func adopt(_ text:String) throws -> WS2OwnedLaunchController.ConductorDraft {
            guard let target=c.conductorTarget,let value=c.adoptConductorDraft(text,hasMarkedText:false,target:target) else { throw Failure.check("adopt "+text) }
            return value
        }
        try await launch()
        try check(c.conductorSessions.isEmpty && c.conductorTarget==nil,"no fabricated initial thread")
        try check(c.send("bootstrap-1",hasMarkedText:false),"create first real fixture thread")
        try await until("first completed") { c.phase == .completed }
        let first=c.conductorSessions[0]
        let firstPrepared=try adopt("draft-for-first")
        let oldConnection=c.conductorTarget
        try await shutdown()
        try check(c.selectProject(project) && c.draft=="draft-for-first","reselecting same project preserves draft")
        try await launch()
        try check(c.send("bootstrap-2",hasMarkedText:false),"create second fixture thread")
        try await until("second completed") { c.phase == .completed }
        let second=c.conductorSessions.first { $0.context.session != first.context.session }!
        let secondTarget=c.conductorTarget!
        try check(!c.sendConductorDraft(firstPrepared,hasMarkedText:false),"old connection draft cannot send")
        try check(c.conductorSessions.count==2,"known same-project sessions listed")
        let secondDraft=try adopt("draft-for-second")
        try check(c.selectConductorSession(first.context.session,revision:first.context.epoch),"request actual thread/resume")
        try check(c.conductorTarget==nil && !c.sendConductorDraft(secondDraft,hasMarkedText:false),"switch pending rejects old input")
        try await until("first selected by backend") { c.conductorTarget?.context.session==first.context.session }
        try check(c.draft=="draft-for-first","draft follows its session")
        try check(c.conductorTarget?.connection != oldConnection?.connection,"fresh connection identity")
        try check(c.conductorTarget != secondTarget,"selection changed actual target")
        try check(!c.selectConductorSession(.init(provider:.codex,id:"foreign"),revision:1),"unowned session refused")
        try check(!c.selectConductorSession(second.context.session,revision:second.context.epoch+99),"stale row refused")
        let sendsBefore=try count("turn/start")
        let pending=try adopt("hold first")
        try await Task.sleep(for:.milliseconds(30))
        try check(try count("turn/start")==sendsBefore,"adoption sends nothing")
        try check(!c.sendConductorDraft(pending,hasMarkedText:true),"IME cannot send")
        try check(c.chooseEffort("high"),"choose next effort")
        try check(!c.sendConductorDraft(pending,hasMarkedText:false),"config change invalidates adopted draft")
        let send=try adopt("hold first")
        try check(c.sendConductorDraft(send,hasMarkedText:false),"explicit send")
        try check(!c.sendConductorDraft(send,hasMarkedText:false),"duplicate send refused")
        _=c.editDraft("newer text while awaiting receipt")
        try await until("running after actual reply") { c.phase == .running }
        try check(c.draft=="newer text while awaiting receipt","old receipt preserves new draft")
        try check(c.notice=="助手已接收","reply is surfaced")
        let sentTurn=c.conductorTurn!
        let beforeConfig=try count("turn/start")
        try check(c.stageConductorModel("fixture-b",target:c.conductorTarget!),"running permits next-turn model")
        try check(c.stageConductorEffort("high",target:c.conductorTarget!),"running permits next-turn effort")
        try await Task.sleep(for:.milliseconds(30))
        try check(try count("turn/start")==beforeConfig && count("turn/steer")==0,"config changes send no request")
        try check(!c.selectConductorSession(second.context.session,revision:second.context.epoch),"running turn cannot be retargeted")
        let add=try adopt("add this")
        try check(!c.sendConductorDraft(add,hasMarkedText:false),"new-turn API cannot silently steer")
        try check(c.addConductorDraftToTurn(add,hasMarkedText:false),"explicit add to current turn")
        try check(!c.addConductorDraftToTurn(add,hasMarkedText:false),"no duplicate steer")
        try await until("steer acknowledgement") { c.notice=="已补进这一轮" }
        try check(c.draft.isEmpty && c.conductorTurn==sentTurn,"matching receipt clears only accepted draft")
        let reject=try adopt("reject")
        try check(c.addConductorDraftToTurn(reject,hasMarkedText:false),"send rejected fixture")
        try await until("steer rejection") { c.notice.contains("拒绝") }
        try check(c.draft=="reject" && c.phase == .running,"refused draft preserved")
        let stopTarget=c.conductorTarget!
        try check(c.interruptConductor(target:stopTarget,turn:sentTurn),"explicit stop bound to current turn")
        try await Task.sleep(for:.milliseconds(50))
        try check(c.phase == .interrupting,"interrupt RPC is not stopped")
        try await until("actual stopped notification") { c.status=="助手已停止" }
        try check(!c.interruptConductor(target:stopTarget,turn:sentTurn),"old stop cannot reach later turn")
        _=c.editDraft("")
        let next=try adopt("next uses staged model")
        try check(c.sendConductorDraft(next,hasMarkedText:false),"next turn explicit send")
        try await until("next completed") { c.phase == .completed }
        let messages=try String(contentsOf:project.appendingPathComponent("protocol.jsonl"),encoding:.utf8).split(separator:"\n").map { try JSONDecoder().decode(WireJSON.self,from:Data($0.utf8)) }
        let lastStart=messages.last { $0["method"]?.text=="turn/start" }!
        try check(lastStart["params"]?["model"]?.text=="fixture-b" && lastStart["params"]?["effort"]?.text=="high","staged config applied only next turn")
        let stale=try adopt("must not cross reconnect")
        try check(c.selectConductorSession(second.context.session,revision:second.context.epoch),"switch back")
        try await until("second selected") { c.conductorTarget?.context.session==second.context.session }
        try check(c.draft=="draft-for-second" && !c.sendConductorDraft(stale,hasMarkedText:false),"cross-target draft and old send separated")
        let liveFirst=c.conductorSessions.first { $0.context.session==first.context.session }!
        try check(c.selectConductorSession(liveFirst.context.session,revision:liveFirst.context.epoch),"return to same session")
        try await until("returned first") { c.conductorTarget?.context.session==first.context.session }
        try check(!c.sendConductorDraft(stale,hasMarkedText:false),"ABA target change does not revive old send")
        let locked=try adopt("private lock draft")
        unlocked=false;c.environmentChanged()
        try check(c.draft.isEmpty && c.conductorSessions.isEmpty && !c.sendConductorDraft(locked,hasMarkedText:false),"lock revokes input and clears drafts")
        try await until("lock reaped") { !c.isBusy }
        unlocked=true
        try await launch()
        try check(c.resumeLast(),"resume after explicit reconnect")
        try await until("resumed") { c.conductorTarget != nil }
        let running=try adopt("hold wrong receipt")
        try check(c.sendConductorDraft(running,hasMarkedText:false),"new explicit turn")
        try await until("running for negative receipt") { c.phase == .running }
        let wrong=try adopt("wrong-turn")
        try check(c.addConductorDraftToTurn(wrong,hasMarkedText:false),"send negative receipt fixture")
        try await until("wrong target receipt closes") { !c.isBusy }
        try check(c.draft=="wrong-turn" && c.notice.contains("没有把缺失状态当成成功"),"wrong turn ack is not success and preserves draft")
        print("PASS Conductor owned flow: real stdio, known session resume, draft adoption/send separation, stale target/config/IME/replay rejection, next-turn settings, start/steer/interrupt receipts, draft preservation and lock invalidation")
    }
}
