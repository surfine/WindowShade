import Cocoa

/// Production file shelf, type icons only, process-local switch and self-created files.
@main enum FileShelfStatePreview {
 enum Failure: Error { case check(String) }
 @MainActor static func main() async {
  do {try await render()} catch {
   let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
   try? JSONSerialization.data(withJSONObject:["passed":false,"error":String(describing:error)],options:[.prettyPrinted]).write(to:out.appendingPathComponent("failure.json"))
   print("FAILED FileShelf surface: \(error)");exit(1)
  }
 }
 @MainActor static func render() async throws {
  _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
  let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
  let defaults=UserDefaults.standard
  let argumentDomain=defaults.volatileDomain(forName:UserDefaults.argumentDomain)
  let enabledBefore=FileShelf.enabled
  var local=argumentDomain;local[FileShelf.enabledKey]=true
  defaults.setVolatileDomain(local,forName:UserDefaults.argumentDomain)
  defer {defaults.setVolatileDomain(argumentDomain,forName:UserDefaults.argumentDomain)}
  guard FileShelf.enabled else {throw Failure.check("local switch")}
  var frames:[[String:Any]]=[]
  for appearance in [NSAppearance.Name.aqua,.darkAqua] {
   let parent=appearance == .aqua ? "light":"dark"
   for state in ["empty","one","many","long-name","wide-name","unicode-name","missing","cleared","restored"] {
    let temp=FileManager.default.temporaryDirectory.appendingPathComponent("fileshelf-surface-"+UUID().uuidString,isDirectory:true)
    try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
    let store=FileShelfStore(root:temp.appendingPathComponent("shelf"),isEnabled:{true})
    let controller=FileShelfController(store:store)
    let panel=NotchPanel(notch:NSRect(x:-8000,y:866.5,width:185,height:33.5),virtual:false)
    panel.isReleasedWhenClosed=false;panel.alphaValue=0;panel.appearance=NSAppearance(named:appearance)
    let card=FileShelfView(controller:controller,hasNotch:true,strip:33.5)
    defer {card.revoke();panel.setInteraction(nil,animated:false);panel.close();controller.undo();store.clearAll();store.flush();store.observe(nil);store.stop();store.flush();try? FileManager.default.removeItem(at:temp)}
    controller.start()
    let count=state == "empty" ? 0:state == "many" ? 7:1
    var ownFiles:[URL]=[]
    for index in 0..<count {
     let name:String
     switch state {
     case "long-name":name=String(repeating:"long-file-name-",count:10)+".txt"
     case "wide-name":name=String(repeating:"W",count:80)+".pdf"
     case "unicode-name":name=String(repeating:"字👨‍👩‍👧‍👦",count:8)+".txt"
     default:name="样件文件\(index+1).txt"
     }
     let file=temp.appendingPathComponent(name)
     try Data("Self-created QA text only.".utf8).write(to:file)
     ownFiles.append(file);store.add(urls:[file]);store.flush()
    }
    let deadline=ProcessInfo.processInfo.systemUptime+5
    while controller.rows.count != count,ProcessInfo.processInfo.systemUptime<deadline {try await Task.sleep(nanoseconds:20_000_000)}
    guard controller.rows.count==count else {throw Failure.check("rows")}
    func waitRows(_ wanted:Int) async throws {
     let deadline=ProcessInfo.processInfo.systemUptime+5
     while controller.rows.count != wanted,ProcessInfo.processInfo.systemUptime<deadline {try await Task.sleep(nanoseconds:20_000_000)}
     guard controller.rows.count==wanted else {throw Failure.check("state rows")}
    }
    if state == "missing" {
     try FileManager.default.removeItem(at:ownFiles[0])
     store.addText("自造样件资料");store.flush();try await waitRows(2)
     guard controller.rows.contains(where:{$0.availability == .missing}) else {throw Failure.check("missing status")}
    }
    if state == "cleared" || state == "restored" {
     controller.removeAll();store.flush();try await waitRows(0)
     guard controller.clear.isPending(at:controller.now) else {throw Failure.check("clear pending")}
     if state == "restored" {
      controller.undo();store.flush();try await waitRows(1)
      guard !controller.clear.isPending(at:controller.now) else {throw Failure.check("undo clears pending")}
     }
    }
    card.inputIsCurrent={true};card.onCancel={};card.rowsChanged()
    panel.setInteraction(card,animated:false)
    try await Task.sleep(nanoseconds:700_000_000)
    guard let canvas=panel.contentView else {throw Failure.check("canvas")}
    canvas.layoutSubtreeIfNeeded()
    let outside=NSScreen.screens.allSatisfy{!$0.frame.intersects(panel.frame)}
    guard outside,!NSApp.isActive,panel.alphaValue==0 else {throw Failure.check("fixture escaped")}
    let image="\(parent)-\(state).png"
    guard let rep=canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds) else {throw Failure.check("bitmap")}
    canvas.cacheDisplay(in:canvas.bounds,to:rep)
    guard let png=rep.representation(using:.png,properties:[:]) else {throw Failure.check("png")}
    try png.write(to:out.appendingPathComponent(image))
    func tiles(_ node:NSView)->[FileShelfTileView] {
     (node as? FileShelfTileView).map{[$0]} ?? node.subviews.flatMap{tiles($0)}
    }
    let measured=tiles(card).sorted{$0.frame.minX<$1.frame.minX}
    let capturedCount=controller.rows.count
    guard measured.count==capturedCount else {throw Failure.check("tiles")}
    let measuredLines=measured.map{tile->[String:Any] in
     let lines=tile.nameLines
     return ["lines":lines,"widths":lines.map{NSAttributedString(string:$0,attributes:[.font:NSFont.systemFont(ofSize:11)]).size().width},"joined":lines.joined(separator:"\n"),"availability":String(describing:tile.row.availability)]
    }
    func labels(_ node:NSView)->[String] {
     if node.isHiddenOrHasHiddenAncestor {return []}
     return (node as? NSTextField).map{[$0.stringValue]} ?? node.subviews.flatMap{labels($0)}
    }
    frames.append(["image":image,"state":state,"synthetic":true,"count":capturedCount,"width":canvas.bounds.width,"height":canvas.bounds.height,"contentWidth":card.bounds.width,"contentHeight":card.bounds.height,"panelAlpha":panel.alphaValue,"intersectsScreen":!outside,"activeApplication":NSApp.isActive,"names":controller.rows.map{$0.entry.name},"tileRects":measured.map{[$0.frame.minX,$0.frame.minY,$0.frame.width,$0.frame.height]},"scrollWidth":card.scrollFrame.width,"scrollHeight":card.scrollFrame.height,"typeIconsOnly":true,"nameLines":measuredLines,"clearPending":controller.clear.isPending(at:controller.now),"visibleLabels":labels(card)])
    try JSONSerialization.data(withJSONObject:frames,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("frames.json"))
    if state == "one",let tile=measured.first {
     guard tile.removeButton.accessibilityPerformPress() else {throw Failure.check("fresh remove action")}
     store.flush();try await waitRows(0)
     guard FileManager.default.fileExists(atPath:ownFiles[0].path) else {throw Failure.check("remove moved original")}
     controller.undo();store.flush();try await waitRows(1)
     card.inputIsCurrent={false};_=tile.removeButton.accessibilityPerformPress();store.flush()
     try await Task.sleep(nanoseconds:50_000_000)
     guard controller.rows.count==1 else {throw Failure.check("stale remove")}
     card.revoke();_=tile.removeButton.accessibilityPerformPress();store.flush()
     try await Task.sleep(nanoseconds:50_000_000)
     guard controller.rows.count==1 else {throw Failure.check("revoked remove")}
     let check:[String:Any]=["passed":true,"freshRemoveAndUndo":true,"originalOwnFileStillExists":true,"staleRemovalBlocked":true,"revokedRemovalBlocked":true]
     try JSONSerialization.data(withJSONObject:check,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent(parent+"-action-check.json"))
    }
    card.revoke();panel.setInteraction(nil,animated:false);panel.close()
    controller.undo();store.clearAll();store.flush()
    guard !controller.clear.isPending(at:controller.now) else {throw Failure.check("pending clear cleanup")}
    store.observe(nil);store.stop();store.flush()
    try FileManager.default.removeItem(at:temp)
    guard !FileManager.default.fileExists(atPath:temp.path) else {throw Failure.check("cleanup")}
   }
  }
  defaults.setVolatileDomain(argumentDomain,forName:UserDefaults.argumentDomain)
  guard FileShelf.enabled==enabledBefore else {throw Failure.check("switch restore")}
  try JSONSerialization.data(withJSONObject:frames,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("frames.json"))
  try JSONSerialization.data(withJSONObject:["temporaryDirectoriesRemoved":true,"volatileDomainRestored":true,"realUserFileActions":false,"syntheticFrames":frames.count],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("cleanup.json"))
  print("Rendered \(frames.count) production file shelf frames; own files removed, local switch restored, no user file actions.")
 }
}
