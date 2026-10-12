import Cocoa
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
let w=NSWindow(contentRect:NSRect(x:-8000,y:-8000,width:720,height:594),styleMask:[.titled,.closable],backing:.buffered,defer:false)
w.isReleasedWhenClosed=false;w.alphaValue=0
print("initial",NSStringFromRect(w.frame),"visible",w.isVisible,"active",NSApp.isActive,"outside",NSScreen.screens.allSatisfy{!$0.frame.intersects(w.frame)})
w.setFrame(NSRect(x:-8000,y:-8000,width:720,height:622),display:false)
print("explicit",NSStringFromRect(w.frame),"visible",w.isVisible,"active",NSApp.isActive,"outside",NSScreen.screens.allSatisfy{!$0.frame.intersects(w.frame)})
w.close()
