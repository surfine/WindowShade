import Cocoa
#if !swift(>=6.0)
#error("PrivacyRowPreview requires Swift6")
#endif
@main enum PrivacyRowPreview {
    final class Background:NSView { override func draw(_ rect:NSRect) {NSColor.textBackgroundColor.setFill();rect.fill()} }
    enum Failure:Error {case check(String)}
    @MainActor static func onMain()->Bool {Thread.isMainThread}
    @MainActor static func main() async {
        _ = NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        do {
            try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
            var frames=[[String:Any]]()
            for parent in [NSAppearance.Name.aqua,.darkAqua] {
                for width:CGFloat in [640,448,300] {
                    for sample in ["battery","missing","denied","granted","long-value","expanded","technical","planned"] {
                        let id = ["denied","granted","expanded","technical"].contains(sample) ? "window-ax" : sample == "planned" ? "face-identity" : "battery"
                        guard let row=WS2PrivacyData.rows.first(where:{$0.id==id}) else {throw Failure.check("registered row")}
                        let value:String? = sample == "battery" ? "妙控鼠标 82%" : sample == "long-value" ? "演示配件 — "+String(repeating:"名字很长的键盘",count:8)+" 82%" : nil
                        let granted:Bool?=sample == "denied" ? false : ["granted","expanded","technical"].contains(sample) ? true : nil
                        let presentation=WS2PrivacyRowPresentation.make(row:row,value:value,hasValueSource:true,permissionGranted:granted)
                        let expanded=["expanded","technical","planned"].contains(sample)
                        var toggles=0
                        let view=PrivacyRowView(row:row,presentation:presentation,expanded:expanded,showDetails:sample == "technical",switchSpec:nil,grantTarget:nil,grantAction:nil,onToggle:{toggles += 1})
                        let host=Background(frame:NSRect(x:0,y:0,width:width+32,height:640))
                        host.widthAnchor.constraint(equalToConstant:width+32).isActive=true
                        host.addSubview(view)
                        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo:host.leadingAnchor,constant:16),view.trailingAnchor.constraint(equalTo:host.trailingAnchor,constant:-16),view.topAnchor.constraint(equalTo:host.topAnchor,constant:16)])
                        let window=NSWindow(contentRect:host.bounds,styleMask:[.borderless],backing:.buffered,defer:false)
                        window.isReleasedWhenClosed=false;window.alphaValue=0;window.appearance=NSAppearance(named:parent);window.contentView=host
                        window.setFrame(NSRect(x:-8000,y:-8000,width:host.bounds.width,height:host.bounds.height),display:false)
                        host.layoutSubtreeIfNeeded();try await Task.sleep(nanoseconds:100_000_000);host.layoutSubtreeIfNeeded()
                        let height=ceil(view.frame.height)+32
                        host.setFrameSize(NSSize(width:width+32,height:height));host.layoutSubtreeIfNeeded()
                        var labels=[[String:Any]]();var buttons=[[String:Any]]()
                        func visit(_ v:NSView) {
                            let rect=v.convert(v.bounds,to:view)
                            let box:[String:CGFloat]=["x":rect.minX,"y":rect.minY,"width":rect.width,"height":rect.height]
                            if let text=v as? NSTextField {
                                var components=[CGFloat]()
                                text.effectiveAppearance.performAsCurrentDrawingAppearance {
                                    if let c=text.textColor?.usingColorSpace(.sRGB) {components=[c.redComponent,c.greenComponent,c.blueComponent,c.alphaComponent]}
                                }
                                let needed=text.cell?.cellSize(forBounds:NSRect(x:0,y:0,width:text.bounds.width,height:10000)).height ?? 0
                                labels.append(["role":text.identifier?.rawValue ?? "header","color":components,"cellFittingHeight":needed,"editable":text.isEditable,"selectable":text.isSelectable,"text":text.stringValue,"tooltip":text.toolTip ?? "","frame":box,"font":text.font?.pointSize ?? 0,"naturalWidth":NSAttributedString(string:text.stringValue,attributes:[.font:text.font ?? NSFont.systemFont(ofSize:13)]).size().width,"wraps":text.cell?.wraps ?? false,"maxLines":text.maximumNumberOfLines,"breakMode":text.lineBreakMode.rawValue])
                            }
                            if let b=v as? NSButton {buttons.append(["title":b.title,"frame":box,"accessibilityLabel":b.accessibilityLabel() ?? "","isGrant":b.title==WS2PrivacyCopy.needsGrant])}
                            v.subviews.forEach(visit)
                        }
                        visit(view)
                        let name="\(parent == .aqua ? "light" : "dark")-\(Int(width))-\(sample)"
                        guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else {throw Failure.check("bitmap")}
                        host.cacheDisplay(in:host.bounds,to:bitmap)
                        guard let png=bitmap.representation(using:.png,properties:[:]) else {throw Failure.check("png")}
                        try png.write(to:out.appendingPathComponent(name+".png"))
                        frames.append(["name":name,"sample":sample,"rowID":row.id,"registeredStatus":row.status,"expanded":expanded,"width":width,"actualRowWidth":view.frame.width,"hostWidth":host.bounds.width,"height":view.frame.height,"labels":labels,"buttons":buttons,"visible":window.isVisible,"active":NSApp.isActive,"alpha":window.alphaValue,"mainThread":onMain(),"toggles":toggles])
                        window.contentView=nil;window.close()
                    }
                }
            }
            let report:[String:Any]=["frames":frames,"pageInstantiated":false,"sourcesRead":0,"grantActions":0,"exports":0,"settingsWrites":0,"globalInputEvents":0,"plannedFixtureOnly":true]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("frames.json"))
            print("PASS \(frames.count) actual privacy row native fixtures; no source/page/actions")
        } catch {fputs("FAIL \(error)\n",stderr);exit(1)}
    }
}
