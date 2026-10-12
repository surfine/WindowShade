import Cocoa
#if !swift(>=6.0)
#error("Swift6 required")
#endif
@main enum PrivacyPageCompositionPreview {
    final class Host:NSView {override var isFlipped:Bool {true}; override func draw(_ rect:NSRect){NSColor.textBackgroundColor.setFill();rect.fill()}}
    final class Mock:NSObject {var actions=0; @objc func pressed(_ sender:Any?){actions += 1}}
    enum Failure:Error {case check(String)}
    @MainActor static func label(_ text:String,_ offset:CGFloat = 0,_ weight:NSFont.Weight = .regular)->NSTextField {
        let f=NSTextField(wrappingLabelWithString:text);f.font=SystemAppearancePolicy.font(relativeToBody:offset,weight:weight);f.maximumNumberOfLines=0;return f
    }
    // Candidate composition of the existing UI factories; no AppDelegate is created.
    @MainActor static func card(_ rows:[NSView])->NSView {
        let box=SettingsGroupBox();box.translatesAutoresizingMaskIntoConstraints=false
        let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=0;stack.translatesAutoresizingMaskIntoConstraints=false;box.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:box.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:box.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:box.topAnchor,constant:10),stack.bottomAnchor.constraint(equalTo:box.bottomAnchor,constant:-10)])
        for (i,row) in rows.enumerated(){
            if i>0 {let sep=NSBox();sep.boxType = .separator;sep.translatesAutoresizingMaskIntoConstraints=false;stack.addArrangedSubview(sep);sep.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true;sep.heightAnchor.constraint(equalToConstant:0.5).isActive=true}
            stack.addArrangedSubview(row);row.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        };return box
    }
    @MainActor static func note(_ lead:String,_ text:String)->NSView {
        let a=label(lead,0,.semibold),b=label(text,-2);b.textColor = .secondaryLabelColor
        let s=NSStackView(views:[a,b]);s.orientation = .vertical;s.alignment = .leading;s.spacing=4
        b.widthAnchor.constraint(equalTo:s.widthAnchor).isActive=true;return s
    }
    @MainActor static func main() async {
        _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        do { try await run(URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)) }
        catch { fputs("FAIL \(error)\n",stderr); exit(1) }
    }
    /// 第26批组合入口调用这个：写到指定子目录（与动效探针输出互不覆盖）。出错就抛，由调用方决定退出码。
    @MainActor static func run(_ out:URL) async throws {
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
            var frames=[[String:Any]]()
            let visible=WS2PrivacyVisibility.visibleRows(WS2PrivacyData.rows,enabledFeatures:[])
            for appearance in [NSAppearance.Name.aqua,.darkAqua] {for expanded in [false,true] {
                let mock=Mock(),root=Host(frame:NSRect(x:0,y:0,width:696,height:600)),doc=Host(frame:NSRect(x:0,y:0,width:696,height:600))
                let scroll=NSScrollView(frame:root.bounds);scroll.hasVerticalScroller=true;scroll.drawsBackground=false;scroll.documentView=doc;root.addSubview(scroll)
                let page=NSStackView();page.orientation = .vertical;page.alignment = .leading;page.spacing=16;page.translatesAutoresizingMaskIntoConstraints=false;doc.addSubview(page)
                NSLayoutConstraint.activate([page.leadingAnchor.constraint(equalTo:doc.leadingAnchor,constant:28),page.widthAnchor.constraint(equalToConstant:640),page.topAnchor.constraint(equalTo:doc.topAnchor,constant:22)])
                page.addArrangedSubview(WS2SettingsCopy.content(name:nil,subtitle:WS2PrivacyCopy.headerSubtitle(),symbol:WS2SettingsCopy.tableSymbol("lock.shield")).view)
                let readAt=label(WS2PrivacyCopy.readAtText(Date(timeIntervalSince1970:0),timeZone:TimeZone(secondsFromGMT:0)!),-2);readAt.textColor = .secondaryLabelColor
                let reread=NSButton(title:WS2PrivacyCopy.rereadTitle,target:mock,action:#selector(Mock.pressed(_:)));reread.bezelStyle = .rounded;reread.controlSize = .small
                let details=NSButton(checkboxWithTitle:WS2PrivacyCopy.showDetailsTitle,target:mock,action:#selector(Mock.pressed(_:)));details.state=expanded ? .on:.off;details.controlSize = .small
                let export=NSButton(title:WS2PrivacyCopy.exportTitle,target:mock,action:#selector(Mock.pressed(_:)));export.bezelStyle = .rounded;export.controlSize = .small
                let spacer=NSView();spacer.setContentHuggingPriority(.init(1),for:.horizontal)
                let toolbar=NSStackView(views:[readAt,reread,spacer,details,export]);toolbar.spacing=12;toolbar.alignment = .centerY;page.addArrangedSubview(toolbar);toolbar.widthAnchor.constraint(equalTo:page.widthAnchor).isActive=true
                var rowViews=[(String,PrivacyRowView)](),groupNames=[String]()
                for group in WS2PrivacyData.groups {
                    let rows=visible.filter{$0.group==group.title};guard !rows.isEmpty || group.title==WS2PrivacyCopy.destinationGroupTitle else {continue}
                    groupNames.append(group.title)
                    let heading=label(group.title,-1,.semibold);heading.textColor = .secondaryLabelColor
                    let caption=label(group.subtitle,-2);caption.textColor = .tertiaryLabelColor
                    let header=NSStackView(views:group.subtitle.isEmpty ? [heading]:[heading,caption]);header.alignment = .firstBaseline;header.spacing=8;page.addArrangedSubview(header);page.setCustomSpacing(8,after:header)
                    if group.title==WS2PrivacyCopy.destinationGroupTitle {
                        let network=WS2PrivacyCopy.networkCard(primaryHost:"updates.example.invalid",fallbackHost:"github.example.invalid")
                        for n in [note(network.lead,network.body),note(WS2PrivacyCopy.storageCard.lead,WS2PrivacyCopy.storageCard.body)]{let c=card([n]);page.addArrangedSubview(c);c.widthAnchor.constraint(equalTo:page.widthAnchor).isActive=true}
                    }
                    if !rows.isEmpty {
                        let views=rows.map {row -> NSView in
                            let titles=["activities":"实时活动","calendar":"日程","downloads":"浏览器下载","login":"登录时自动启动","autoUpdate":UpdateCopy.autoCheck,"desktop":"桌面开合","focusQuiet":"专注模式时更安静"]
                            let spec=row.switchID.flatMap {id in titles[id].map {PrivacySwitchSpec(title:$0,isOn:false,target:mock,action:#selector(Mock.pressed(_:)))}}
                            let value=row.id=="battery" ? "演示配件 82%":nil
                            let presentation=WS2PrivacyRowPresentation.make(row:row,value:value,hasValueSource:WS2PrivacyValues.hasValueSource(row.id),permissionGranted:row.permission == nil ? nil:false)
                            let v=PrivacyRowView(row:row,presentation:presentation,expanded:expanded,showDetails:expanded,switchSpec:spec,grantTarget:mock,grantAction:#selector(Mock.pressed(_:)),onToggle:{mock.actions += 1})
                            rowViews.append((row.id,v));return v
                        };let c=card(views);page.addArrangedSubview(c);c.widthAnchor.constraint(equalTo:page.widthAnchor).isActive=true
                    }
                }
                let window=NSWindow(contentRect:root.bounds,styleMask:[.borderless],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.alphaValue=0;window.appearance=NSAppearance(named:appearance);window.contentView=root;window.setFrameOrigin(NSPoint(x:-8000,y:-8000))
                root.layoutSubtreeIfNeeded();try await Task.sleep(nanoseconds:100_000_000);root.layoutSubtreeIfNeeded()
                let height=ceil(page.frame.height)+44;doc.setFrameSize(NSSize(width:696,height:height));doc.layoutSubtreeIfNeeded()
                for position in ["top","middle","bottom"] {
                    let maxY=max(0,height-scroll.contentView.bounds.height),y=position=="top" ? 0:position=="middle" ? maxY/2:maxY
                    scroll.contentView.scroll(to:NSPoint(x:0,y:y));scroll.reflectScrolledClipView(scroll.contentView);root.layoutSubtreeIfNeeded()
                    var records=[[String:Any]](),controls=[[String:Any]]()
                    for (id,v) in rowViews {
                        let r=v.convert(v.bounds,to:doc)
                        var fields=[[String:Any]]()
                        func visit(_ n:NSView){
                            let b=n.convert(n.bounds,to:v)
                            if let f=n as? NSTextField {fields.append(["role":f.identifier?.rawValue ?? "header","text":f.stringValue,"x":b.minX,"y":b.minY,"width":b.width,"height":b.height,"neededHeight":f.cell?.cellSize(forBounds:NSRect(x:0,y:0,width:f.bounds.width,height:10000)).height ?? 0])}
                            if let s=n as? NSSwitch {controls.append(["row":id,"kind":"switch","mockTarget":s.target === mock,"width":b.width,"height":b.height,"state":s.state.rawValue])}
                            if let button=n as? NSButton,button.title==WS2PrivacyCopy.needsGrant {controls.append(["row":id,"kind":"grant","mockTarget":button.target === mock,"width":b.width,"height":b.height])}
                            n.subviews.forEach(visit)
                        };visit(v)
                        records.append(["id":id,"x":r.minX,"y":r.minY,"width":r.width,"height":r.height,"fields":fields])
                    }
                    let name="\(appearance == .aqua ? "light":"dark")-\(expanded ? "expanded":"collapsed")-\(position)"
                    guard let bitmap=root.bitmapImageRepForCachingDisplay(in:root.bounds) else {throw Failure.check("bitmap")};root.cacheDisplay(in:root.bounds,to:bitmap)
                    guard let png=bitmap.representation(using:.png,properties:[:]) else {throw Failure.check("png")};try png.write(to:out.appendingPathComponent(name+".png"))
                    frames.append(["name":name,"expanded":expanded,"position":position,"groups":groupNames,"rows":records,"controls":controls,"contentHeight":height,"scrollY":scroll.contentView.bounds.minY,"maxScrollY":maxY,"pageWidth":page.frame.width,"actions":mock.actions,"visible":window.isVisible,"alpha":window.alphaValue,"active":NSApp.isActive])
                };window.contentView=nil;window.close()
            }}
            try JSONSerialization.data(withJSONObject:["frames":frames,"candidateOnly":true,"pageInstantiated":false,"sourcesRead":0,"settingsWrites":0,"globalInputEvents":0],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("frames.json"))
            print("PASS \(frames.count) static page composition fixtures")
    }
}
