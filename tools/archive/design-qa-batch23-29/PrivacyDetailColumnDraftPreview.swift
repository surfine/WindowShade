import Cocoa

@MainActor private final class DetailColumnDraft: NSView {
    let stack=NSStackView()
    var fields=[(key:String,role:String,view:NSTextField)]()
    init(lines:[(String,String)],width:CGFloat) {
        super.init(frame:.zero)
        stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=4
        stack.translatesAutoresizingMaskIntoConstraints=false;addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:leadingAnchor),stack.topAnchor.constraint(equalTo:topAnchor),stack.widthAnchor.constraint(equalToConstant:width),stack.bottomAnchor.constraint(equalTo:bottomAnchor)])
        let font=NSFont.systemFont(ofSize:12),column=font.pointSize*4.4
        for (key,value) in lines {
            func label(_ text:String,_ role:String,_ width:CGFloat)->NSTextField {
                let field=NSTextField(wrappingLabelWithString:text);field.font=font
                field.textColor = role == "label" ? .secondaryLabelColor : .labelColor
                field.maximumNumberOfLines=0;field.lineBreakMode = .byWordWrapping
                field.preferredMaxLayoutWidth=width;field.toolTip = role == "label" ? key : text
                field.widthAnchor.constraint(equalToConstant:width).isActive=true
                field.setContentCompressionResistancePriority(.required,for:.vertical)
                fields.append((key,role,field));return field
            }
            let title=key == "什么时候读" ? "什么时候" : key == "合起来能看出什么" ? "合起来看" : key
            let row=NSStackView(views:[label(title,"label",column),label(value,"body",width-column-10)])
            row.orientation = .horizontal;row.alignment = .firstBaseline;row.spacing=10
            row.widthAnchor.constraint(equalToConstant:width).isActive=true
            stack.addArrangedSubview(row)
        }
    }
    required init?(coder:NSCoder) {nil}
    override var intrinsicContentSize:NSSize {stack.fittingSize}
}

@main enum PrivacyDetailColumnDraftPreview {
    enum Failure:Error {case check(String)}
    final class Background:NSView {override func draw(_ rect:NSRect) {NSColor.textBackgroundColor.setFill();rect.fill()}}
    @MainActor static func onMain()->Bool {Thread.isMainThread}
    static func box(_ r:NSRect)->[String:CGFloat] { ["x":r.minX,"y":r.minY,"width":r.width,"height":r.height] }
    @MainActor static func main() async {
        _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        guard NSApp.delegate == nil else {fatalError("own entry only")}
        do {
            let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
            let registry=URL(fileURLWithPath:CommandLine.arguments[2])
            let data=try Data(contentsOf:registry)
            guard let json=try JSONSerialization.jsonObject(with:data) as? [String:Any],let signals=json["signals"] as? [[String:Any]],let sites=json["sites"] as? [[String:Any]] else {throw Failure.check("registry")}
            try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
            var frames=[[String:Any]]()
            for appearance in [NSAppearance.Name.aqua,.darkAqua] {
                for width:CGFloat in [640,448,300] {
                    for id in ["window-ax","battery","face-identity"] {
                        guard let source=signals.first(where:{$0["id"] as? String == id}) else {throw Failure.check("signal")}
                        for technical in [false,true] {
                            let keys=[("读到的","reads"),("为什么","purpose"),("去了哪里","destination"),("什么时候读","activation"),("开关","toggle"),("合起来能看出什么","combined")]
                            var lines=keys.compactMap { (label,key)->(String,String)? in guard let text=source[key] as? String,!text.isEmpty else {return nil};return (label,text) }
                            let interfaces=Array(Set(sites.filter{$0["signal"] as? String == id}.compactMap{$0["symbol"] as? String})).sorted()
                            if technical,!interfaces.isEmpty {lines.append(("接口",interfaces.joined(separator:"、")))}
                            let view=DetailColumnDraft(lines:lines,width:width)
                            let host=Background(frame:NSRect(x:0,y:0,width:width+32,height:700));host.widthAnchor.constraint(equalToConstant:width+32).isActive=true
                            view.translatesAutoresizingMaskIntoConstraints=false;host.addSubview(view)
                            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo:host.leadingAnchor,constant:16),view.topAnchor.constraint(equalTo:host.topAnchor,constant:16),view.widthAnchor.constraint(equalToConstant:width)])
                            let window=NSWindow(contentRect:host.bounds,styleMask:[.borderless],backing:.buffered,defer:false)
                            window.isReleasedWhenClosed=false;window.alphaValue=0;window.appearance=NSAppearance(named:appearance);window.contentView=host
                            window.setFrame(NSRect(x:-8000,y:-8000,width:width+32,height:700),display:false)
                            host.layoutSubtreeIfNeeded();try await Task.sleep(nanoseconds:100_000_000);host.layoutSubtreeIfNeeded()
                            host.setFrameSize(NSSize(width:width+32,height:ceil(view.fittingSize.height)+32));host.layoutSubtreeIfNeeded()
                            var fields=[[String:Any]]()
                            for field in view.fields {
                                var components=[CGFloat]()
                                field.view.effectiveAppearance.performAsCurrentDrawingAppearance {
                                    let color=field.view.textColor!.usingColorSpace(.sRGB)!
                                    components=[color.redComponent,color.greenComponent,color.blueComponent,color.alphaComponent]
                                }
                                fields.append(["key":field.key,"role":field.role,"text":field.view.stringValue,"tooltip":field.view.toolTip ?? "","frame":box(field.view.convert(field.view.bounds,to:view)),"font":field.view.font!.pointSize,"wraps":field.view.cell?.wraps ?? false,"maxLines":field.view.maximumNumberOfLines,"editable":field.view.isEditable,"selectable":field.view.isSelectable,"color":components])
                            }
                            let name="\(appearance == .aqua ? "light" : "dark")-\(Int(width))-\(id)-\(technical ? "technical" : "plain")"
                            guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else {throw Failure.check("bitmap")}
                            host.cacheDisplay(in:host.bounds,to:bitmap)
                            guard let png=bitmap.representation(using:.png,properties:[:]) else {throw Failure.check("png")}
                            try png.write(to:out.appendingPathComponent(name+".png"))
                            frames.append(["name":name,"id":id,"status":source["status"] as? String ?? "","technical":technical,"width":width,"actualWidth":view.bounds.width,"height":view.bounds.height,"hostSize":box(host.bounds),"fields":fields,"interfaces":interfaces,"visible":window.isVisible,"active":NSApp.isActive,"alpha":window.alphaValue,"mainThread":onMain()])
                            window.contentView=nil;window.close()
                        }
                    }
                }
            }
            let report:[String:Any]=["candidateOnly":true,"productionIntegration":false,"plannedFixtureOnly":true,"frames":frames,"realSources":0,"actions":0,"networkReads":0,"globalInputEvents":0,"preferencesWrites":0]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("frames.json"))
            print("PASS \(frames.count) own native column candidates; registry text only; no integration/source/actions")
        } catch {fputs("FAIL \(error)\n",stderr);exit(1)}
    }
}
