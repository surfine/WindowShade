import Cocoa
_ = NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
let view=NSView(frame:NSRect(x:0,y:0,width:40,height:40));view.wantsLayer=true
let front=CALayer();front.frame=view.bounds;front.backgroundColor=NSColor.red.cgColor;front.zPosition=7
let back=CALayer();back.frame=view.bounds;back.backgroundColor=NSColor.blue.cgColor;back.zPosition=0
view.layer!.addSublayer(front);view.layer!.addSublayer(back)
let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
view.cacheDisplay(in:view.bounds,to:rep)
let c=rep.colorAt(x:20,y:20)!.usingColorSpace(.sRGB)!
print("cacheDisplay redZ7-first/blueZ0-last:",c.redComponent,c.greenComponent,c.blueComponent,c.alphaComponent)
let context=CGContext(data:nil,width:40,height:40,bitsPerComponent:8,bytesPerRow:160,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
view.layer!.render(in:context)
let pixel=context.data!.assumingMemoryBound(to:UInt8.self)+(20*40+20)*4
print("layer.render same tree:",pixel[0],pixel[1],pixel[2],pixel[3])
