import Cocoa
import QuartzCore
@main enum SpringVelocityUnitsPreview {
    @MainActor static func mainThreadNow()->Bool {Thread.isMainThread}
    @MainActor static func main(){
        _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {try await run(URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true));exit(0)}catch{print(error);exit(1)}
        };NSApp.run()
    }
    @MainActor static func run(_ out:URL) async throws {
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let host=NSView(frame:NSRect(x:0,y:0,width:600,height:200));host.wantsLayer=true
        let w=NSWindow(contentRect:host.bounds,styleMask:[.borderless],backing:.buffered,defer:false);w.isReleasedWhenClosed=false;w.contentView=host;w.alphaValue=0;w.setFrameOrigin(NSPoint(x:-8000,y:-8000));defer{w.close()}
        var layers=[(Double,Double,CALayer)]()
        CATransaction.begin();CATransaction.setDisableActions(true)
        for distance in [100.0,200.0] {for speed in [-1.0,0.0,1.0] {let l=CALayer();l.bounds=CGRect(x:0,y:0,width:1,height:1);l.position=CGPoint(x:distance,y:0);host.layer!.addSublayer(l);layers.append((distance,speed,l))}}
        CATransaction.commit();CATransaction.flush()
        let start=CACurrentMediaTime()
        CATransaction.begin();CATransaction.setDisableActions(true)
        for (distance,speed,l) in layers {let a=CASpringAnimation(keyPath:"position.x");a.mass=1;a.stiffness=100;a.damping=10;a.initialVelocity=speed;a.fromValue = -distance;a.toValue=0;a.isAdditive=true;a.beginTime=l.convertTime(start,from:nil);a.duration=1;l.add(a,forKey:"probe")}
        CATransaction.commit();CATransaction.flush()
        var records=[[String:Any]]()
        for _ in 0..<30 {
            let now=CACurrentMediaTime()
            for (d,v,l) in layers {records.append(["time":now-start,"distance":d,"initialVelocity":v,"presentationX":l.presentation()?.position.x as Any? ?? NSNull(),"modelX":l.position.x])}
            try await Task.sleep(nanoseconds:10_000_000)
        }
        try JSONSerialization.data(withJSONObject:["records":records,"visible":w.isVisible,"alpha":w.alphaValue,"active":NSApp.isActive,"mainThread":mainThreadNow(),"delegateNil":NSApp.delegate==nil,"productEntry":false,"globalInputEvents":0],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("samples.json"))
        print("PASS own Cocoa spring API sampling; not compositor acceptance")
    }
}
