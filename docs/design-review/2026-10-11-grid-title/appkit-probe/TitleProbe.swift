import Cocoa
@main enum TitleProbe {
 final class Back: NSView { override func draw(_ r:NSRect) { NSColor.white.setFill(); r.fill() } }
 @MainActor static func main() {
  _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
  let root=Back(frame:NSRect(x:0,y:0,width:320,height:132))
  let text="季度报告 — "+String(repeating:"项目讨论与修改记录",count:12)
  var state:[[String:Any]]=[]
  for (i,mode) in [NSLineBreakMode.byTruncatingTail,.byWordWrapping].enumerated() {
   let label=NSTextField(wrappingLabelWithString:text); label.font=WindowBrowserTypography.title
   label.textColor = .black; label.maximumNumberOfLines=2;label.lineBreakMode=mode; label.cell?.truncatesLastVisibleLine=true
   label.frame=NSRect(x:12,y:CGFloat(80-i*52),width:296,height:34);root.addSubview(label)
   state.append(["mode":mode.rawValue,"wraps":label.cell?.wraps ?? false,"singleLine":label.cell?.usesSingleLineMode ?? false,"font":label.font?.pointSize ?? -1])
  }
  let window=NSWindow(contentRect:root.bounds,styleMask:[.borderless],backing:.buffered,defer:false)
  window.isReleasedWhenClosed=false;window.alphaValue=0;window.contentView=root
  window.setFrame(NSRect(x:-8000,y:-8000,width:320,height:132),display:false)
  precondition(!window.isVisible && !NSApp.isActive && NSScreen.screens.allSatisfy{!window.frame.intersects($0.frame)})
  root.layoutSubtreeIfNeeded()
  let bitmap=root.bitmapImageRepForCachingDisplay(in:root.bounds)!;root.cacheDisplay(in:root.bounds,to:bitmap)
  try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
  print(state);window.close()
 }
}
