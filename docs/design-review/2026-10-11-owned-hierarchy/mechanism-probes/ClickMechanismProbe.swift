import Cocoa
@MainActor final class Receiver:NSObject {
    @objc func toggle(_ sender:Any?) {
        print("action active=\(NSApp.isActive)");fflush(stdout)
        if let window=(sender as? NSButton)?.window {
            var rect=window.frame;rect.origin.y-=126;rect.size.height+=126;window.setFrame(rect,display:false)
            print("resized frame=\(window.frame)");fflush(stdout)
        }
    }
}
@main enum Probe {
    @MainActor static func main() async {
        _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        let panel=NSPanel(contentRect:NSRect(x:-8000,y:600,width:620,height:309),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed=false;panel.alphaValue=0
        panel.level=NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopWindow))-1)
        let keeper=NSPanel(contentRect:NSRect(x:-9000,y:500,width:1,height:1),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        keeper.alphaValue=0;keeper.isReleasedWhenClosed=false;keeper.orderFrontRegardless()
        let target=Receiver();let button=NSButton(title:"查看诊断",target:target,action:#selector(Receiver.toggle(_:)))
        button.frame=NSRect(x:14,y:14,width:100,height:24);panel.contentView?.addSubview(button);panel.orderFrontRegardless()
        print("before active=\(NSApp.isActive) frame=\(panel.frame)");fflush(stdout)
        _ = NSApp.sendAction(button.action!,to:button.target,from:button)
        print("after active=\(NSApp.isActive) frame=\(panel.frame)");fflush(stdout)
        panel.close()
        print("closed");fflush(stdout)
        try? await Task.sleep(nanoseconds:100_000_000)
        print("after await");fflush(stdout);keeper.close()
    }
}
