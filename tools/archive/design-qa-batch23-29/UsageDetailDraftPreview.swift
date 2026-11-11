import Cocoa

#if !swift(>=6.0)
#error("UsageDetailDraftPreview requires --swift6")
#endif

@MainActor private final class UsageModelLabel: NSTextView {
    let fullText: String
    init(_ text: String) {
        fullText=text
        let container=NSTextContainer(containerSize:NSSize(width:484,height:32))
        container.lineFragmentPadding=0;container.maximumNumberOfLines=2;container.lineBreakMode = .byTruncatingTail
        let manager=NSLayoutManager();manager.addTextContainer(container)
        let storage=NSTextStorage(string:text,attributes:[.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.white.withAlphaComponent(0.92)])
        storage.addLayoutManager(manager)
        super.init(frame:.zero,textContainer:container)
        isEditable=false;isSelectable=false;drawsBackground=false;textContainerInset = .zero
        toolTip=text;setAccessibilityLabel(text)
        manager.ensureLayout(for:container)
    }
    required init?(coder:NSCoder) {nil}
    override var intrinsicContentSize:NSSize {
        NSSize(width:484,height:ceil(layoutManager!.usedRect(for:textContainer!).height))
    }
    var truncated:Bool {
        let manager=layoutManager!;let range=manager.glyphRange(for:textContainer!)
        guard range.length>0 else {return false}
        return manager.truncatedGlyphRange(inLineFragmentForGlyphAt:NSMaxRange(range)-1).location != NSNotFound
    }
}

/// Design-only candidate. Its inputs are explicit synthetic facts, never a source/controller.
@MainActor private final class UsageDetailDraftView: NSView, WS2LeaseContent {
    var onCancel: (() -> Void)?
    var inputIsCurrent: () -> Bool = { false }
    var interactionSize: NSSize { NSSize(width:520,height:ceil(body.fittingSize.height)+36) }
    private let body=NSStackView()
    private(set) var fields=[String:NSView]()
    private(set) var windows=[[String:Any]]()
    let modelName: String
    let shared: Bool
    init(reading: UsageReading?, contextUsed: Double?, model: String, shared: Bool, now: Double, calendar: Calendar) {
        self.modelName=model;self.shared=shared
        super.init(frame:NSRect(x:0,y:0,width:520,height:480))
        body.orientation = .vertical;body.alignment = .leading;body.spacing=12
        body.translatesAutoresizingMaskIntoConstraints=false;addSubview(body)
        NSLayoutConstraint.activate([body.leadingAnchor.constraint(equalTo:leadingAnchor,constant:18),body.topAnchor.constraint(equalTo:topAnchor,constant:18),body.widthAnchor.constraint(equalToConstant:484)])
        func field(_ key:String,_ text:String,_ size:CGFloat=13,_ weight:NSFont.Weight = .regular,_ secondary:Bool=false,_ wrap:Bool=false) -> NSTextField {
            let view=wrap ? NSTextField(wrappingLabelWithString:text) : NSTextField(labelWithString:text)
            view.font = .systemFont(ofSize:size,weight:weight)
            view.textColor = NSColor.white.withAlphaComponent(secondary ? 0.6 : 0.92)
            view.toolTip=text;view.identifier=NSUserInterfaceItemIdentifier(key)
            if wrap {view.maximumNumberOfLines=2;view.lineBreakMode = .byWordWrapping;view.preferredMaxLayoutWidth=484}
            else {view.lineBreakMode = .byTruncatingTail}
            view.setContentCompressionResistancePriority(.required,for:.vertical)
            fields[key]=view;return view
        }
        func add(_ view:NSView) {body.addArrangedSubview(view);view.widthAnchor.constraint(equalToConstant:484).isActive=true}
        add(field("title","用量",18,.semibold))
        add(field("source",shared ? "会话信息已隐藏" : "Codex · 演示账户",12,.regular,true))
        add(field("account-heading","账户额度",12,.semibold,true))
        let shown = shared ? [] : reading?.windows ?? []
        if shown.isEmpty {add(field("account-empty",shared ? "用量已隐藏" : "暂未读到用量",13,.regular,true))}
        for (index,window) in shown.enumerated() {
            guard let usage=UsageReading(windows:[window]).sessionUsage(now:now,calendar:calendar) else {continue}
            let name: String
            switch window.windowMinutes {
            case 300?: name="五小时额度"
            case 10080?: name="七天额度"
            case let minutes?: name="账户额度 · \(minutes) 分钟"
            case nil: name="账户额度"
            }
            let text=NSStackView();text.orientation = .vertical;text.alignment = .leading;text.spacing=3
            text.addArrangedSubview(field("window-\(index)-name",name,13,.medium))
            if let recovery=usage.recoveryDetail {text.addArrangedSubview(field("window-\(index)-recovery",recovery,12,.regular,true))}
            let amount=field("window-\(index)-amount","剩 \(usage.leftPercent)%",22,.semibold)
            amount.font = .monospacedDigitSystemFont(ofSize:22,weight:.semibold)
            if usage.isLow {amount.textColor = .systemOrange}
            amount.setContentCompressionResistancePriority(.required,for:.horizontal)
            amount.setContentHuggingPriority(.required,for:.horizontal)
            let spacer=NSView();spacer.setContentHuggingPriority(.init(1),for:.horizontal)
            let row=NSStackView(views:[text,spacer,amount]);row.orientation = .horizontal;row.alignment = .centerY;row.spacing=16
            add(row)
            windows.append(["name":name,"leftPercent":usage.leftPercent,"recovery":usage.recoveryDetail as Any? ?? NSNull(),"windowMinutes":window.windowMinutes as Any? ?? NSNull()])
        }
        let line=NSView();line.wantsLayer=true;line.layer?.backgroundColor=NSColor.white.withAlphaComponent(0.14).cgColor
        line.heightAnchor.constraint(equalToConstant:0.5).isActive=true;add(line)
        add(field("session-heading","当前会话",12,.semibold,true))
        add(field("project",shared ? "编程会话" : "设计工作间",15,.medium))
        if !shared {
            let label=UsageModelLabel(model);fields["model"]=label;add(label)
            add(field("effort","思考：深入",12,.regular,true))
            // This is a synthetic context value for the candidate, not a newly qualified wire channel.
            let snapshot=WS2SilentUsageSnapshot(selectedContext:contextUsed.map(WS2SilentUsageValue.provided) ?? .notProvided)
            let number=WS2SilentUsageRead.writtenNumber(snapshot.value(for:.selectedContext))
            let context=number.map {"上下文占用 \(Int($0))%"} ?? "暂未读到上下文"
            add(field("context",context,12,.regular,true))
        }
    }
    required init?(coder:NSCoder) {nil}
    func revoke() {inputIsCurrent={false};body.removeFromSuperview();fields.removeAll()}
}

@main enum UsageDetailDraftPreview {
    enum Failure:Error {case check(String)}
    @MainActor static func mainThreadNow()->Bool {Thread.isMainThread}
    static func box(_ rect:NSRect)->[String:CGFloat] {["x":rect.minX,"y":rect.minY,"width":rect.width,"height":rect.height]}
    @MainActor static func main() async {
        _ = NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        var ownWindows=[NSWindow]()
        defer {ownWindows.forEach {$0.close()}}
        do {
            try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
            let now=1_800_000_000.0
            var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
            let normal=#"{"rateLimits":{"primary":{"usedPercent":5,"windowDurationMins":300,"resetsAt":1800003600},"secondary":{"usedPercent":93,"windowDurationMins":10080,"resetsAt":1800400000}}}"#
            let expired=#"{"rateLimits":{"primary":{"usedPercent":95,"windowDurationMins":300,"resetsAt":1799999995},"secondary":{"usedPercent":60,"windowDurationMins":10080,"resetsAt":1800400000}}}"#
            let unknownWindow=#"{"rateLimits":{"primary":{"usedPercent":12}}}"#
            let zero=#"{"rateLimits":{"primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":1800003600}}}"#
            var frames=[[String:Any]]()
            for parent in [NSAppearance.Name.aqua,.darkAqua] {
                for sample in ["normal","unknown","context-only","expired","long-model","unknown-window","zero","shared"] {
                    let raw=sample == "expired" ? expired : sample == "unknown-window" ? unknownWindow : sample == "zero" ? zero : normal
                    let wire=try JSONDecoder().decode(WireJSON.self,from:Data(raw.utf8))
                    let reading=["unknown","context-only"].contains(sample) ? nil : UsageReading.parse(wire)
                    let model=sample == "long-model" ? "演示模型 — "+String(repeating:"跨领域推理与图像分析",count:12) : "演示模型"
                    let context:Double?=sample == "unknown" ? nil : 25
                    let view=UsageDetailDraftView(reading:reading,contextUsed:context,model:model,shared:sample == "shared",now:now,calendar:calendar)
                    let size=view.interactionSize;guard size.height<=480,size.height>=68 else {throw Failure.check("candidate height")}
                    let bounds=NSRect(x:0,y:0,width:520,height:size.height+33.5)
                    let canvas=NotchCanvasView(frame:bounds)
                    let window=NSWindow(contentRect:bounds,styleMask:[.borderless],backing:.buffered,defer:false)
                    ownWindows.append(window);window.isReleasedWhenClosed=false;window.alphaValue=0
                    window.appearance=NSAppearance(named:parent);window.contentView=canvas
                    window.setFrame(NSRect(x:-8000,y:-8000,width:bounds.width,height:bounds.height),display:false)
                    canvas.setAuthentication(view)
                    var completions=0
                    let content=NotchCanvasView.Content(tiles:[],dots:0,dotsChanged:false,dotsY:0,compact:nil,compactSlots:nil,alert:nil,hint:nil,notchHeight:33.5)
                    canvas.morph(to:bounds,style:.init(cornerRadius:24,allCorners:false,fill:.black,border:0.5),content:content,spring:nil){completions += 1}
                    canvas.placeAuthentication(in:NSRect(origin:.zero,size:size));canvas.layoutSubtreeIfNeeded()
                    try await Task.sleep(nanoseconds:150_000_000);canvas.layoutSubtreeIfNeeded()
                    var fields=[[String:Any]]()
                    for (key,label) in view.fields.sorted(by:{$0.key<$1.key}) {
                        var item:[String:Any]=["id":key,"tooltip":label.toolTip as Any? ?? NSNull(),"frame":box(label.convert(label.bounds,to:view)),"dark":label.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua]
                        if let text=label as? NSTextField {
                            item["text"]=text.stringValue;item["font"]=text.font?.pointSize ?? 0
                            item["maximumNumberOfLines"]=text.maximumNumberOfLines;item["wraps"]=(text.cell as? NSTextFieldCell)?.wraps ?? false
                        } else if let text=label as? UsageModelLabel {
                            item["text"]=text.fullText;item["font"]=13;item["maximumNumberOfLines"]=text.textContainer!.maximumNumberOfLines
                            item["renderer"]="TextKit";item["truncated"]=text.truncated
                            item["editable"]=text.isEditable;item["selectable"]=text.isSelectable
                        }
                        fields.append(item)
                    }
                    let name="\(parent == .aqua ? "light" : "dark")-\(sample)"
                    guard let bitmap=canvas.bitmapImageRepForCachingDisplay(in:bounds) else {throw Failure.check("bitmap")}
                    canvas.cacheDisplay(in:bounds,to:bitmap)
                    guard let png=bitmap.representation(using:.png,properties:[:]) else {throw Failure.check("png")}
                    try png.write(to:out.appendingPathComponent(name+".png"))
                    frames.append(["name":name,"sample":sample,"candidateOnly":true,"windows":view.windows,"fields":fields,"pageSize":["width":size.width,"height":size.height],"canvasSize":["width":bounds.width,"height":bounds.height],"visible":window.isVisible,"active":NSApp.isActive,"alpha":window.alphaValue,"completions":completions,"mainThread":mainThreadNow()])
                    view.revoke();canvas.setAuthentication(nil);window.close()
                }
            }
            let report:[String:Any]=["frames":frames,"candidateOnly":true,"productionIntegration":false,"sourceControllers":0,"actions":0,"networkReads":0,"globalInputEvents":0,"contextSourceQualified":false]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("frames.json"))
            print("PASS \(frames.count) own native usage detail candidates; no production integration/source/actions")
        } catch {fputs("FAIL \(error)\n",stderr);exit(1)}
    }
}
