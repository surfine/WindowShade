import Cocoa

/// Production owned views driven by isolated synthetic stdio states; no login/browser/user projects.
enum OwnedStatePreview {
 enum Failure:Error {case check(String)}
 @MainActor static func until(_ label:String,_ predicate:()->Bool) async throws {
  let end=ProcessInfo.processInfo.systemUptime+10
  while !predicate(),ProcessInfo.processInfo.systemUptime<end {try await Task.sleep(nanoseconds:20_000_000)}
  guard predicate() else {throw Failure.check(label)}
 }
 @MainActor static func render(_ out:URL) async throws {
  _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
  try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
  let temp=FileManager.default.temporaryDirectory.appendingPathComponent("owned-state-"+UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
  let original=try String(contentsOfFile:"tests/fixtures/conductor-backend.py",encoding:.utf8)
  let controller=WS2OwnedLaunchController(profileRoot:temp.appendingPathComponent("profile"),mayUse:{true})
  var frames:[[String:Any]]=[],browserRequests=0
  controller.onBrowserURL={_ in browserRequests += 1}
  do {
   for appearance in [NSAppearance.Name.aqua,.darkAqua] {
    let parent=appearance == .aqua ? "light":"dark"
    for state in ["signed-out","config-rejected","malformed-account","long-models"] {
     let project=temp.appendingPathComponent(parent+"-"+state,isDirectory:true)
     try FileManager.default.createDirectory(at:project,withIntermediateDirectories:true)
     var text=original
     if state=="signed-out" {text=text.replacingOccurrences(of:"\"account\": {\"type\": \"chatgpt\"}",with:"\"account\": None")}
     if state=="config-rejected" {text=text.replacingOccurrences(of:"\"approval_policy\": \"on-request\"",with:"\"approval_policy\": \"never\"")}
     if state=="malformed-account" {text=text.replacingOccurrences(of:", \"requiresOpenaiAuth\": True",with:"")}
     let longModel=String(repeating:"synthetic-long-model-",count:14)+"a"
     if state=="long-models" {text=text.replacingOccurrences(of:"[\"fixture-a\", \"fixture-b\"]",with:"[\""+longModel+"\", \"fixture-b\"]")}
     let backend=project.appendingPathComponent("synthetic-codex.py")
     try text.write(to:backend,atomically:true,encoding:.utf8)
     try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:backend.path)
     guard controller.selectProject(project),controller.selectExecutable(backend),controller.launch(consent:true) else {throw Failure.check("launch")}
     if state=="signed-out" {try await until("signed out"){controller.phase == .signedOut}}
     else if state=="long-models" {
      try await until("ready"){controller.phase == .ready}
      guard controller.chooseModel(longModel) else {throw Failure.check("actual long model")}
     } else {try await until("failed reap"){controller.phase == .stopped && !controller.isBusy}}
     let view=WS2OwnedSessionView(controller:controller)
     view.inputIsCurrent={true};view.onCancel={};view.openModelPicker={};view.openConductorPage={}
     try await capture(view,state:state,parent:parent,appearance:appearance,controller:controller,out:out,frames:&frames)
     if state=="long-models" {
      let picker=WS2ModelPickerView(controller:controller);picker.inputIsCurrent={true};picker.onCancel={}
      picker.hostScreenWidth = 1440
      try await capture(picker,state:"long-model-picker",parent:parent,appearance:appearance,controller:controller,out:out,frames:&frames)
     }
     controller.stop(clearPrivate:true);try await until("stop own child"){!controller.isBusy}
    }
   }
  } catch {
   controller.stop(clearPrivate:true);try? await until("failure cleanup"){!controller.isBusy}
   try? JSONSerialization.data(withJSONObject:["error":String(describing:error),"childReaped":!controller.isBusy,"temporaryRoot":temp.path],options:[.prettyPrinted]).write(to:out.appendingPathComponent("failure.json"))
   throw error
  }
  guard !controller.isBusy,browserRequests==0 else {throw Failure.check("cleanup/browser")}
  try FileManager.default.removeItem(at:temp)
  try JSONSerialization.data(withJSONObject:["childReaped":true,"temporaryRemoved":!FileManager.default.fileExists(atPath:temp.path),"browserRequests":browserRequests,"synthetic":true],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("cleanup.json"))
  print("Rendered \(frames.count) actual owned auth/error/long-model frames, own child reaped, no browser.")
 }
 @MainActor static func capture(_ content:NSView & WS2LeaseContent,state:String,parent:String,appearance:NSAppearance.Name,controller:WS2OwnedLaunchController,out:URL,frames:inout [[String:Any]]) async throws {
  let panel=NotchPanel(notch:NSRect(x:-8000,y:866.5,width:185,height:33.5),virtual:false)
  panel.isReleasedWhenClosed=false;panel.alphaValue=0;panel.appearance=NSAppearance(named:appearance)
  defer {content.revoke();panel.setInteraction(nil,animated:false);panel.close()}
  panel.setInteraction(content,animated:false)
  (content as? WS2OwnedSessionView)?.render()
  try await Task.sleep(nanoseconds:500_000_000)
  guard let canvas=panel.contentView else {throw Failure.check("canvas")}
  canvas.layoutSubtreeIfNeeded()
  let outside=NSScreen.screens.allSatisfy{!$0.frame.intersects(panel.frame)}
  guard outside,!NSApp.isActive,panel.alphaValue==0 else {throw Failure.check("escaped")}
  func nodes(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{nodes($0)}}
  let visible=nodes(content).filter{!$0.isHiddenOrHasHiddenAncestor}
  let labels=visible.compactMap{$0 as? NSTextField}.map{field->[String:Any] in
   let r=field.convert(field.bounds,to:content)
   return ["text":field.stringValue,"x":r.minX,"y":r.minY,"width":r.width,"height":r.height]
  }
  let buttons=visible.compactMap{$0 as? NSButton}.map{button->[String:Any] in
   let r=button.convert(button.bounds,to:content)
   return ["title":button.title,"enabled":button.isEnabled,"x":r.minX,"y":r.minY,"width":r.width,"height":r.height]
  }
  let name=parent+"-"+state+".png"
  guard let rep=canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds) else {throw Failure.check("bitmap")}
  canvas.cacheDisplay(in:canvas.bounds,to:rep)
  guard let png=rep.representation(using:.png,properties:[:]) else {throw Failure.check("png")}
  try png.write(to:out.appendingPathComponent(name))
  frames.append(["image":name,"state":state,"synthetic":true,"phase":String(describing:controller.phase),"status":controller.status,"notice":controller.notice,"canSend":controller.canSend,"canChooseModel":controller.canChooseModel,"selectedModel":controller.model as Any? ?? NSNull(),"width":canvas.bounds.width,"height":canvas.bounds.height,"contentWidth":content.bounds.width,"contentHeight":content.bounds.height,"panelAlpha":panel.alphaValue,"intersectsScreen":!outside,"activeApplication":NSApp.isActive,"labels":labels,"buttons":buttons])
  try JSONSerialization.data(withJSONObject:frames,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("frames.json"))
 }
}
