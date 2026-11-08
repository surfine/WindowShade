import Cocoa

/// Production file shelf, state matrix (no user file actions), synthetic QA files only.
@main enum FileShelfStatePreview {
 enum Failure: Error { case check(String) }

 @MainActor static func main() async {
  do {try await render()} catch {
   let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
   try? FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
   try? JSONSerialization.data(withJSONObject:["passed":false,"error":String(describing:error)],options:[.prettyPrinted]).write(to:out.appendingPathComponent("failure.json"))
   print("FAILED FileShelf states: \\(error)");exit(1)
  }
 }

 static let states=["empty","one","many","long-name","wide-name","unicode-name","cleared","restored"]

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
   for state in states {
    try await renderState(state:state,parent:parent,appearance:appearance,out:out,frames:&frames)
   }
  }
  defaults.setVolatileDomain(argumentDomain,forName:UserDefaults.argumentDomain)
  guard FileShelf.enabled==enabledBefore else {throw Failure.check("switch restore")}
  guard frames.count==states.count*2 else {throw Failure.check("frame count")}
  try JSONSerialization.data(withJSONObject:frames,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("frames.json"))
  try JSONSerialization.data(withJSONObject:["temporaryDirectoriesRemoved":true,"volatileDomainRestored":true,"realUserFileActions":false,"syntheticFrames":frames.count],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("cleanup.json"))
  print("Rendered \\(frames.count) production file shelf state frames; own files removed, local switch restored, no user file actions.")
 }

 /// 文件名：只有长名、宽名、Unicode 名三种是特殊名；其余用序号短名。
 static func fileName(state:String,index:Int)->String {
  switch state {
  case "long-name": return String(repeating:"long-file-name-",count:10)+".txt"
  case "wide-name": return String(repeating:"W",count:80)+".pdf"
  case "unicode-name": return String(repeating:"字👨‍👩‍👧‍👦",count:8)+".txt"
  default: return "样件文件\\(index+1).txt"
  }
 }

 @MainActor static func renderState(state:String,parent:String,appearance:NSAppearance.Name,out:URL,frames:inout [[String:Any]]) async throws {
  let temp=FileManager.default.temporaryDirectory.appendingPathComponent("fileshelf-state-"+UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
  let store=FileShelfStore(root:temp.appendingPathComponent("shelf"),isEnabled:{true})
  let controller=FileShelfController(store:store)
  let panel=NotchPanel(notch:NSRect(x:-8000,y:866.5,width:185,height:33.5),virtual:false)
  panel.isReleasedWhenClosed=false;panel.alphaValue=0;panel.appearance=NSAppearance(named:appearance)
  let card=FileShelfView(controller:controller,hasNotch:true,strip:33.5)
  var cleaned=false
  func cleanupOnce() {
   guard !cleaned else {return};cleaned=true
   card.revoke();panel.setInteraction(nil,animated:false);panel.close()
   store.observe(nil);store.stop();store.flush()
   try? FileManager.default.removeItem(at:temp)
  }
  defer {cleanupOnce()}
  controller.start()
  let base=state == "cleared" || state == "restored" ? "cleared" : state
  let count=base == "empty" ? 0:base == "many" ? 7:1
  for index in 0..<count {
   let file=temp.appendingPathComponent(fileName(state:base,index:index))
   try Data("Self-created QA text only.".utf8).write(to:file)
   store.add(urls:[file]);store.flush()
  }
  try await awaitRows(controller,count)
  guard controller.rows.count==count else {throw Failure.check("rows \\(state)")}
  if base == "cleared" {
   controller.removeAll();store.flush()
   try await awaitRows(controller,0)
   guard controller.rows.isEmpty else {throw Failure.check("cleared rows")}
  } else if state == "restored" {
   controller.removeAll();store.flush()
   try await awaitRows(controller,0)
   guard controller.rows.isEmpty else {throw Failure.check("restored cleared rows")}
   controller.undo();store.flush()
   try await awaitRows(controller,1)
   guard controller.rows.count==1 else {throw Failure.check("restored rows")}
  }
  card.inputIsCurrent={true};card.onCancel={};card.rowsChanged()
  panel.setInteraction(card,animated:false)
  try await Task.sleep(nanoseconds:700_000_000)
  guard let canvas=panel.contentView else {throw Failure.check("canvas")}
  canvas.layoutSubtreeIfNeeded()
  let outside=NSScreen.screens.allSatisfy{!$0.frame.intersects(panel.frame)}
  guard outside,!NSApp.isActive,panel.alphaValue==0 else {throw Failure.check("fixture escaped")}
  let clearPending=controller.clear.isPending(at:controller.now)
  guard clearPending==(state == "cleared") else {throw Failure.check("clear pending \\(state)")}
  let image="\\(parent)-\\(state).png"
  guard let rep=canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds) else {throw Failure.check("bitmap")}
  canvas.cacheDisplay(in:canvas.bounds,to:rep)
  guard let png=rep.representation(using:.png,properties:[:]) else {throw Failure.check("png")}
  try png.write(to:out.appendingPathComponent(image))
  func tiles(_ node:NSView)->[FileShelfTileView] {
   (node as? FileShelfTileView).map{[$0]} ?? node.subviews.flatMap{tiles($0)}
  }
  let measured=tiles(card).sorted{$0.frame.minX<$1.frame.minX}
  guard measured.count==count else {throw Failure.check("tiles \\(state)")}
  let font=NSFont.systemFont(ofSize:11)
  var linesOut:[[String:Any]]=[]
  for tile in measured {
   let lines=card.nameLines(of:tile)
   let widths=lines.map{(line:String)->Double in
    Double((line as NSString).size(withAttributes:[.font:font]).width)
   }
   linesOut.append(["join":lines.joined(separator:"\n"),"lines":lines,"lineWidths":widths])
  }
  let labels=textFields(card).filter{!hiddenAncestor($0)}.map{$0.stringValue}
  frames.append(["image":image,"state":state,"parent":parent,"synthetic":true,"count":count,
    "width":canvas.bounds.width,"height":canvas.bounds.height,
    "contentWidth":card.bounds.width,"contentHeight":card.bounds.height,
    "panelAlpha":panel.alphaValue,"intersectsScreen":!outside,"activeApplication":NSApp.isActive,
    "names":controller.rows.map{$0.entry.name},"tileRects":measured.map{tileRect($0,canvas:canvas)},
    "scrollWidth":card.scrollFrame.width,"scrollHeight":card.scrollFrame.height,
    "nameLines":linesOut,"clearPending":clearPending,"visibleLabelTexts":labels,"typeIconsOnly":true])
  try JSONSerialization.data(withJSONObject:frames,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("frames.json"))
  if base == "cleared" {
   // 让 cleared 的撤销计时器失效，再彻底清掉，别留待删项。
   controller.undo();store.flush()
  }
  cleanupOnce()
  guard !FileManager.default.fileExists(atPath:temp.path) else {throw Failure.check("cleanup")}
 }

 /// 格子在整张卡坐标里的位置（用 canvas 换算，供排版核对）。
 @MainActor static func tileRect(_ tile:FileShelfTileView,canvas:NSView)->[Double] {
  let r=tile.convert(tile.bounds,to:canvas)
  return [Double(r.minX),Double(r.minY),Double(r.width),Double(r.height)]
 }

 /// 递归拿所有 NSTextField；不含隐藏祖先。
 static func textFields(_ node:NSView)->[NSTextField] {
  var found:[NSTextField]=[]
  if let field=node as? NSTextField {found.append(field)}
  for sub in node.subviews {found.append(contentsOf:textFields(sub))}
  return found
 }

 static func hiddenAncestor(_ view:NSView)->Bool {
  var node:NSView?=view
  while let current=node {
   if current.isHidden {return true}
   node=current.superview
  }
  return false
 }

 @MainActor static func awaitRows(_ controller:FileShelfController,_ count:Int) async throws {
  let deadline=ProcessInfo.processInfo.systemUptime+5
  while controller.rows.count != count,ProcessInfo.processInfo.systemUptime<deadline {try await Task.sleep(nanoseconds:20_000_000)}
 }
}

extension FileShelfView {
 /// 一格现在实际排出来的名字行。main 会加 `var nameLines:[String]`；这里先按同一份逻辑算，接口对上就能换。
 func nameLines(of tile:FileShelfTileView)->[String] {
  _=tile
  let text=nameForStatePreview(of:tile.row)
  return text.components(separatedBy:"\n")
 }

 private func nameForStatePreview(of row:FileShelfRow)->String {
  if SystemQuietState.shared.state.redactsPrivateTiles {return row.availability.label.map{"文件\n"+$0} ?? "文件"}
  if let label=row.availability.label {return FileShelfTileName.stale(row.entry.name,reason:label)}
  return FileShelfTileName.display(row.entry.name)
 }
}
