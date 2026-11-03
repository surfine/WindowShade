import Foundation
@MainActor func waitUntil(_ predicate:()->Bool)async->Bool{
 let start=ProcessInfo.processInfo.systemUptime
 while !predicate(),ProcessInfo.processInfo.systemUptime-start<5{try? await Task.sleep(nanoseconds:10_000_000)}
 return predicate()
}
@main struct InputFlowTests {
 @MainActor static func main()async throws{
  let t=TestLog(),fm=FileManager.default
  let root=fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("ws2-r8-flow-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);defer{try? fm.removeItem(at:root)}
  let project=root.appendingPathComponent("project"),exe=root.appendingPathComponent("fake-codex-picker.py")
  try fm.createDirectory(at:project,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])).write(to:exe)
  try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:exe.path)
  var mayUse=true
  let c=WS2OwnedLaunchController(profileRoot:root.appendingPathComponent("state"),mayUse:{mayUse})
  t.begin("IFLOW01 real pipe catalogue supplies selection rows")
  t.check(c.selectProject(project),"local project");t.check(c.selectExecutable(exe),"local fixture");t.check(c.launch(consent:true),"explicit launch")
  let ready=await waitUntil({c.phase == .ready});t.check(ready,"actual handshake");t.check(c.models.keys.sorted()==["fixture-a","fixture-b"],"two actual backend rows");t.check(c.canChooseModel,"valid UI state")
  let h=try InputHarness();try h.sink.input.replace(c.models.keys.sorted().map{.init(id:$0,enabled:true)},selectedID:c.model)
  h.backend=c.session!.connectionID;h.sink.input.onActivate={c.chooseModel($0)}
  t.check(h.enable(),"local enable of substitute attachment");t.end()
  func log()throws->[String:Any]{["text":try String(contentsOf:exe.deletingPathExtension().appendingPathExtension("messages.ndjson"),encoding:.utf8)]}
  t.begin("IFLOW02 device chooses model without sending work")
  h.tap("down");h.tap("a");t.check(c.model=="fixture-b","selected current backend b");let before=try log()["text"] as! String
  t.check(!before.contains("thread/start") && !before.contains("turn/start"),"selection creates no model job");t.check(c.store.visibleSessions.isEmpty,"no fabricated session");t.end()
  t.begin("IFLOW03 separate local send uses selected model")
  t.check(!c.send("组字中",hasMarkedText:true),"IME protected");t.check(c.send("明确发送",hasMarkedText:false),"explicit send");t.check(!c.canChooseModel,"selection disabled while preparing")
  let complete=await waitUntil({c.phase == .completed});t.check(complete,"real synthetic stream completed")
  let bytes=try String(contentsOf:exe.deletingPathExtension().appendingPathExtension("messages.ndjson"),encoding:.utf8)
  let messages=try bytes.split(separator:"\n").map{try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
  let starts=messages.filter{($0["method"] as? String)=="thread/start"}
  let turns=messages.filter{($0["method"] as? String)=="turn/start"}
  t.check(starts.count==1 && turns.count==1,"one job only");t.check((starts[0]["params"] as? [String:Any])?["model"] as? String == "fixture-b","selected model on actual wire");t.end()
  t.begin("IFLOW04 late release after local capability loss cannot change model")
  h.holdA();mayUse=false;c.environmentChanged();h.sink.input.ready=c.canChooseModel;h.host.environmentChanged();h.releaseA()
  t.check(!h.active,"device revoked");t.check(!c.canChooseModel,"closed capability");let ended=await waitUntil({!c.isBusy});t.check(ended,"owned process actually reaped");t.end()
  t.begin("IFLOW05 reconnect uses a new backend epoch")
  mayUse=true;t.check(c.launch(consent:true),"explicit reconnect");let again=await waitUntil({c.phase == .ready});t.check(again,"reconnected")
  t.check(c.session!.connectionID != h.backend,"new scope");h.backend=c.session!.connectionID;h.sink.input.ready=true;h.host.environmentChanged()
  t.check(!h.active,"reconnect never reenables device");t.check(h.enable(),"local reenabling");t.end()
  t.begin("IFLOW06 project replacement rejected by actual model selector")
  try fm.moveItem(at:project,to:root.appendingPathComponent("previous-project"))
  try fm.createDirectory(at:project,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  t.check(!c.chooseModel("fixture-a"),"actual select revalidates replaced inode")
  let done=await waitUntil({!c.isBusy});t.check(done,"invalid scope shuts down and reaps");h.host.stop();t.check(h.bridge.installed.isEmpty,"all input subscriptions removed");t.end()
  try t.save(URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
