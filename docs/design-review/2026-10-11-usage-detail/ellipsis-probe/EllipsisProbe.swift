import Cocoa
@MainActor final class Black:NSView {override func draw(_ r:NSRect){NSColor.black.setFill();bounds.fill()}}
@main enum EllipsisProbe {
 @MainActor static func main() throws {
  _ = NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
  let root=Black(frame:NSRect(x:0,y:0,width:520,height:392))
  let window=NSWindow(contentRect:root.bounds,styleMask:[.borderless],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.alphaValue=0;window.contentView=root;window.setFrame(NSRect(x:-8000,y:-8000,width:520,height:392),display:false);defer{window.close()}
  let text="演示模型 — "+String(repeating:"跨领域推理与图像分析",count:12)
  var records=[[String:Any]]()
  for (i,name) in ["wrap","tail-then-wrap","wrap-then-tail","attributed-tail"].enumerated() {
   let f=NSTextField(wrappingLabelWithString:text);f.font = .systemFont(ofSize:13);f.textColor = .white;f.maximumNumberOfLines=2;f.preferredMaxLayoutWidth=484
   switch i {
   case 0:f.lineBreakMode = .byWordWrapping
   case 1:f.lineBreakMode = .byTruncatingTail;(f.cell as? NSTextFieldCell)?.wraps=true
   case 2:(f.cell as? NSTextFieldCell)?.wraps=true;f.lineBreakMode = .byTruncatingTail
   default:
    let p=NSMutableParagraphStyle();p.lineBreakMode = .byTruncatingTail
    f.attributedStringValue=NSAttributedString(string:text,attributes:[.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.white,.paragraphStyle:p])
   }
   let title=NSTextField(labelWithString:name);title.font = .systemFont(ofSize:11);title.textColor = .white;title.frame=NSRect(x:18,y:368-CGFloat(i)*64,width:484,height:15);root.addSubview(title)
   f.frame=NSRect(x:18,y:328-CGFloat(i)*64,width:484,height:32);root.addSubview(f)
   records.append(["name":name,"wraps":(f.cell as? NSTextFieldCell)?.wraps ?? false,"mode":f.lineBreakMode.rawValue,"height":f.intrinsicContentSize.height])
  }
  let title=NSTextField(labelWithString:"TextKit max2 + container tail");title.font = .systemFont(ofSize:11);title.textColor = .white;title.frame=NSRect(x:18,y:112,width:484,height:15);root.addSubview(title)
  let container=NSTextContainer(containerSize:NSSize(width:484,height:32));container.lineFragmentPadding=0;container.maximumNumberOfLines=2;container.lineBreakMode = .byTruncatingTail
  let manager=NSLayoutManager();manager.addTextContainer(container)
  let store=NSTextStorage(string:text,attributes:[.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.white]);store.addLayoutManager(manager)
  let view=NSTextView(frame:NSRect(x:18,y:72,width:484,height:32),textContainer:container);view.isEditable=false;view.isSelectable=false;view.drawsBackground=false;view.textContainerInset = .zero;root.addSubview(view)
  manager.ensureLayout(for:container)
  records.append(["name":"textkit","height":manager.usedRect(for:container).height])
  root.layoutSubtreeIfNeeded()
  let rep=root.bitmapImageRepForCachingDisplay(in:root.bounds)!;root.cacheDisplay(in:root.bounds,to:rep)
  let out=URL(fileURLWithPath:CommandLine.arguments[1]);try rep.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent("probe.png"))
  try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("probe.json"))
  print("PASS own hidden Cocoa ellipsis probe")
 }
}
