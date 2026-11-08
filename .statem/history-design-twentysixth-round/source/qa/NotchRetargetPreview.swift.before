import Cocoa
import QuartzCore
#if !swift(>=6.0)
#error("Swift6 required")
#endif
/// Own hidden layer probe. Animation configuration evidence, not compositor/FPS acceptance.
@main enum NotchRetargetPreview {
    enum Failure:Error {case check(String)}
    @MainActor static func field(_ object:Any,_ name:String)->Any? {Mirror(reflecting:object).children.first{$0.label==name}?.value}
    static func box(_ r:CGRect)->[String:CGFloat] {["x":r.minX,"y":r.minY,"width":r.width,"height":r.height]}
    @MainActor static func main(){
        _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {try await run(URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true));exit(0)}
            catch {print("FAIL \(error)");exit(1)}
        };NSApp.run()
    }
    @MainActor static func run(_ out:URL) async throws {
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let saved=Motion.reducedOverrideForProbe;defer{Motion.reducedOverrideForProbe=saved}
        var records=[[String:Any]]()
        for reduced in [false,true] {
            Motion.reducedOverrideForProbe=reduced
            let canvas=NotchCanvasView(frame:NSRect(x:0,y:0,width:800,height:400))
            let w=NSWindow(contentRect:canvas.bounds,styleMask:[.borderless],backing:.buffered,defer:false);w.isReleasedWhenClosed=false;w.alphaValue=0;w.contentView=canvas;w.setFrameOrigin(NSPoint(x:-8000,y:-8000))
            guard let island=field(canvas,"island") as? CALayer else {throw Failure.check("island")}
            let content=NotchCanvasView.Content(tiles:[],dots:0,dotsChanged:false,dotsY:0,compact:nil,compactSlots:nil,alert:nil,hint:nil,notchHeight:33.5)
            let compact=NSRect(x:307.5,y:366.5,width:185,height:33.5),expanded=NSRect(x:247.5,y:180,width:305,height:220),wide=NSRect(x:187.5,y:180,width:425,height:220)
            var callbacks=0
            func record(_ name:String){
                var animations=[[String:Any]]()
                for key in island.animationKeys() ?? [] {if let a=island.animation(forKey:key) as? CASpringAnimation {
                    var value:[String:Any]=["key":key,"velocity":a.initialVelocity,"mass":a.mass,"stiffness":a.stiffness,"damping":a.damping,"duration":a.duration,"beginTime":a.beginTime,"additive":a.isAdditive]
                    if let x=a.fromValue as? NSValue {
                        if a.keyPath=="position" {value["from"]=[x.pointValue.x,x.pointValue.y]}
                        if a.keyPath=="bounds.size" {value["from"]=[x.sizeValue.width,x.sizeValue.height]}
                    }else if let x=a.fromValue as? NSNumber {value["from"]=x.doubleValue}
                    animations.append(value)
                }}
                records.append(["stage":name,"reduced":reduced,"time":CACurrentMediaTime(),"model":box(island.frame),"presentation":island.presentation().map{box($0.frame)} as Any? ?? NSNull(),"animations":animations,"callbacks":callbacks,"visible":w.isVisible,"alpha":w.alphaValue,"active":NSApp.isActive,"delegateNil":NSApp.delegate==nil,"mainThread":Thread.isMainThread])
            }
            func morph(_ name:String,_ target:NSRect,_ animated:Bool=true){
                record(name+"-before")
                canvas.morph(to:target,style:.init(cornerRadius:target.height>34 ? 28:12,allCorners:false,fill:.black,border:0.5),content:content,spring:animated ? .init(response:0.4,bounce:0.08):nil){callbacks += 1}
                record(name+"-after")
            }
            morph("initial",compact,false);try await Task.sleep(nanoseconds:30_000_000)
            morph("open",expanded);try await Task.sleep(nanoseconds:90_000_000);record("open-sample")
            morph("reverse",compact);try await Task.sleep(nanoseconds:50_000_000);record("reverse-sample")
            morph("reopen",expanded);try await Task.sleep(nanoseconds:80_000_000)
            morph("width-only",wide);try await Task.sleep(nanoseconds:50_000_000)
            morph("width-reverse",expanded);try await Task.sleep(nanoseconds:700_000_000);record("settled")
            w.contentView=nil;w.close()
        }
        Motion.reducedOverrideForProbe=saved
        let result:[String:Any]=["records":records,"cacheOnly":true,"compositorAccepted":false,"realSources":0,"globalInputEvents":0,"productEntry":false,"overrideRestored":Motion.reducedOverrideForProbe == saved]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("retarget.json"))
        print("PASS \(records.count) actual retarget configuration records; compositor not accepted")
    }
}
