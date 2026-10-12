import Cocoa

/// Static production WelcomeView first two pages. No permission queries or preference writes.
@main enum WelcomeStatePreview {
 enum Failure:Error {case check(String)}
 @MainActor static func main() async {
  _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
  let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  do {
   try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
   let before=UserDefaults.standard.object(forKey:SwitcherOrigin.defaultsKey) as? String
   var frames:[[String:Any]]=[]
   for appearance in [NSAppearance.Name.aqua,.darkAqua] {
    let parent=appearance == .aqua ? "light":"dark"
    let samples:[(String,Int,WelcomePreview)]=[
     ("intro-stuck",0,.init(moment:0.2,origin:.unanswered,notched:true)),
     ("intro-hint",0,.init(moment:0.5,origin:.unanswered,notched:true)),
     ("intro-no-notch",0,.init(moment:0.5,origin:.unanswered,notched:false)),
     ("origin-unanswered",1,.init(moment:0,origin:.unanswered,notched:true)),
     ("origin-windows",1,.init(moment:0,origin:.windows,notched:true)),
     ("origin-ipad",1,.init(moment:0,origin:.ipad,notched:true)),
     ("origin-mac",1,.init(moment:0,origin:.mac,notched:true))]
    for (state,page,preview) in samples {
     let window=NSWindow(contentRect:NSRect(x:-8000,y:-8000,width:WelcomeView.size.width,height:WelcomeView.size.height),styleMask:[.titled,.closable,.fullSizeContentView],backing:.buffered,defer:false)
     window.isReleasedWhenClosed=false;window.alphaValue=0;window.appearance=NSAppearance(named:appearance)
     window.setFrame(NSRect(origin:NSPoint(x:-8000,y:-8000),size:window.frame.size),display:false)
     window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.tabbingMode = .disallowed
     let view=WelcomeView(frame:NSRect(origin:.zero,size:WelcomeView.size))
     let background=NSVisualEffectView(frame:NSRect(origin:.zero,size:WelcomeView.size))
     background.material=SystemAppearancePolicy.usesOpaqueFallback(SystemAppearanceCapabilities.current) ? .contentBackground:.underPageBackground
     background.blendingMode = .withinWindow
     view.autoresizingMask=[.width,.height];background.addSubview(view)
     window.contentView=background
     defer {window.contentView=nil;window.close()}
     var permissionQueries=0
     view.permissionsGranted={permissionQueries += 1;return false};view.show(page,preview:preview);view.refreshButtons()
     view.layoutSubtreeIfNeeded()
     try await Task.sleep(nanoseconds:200_000_000)
     let outside=NSScreen.screens.allSatisfy({!$0.frame.intersects(window.frame)})
     guard !window.isVisible,!NSApp.isActive,window.alphaValue==0,outside,permissionQueries==0 else {
      try JSONSerialization.data(withJSONObject:["state":state,"windowFrame":NSStringFromRect(window.frame),"visible":window.isVisible,"active":NSApp.isActive,"outside":outside,"permissionQueries":permissionQueries],options:[.prettyPrinted]).write(to:out.appendingPathComponent("failure.json"))
      throw Failure.check("escaped or permission queried")
     }
     func nodes(_ v:NSView)->[NSView] {[v]+v.subviews.flatMap{nodes($0)}}
     let visible=nodes(view).filter{!$0.isHiddenOrHasHiddenAncestor}
     let labels=visible.compactMap{$0 as? NSTextField}.map{v->[String:Any] in let r=v.convert(v.bounds,to:view);return ["text":v.stringValue,"x":r.minX,"y":r.minY,"width":r.width,"height":r.height]}
     guard let rep=background.bitmapImageRepForCachingDisplay(in:background.bounds) else {throw Failure.check("bitmap")}
     background.cacheDisplay(in:background.bounds,to:rep)
     guard let png=rep.representation(using:.png,properties:[:]) else {throw Failure.check("png")}
     let name=parent+"-"+state+".png";try png.write(to:out.appendingPathComponent(name))
     frames.append(["image":name,"state":state,"page":view.index,"width":view.bounds.width,"height":view.bounds.height,"nextEnabled":view.next.isEnabled,"labels":labels,"visibleWindow":window.isVisible,"activeApplication":NSApp.isActive,"alpha":window.alphaValue,"syntheticStage":true,"preferencesWritten":false,"permissionQueries":permissionQueries])
     try JSONSerialization.data(withJSONObject:frames,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("frames.json"))
    }
   }
   guard (UserDefaults.standard.object(forKey:SwitcherOrigin.defaultsKey) as? String)==before else {throw Failure.check("origin changed")}
   print("Rendered \(frames.count) actual WelcomeView first-two-page static frames; origin unchanged, no permission calls.")
  } catch {print("FAILED welcome preview: \(error)");exit(1)}
 }
}
