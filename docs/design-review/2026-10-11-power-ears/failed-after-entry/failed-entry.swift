import Cocoa

/// Production compact drawing only: synthetic flash, no battery source/AX announcements/timer policy.
@main enum PowerEarPreview {
 enum Failure:Error {case check(String)}
 @MainActor static func main() async {
  _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
  let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  do {
   try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
   var frames:[[String:Any]]=[]
   for appearance in [NSAppearance.Name.aqua,.darkAqua] {
    let parent=appearance == .aqua ? "light":"dark"
    for (state,kind,percent,tone,symbol) in [
     ("plug-zero",PowerFlashKind.plug,0,PowerFlashTone.red,"bolt.fill"),
     ("plug-five",.plug,5,.red,"bolt.fill"),("plug-twenty",.plug,20,.red,"bolt.fill"),
     ("plug-twenty-one",.plug,21,.green,"bolt.fill"),("plug-eighty-two",.plug,82,.green,"bolt.fill"),
     ("plug-hundred",.plug,100,.green,"bolt.fill"),("full",.full,100,.green,"battery.100percent"),
     ("low-power",.lowPowerMode,82,.yellow,"battery.50percent")
    ] {
     let panel=NotchPanel(notch:NSRect(x:-8000,y:866.5,width:185,height:33.5),virtual:false)
     panel.isReleasedWhenClosed=false;panel.alphaValue=0;panel.appearance=NSAppearance(named:appearance)
     defer {panel.setCompact(nil,room:nil);panel.close()}
     var policy=PowerFlashPolicy()
     func reading(_ value:Int,_ charged:Bool=false,_ mode:Bool=false)->BatteryReading {
      BatteryReading(deviceID:InternalBattery.deviceID,component:.main,provider:InternalBattery.providerName,providerEpoch:1,percent:value,charging:.notCharging,sourceObservedAt:nil,receivedAt:0,isCharged:charged,lowPowerMode:mode)
     }
     let flash:PowerFlash
     if kind == .plug {
      _=policy.observe(reading(percent),now:0)
      var next=reading(percent);next.charging = .charging
      guard let generated=policy.observe(next,now:1).flash else {throw Failure.check("synthetic plug policy")};flash=generated
     } else if kind == .full {
      var baseline=reading(82);baseline.charging = .charging
      _=policy.observe(baseline,now:0)
      guard let generated=policy.observe(reading(100,true),now:1).flash else {throw Failure.check("synthetic full policy")};flash=generated
     } else {
      _=policy.observe(reading(percent),now:0)
      guard let generated=policy.observe(reading(percent,false,true),now:1).flash else {throw Failure.check("synthetic low power policy")};flash=generated
     }
     guard flash.kind==kind,flash.tone==tone,NSImage(systemSymbolName:flash.symbol,accessibilityDescription:nil) != nil else {throw Failure.check("actual policy payload/symbol")}
     _=symbol // legacy before-fixture names retained only in state table; actual policy supplies symbols.
     panel.setCompact(.init(count:0,changed:false,leading:flash.spoken,trailing:flash.trailing,flash:flash),room:.init(leading:34,trailing:34))
     try await Task.sleep(nanoseconds:800_000_000)
     guard let canvas=panel.contentView else {throw Failure.check("canvas")}
     canvas.layoutSubtreeIfNeeded()
     func nodes(_ v:NSView)->[NSView] {[v]+v.subviews.flatMap{nodes($0)}}
     guard let compact=nodes(canvas).compactMap({$0 as? NotchCompactView}).first,
      let slots=Mirror(reflecting:compact).children.first(where:{$0.label=="slots"})?.value as? (leading:NSRect,trailing:NSRect) else {throw Failure.check("actual compact slots")}
     let actual=Mirror(reflecting:compact).children.first(where:{$0.label=="compact"})?.value as? NotchPanel.Compact
     guard actual?.flash==flash else {throw Failure.check("actual compact payload")}
     let outside=NSScreen.screens.allSatisfy{!$0.frame.intersects(panel.frame)}
     guard outside,!NSApp.isActive,panel.alphaValue==0 else {throw Failure.check("escaped")}
     let color=NotchCompactView.flashColor(tone).usingColorSpace(.sRGB)!
     let layout=NotchCompactView.flashPercentageLayout(flash,in:slots.trailing,color:color)
     guard layout.frame.minX>=slots.trailing.minX+2,layout.frame.maxX<=slots.trailing.maxX-2,
      layout.frame.minY>=slots.trailing.minY,layout.frame.maxY<=slots.trailing.maxY else {throw Failure.check("percentage clipped")}
     for value in 0...100 {
      let sample=PowerFlash(kind:.plug,percent:value,tone:.green,symbol:"bolt.fill",trailing:"\(value)%",spoken:"")
      let box=NotchCompactView.flashPercentageLayout(sample,in:slots.trailing,color:color).frame
      guard box.minX>=slots.trailing.minX+2,box.maxX<=slots.trailing.maxX-2 else {throw Failure.check("percentage font boundary \(value)")}
     }
     guard let rep=canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds) else {throw Failure.check("bitmap")}
     canvas.cacheDisplay(in:canvas.bounds,to:rep)
     guard let png=rep.representation(using:.png,properties:[:]) else {throw Failure.check("png")}
     let name=parent+"-"+state+".png";try png.write(to:out.appendingPathComponent(name))
     frames.append(["image":name,"state":state,"width":canvas.bounds.width,"height":canvas.bounds.height,"compactWidth":compact.bounds.width,"compactHeight":compact.bounds.height,"trailing":actual!.flash!.trailing,"textWidth":layout.frame.width,"availableTextWidth":slots.trailing.width-4,"fontPointSize":(layout.text.attribute(.font,at:0,effectiveRange:nil) as? NSFont)?.pointSize ?? 0,"wholeRangeFontFits":101,"symbol":actual!.flash!.symbol,"tone":tone.rawValue,"colorRGB":[color.redComponent,color.greenComponent,color.blueComponent],"leadingSlot":[slots.leading.minX,slots.leading.minY,slots.leading.width,slots.leading.height],"trailingSlot":[slots.trailing.minX,slots.trailing.minY,slots.trailing.width,slots.trailing.height],"alpha":panel.alphaValue,"activeApplication":NSApp.isActive,"intersectsScreen":!outside,"synthetic":true,"realBatterySource":false,"powerFlashAPIOrAXUsed":false])
     try JSONSerialization.data(withJSONObject:frames,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("frames.json"))
    }
   }
   print("Rendered \(frames.count) actual compact flash payload frames; no real sources/persistent settings/announcement API.")
  } catch {print("FAILED power ears: \(error)");exit(1)}
 }
}
