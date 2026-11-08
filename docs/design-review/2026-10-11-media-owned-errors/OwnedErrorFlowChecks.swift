import Foundation
import CryptoKit

@main enum OwnedErrorFlowChecks {
 enum Failure: Error { case check(String) }
 @MainActor static func until(_ label:String,_ predicate:()->Bool) async throws {
  let end=ProcessInfo.processInfo.systemUptime+10
  while !predicate(),ProcessInfo.processInfo.systemUptime<end {try await Task.sleep(nanoseconds:20_000_000)}
  guard predicate() else {throw Failure.check(label)}
 }
 @MainActor static func main() async {
  let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  let temp=FileManager.default.temporaryDirectory.appendingPathComponent("owned-errors-"+UUID().uuidString,isDirectory:true)
  let controller=WS2OwnedLaunchController(profileRoot:temp.appendingPathComponent("profile"),mayUse:{true})
  var records:[[String:Any]]=[],failure:String?
  do {
   try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
   try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
   let original=try String(contentsOfFile:"tests/fixtures/conductor-backend.py",encoding:.utf8)
   for mode in ["signed-out","config-rejected","malformed-account","manual-stop"] {
    let project=temp.appendingPathComponent(mode,isDirectory:true)
    try FileManager.default.createDirectory(at:project,withIntermediateDirectories:true)
    var text=original
    if mode == "signed-out" {text=text.replacingOccurrences(of:"\"account\": {\"type\": \"chatgpt\"}",with:"\"account\": None")}
    if mode == "config-rejected" {text=text.replacingOccurrences(of:"\"approval_policy\": \"on-request\"",with:"\"approval_policy\": \"never\"")}
    if mode == "malformed-account" {text=text.replacingOccurrences(of:", \"requiresOpenaiAuth\": True",with:"")}
    let backend=project.appendingPathComponent("synthetic-codex.py")
    try text.write(to:backend,atomically:true,encoding:.utf8)
    try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:backend.path)
    let before=controller.observedReaps
    guard controller.selectProject(project),controller.selectExecutable(backend),controller.launch(consent:true) else {throw Failure.check("launch")}
    if mode == "signed-out" || mode == "manual-stop" {
     try await until("connected") {controller.phase == (mode == "signed-out" ? .signedOut:.ready)}
     if mode == "signed-out" {
      records.append(["mode":mode,"passed":!controller.canSend && !controller.canChooseModel,"status":controller.status,"canSend":controller.canSend,"canChooseModel":controller.canChooseModel])
     }
     controller.stop(clearPrivate:true)
    }
    try await until("reaped") {!controller.isBusy && controller.session == nil && controller.observedReaps>before}
    if mode == "config-rejected" || mode == "malformed-account" {
     let retained=mode == "config-rejected" ? (controller.status.contains("配置") || controller.status.contains("设置")):(controller.status.contains("状态不完整") || controller.status.contains("信息不完整"))
     records.append(["mode":mode,"passed":retained,"status":controller.status,"notice":controller.notice,"reaped":true,"canSend":controller.canSend])
    } else if mode == "manual-stop" {
     records.append(["mode":mode,"passed":controller.status=="已断开","status":controller.status,"reaped":true])
    }
   }
  } catch {failure=String(describing:error)}
  controller.stop(clearPrivate:true)
  do {try await until("final cleanup"){!controller.isBusy}} catch {failure="cleanup: "+String(describing:error)}
  let reaped = !controller.isBusy
  if reaped {try? FileManager.default.removeItem(at:temp)}
  let removed = !FileManager.default.fileExists(atPath:temp.path)
  let result:[String:Any]=["records":records,"failure":failure as Any? ?? NSNull(),"passed":failure==nil && records.count==4 && records.allSatisfy{$0["passed"] as? Bool == true} && reaped && removed,"cleanup":["reaped":reaped,"temporaryRemoved":removed],"synthetic":true]
  try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("checks.json"))
  for record in records {print("\(record["mode"]!): \(record["status"]!), passed=\(record["passed"]!)")}
  exit(result["passed"] as? Bool == true ? 0:1)
 }
}
