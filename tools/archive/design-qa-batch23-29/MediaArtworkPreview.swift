import Cocoa
import ImageIO

/// Real decoder/palette/card, diagnostic pixels and routes only; no music/system commands.
enum MediaArtworkPreview {
 enum Failure:Error {case check(String)}
 static func artwork(_ kind:String,track:String,out:URL) throws -> NowPlayingArtworkImage {
  let side=128
  var pixels=[UInt8]();pixels.reserveCapacity(side*side*4)
  for _ in 0..<side {for x in 0..<side {
   let rgb:[UInt8]
   switch kind {
   case "cool":rgb=x<85 ? [25,115,180]:[155,65,195]
   case "neutral":rgb=[105,105,105]
   default:rgb=x<85 ? [180,70,25]:[230,165,55]
   }
   pixels.append(contentsOf:rgb+[255])
  }}
  guard let provider=CGDataProvider(data:Data(pixels) as CFData),let space=CGColorSpace(name:CGColorSpace.sRGB),
   let image=CGImage(width:side,height:side,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:side*4,space:space,bitmapInfo:NowPlayingArtworkDecoder.bitmapInfo,provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {throw Failure.check("source image")}
  let data=NSMutableData()
  guard let destination=CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil) else {throw Failure.check("png destination")}
  CGImageDestinationAddImage(destination,image,nil)
  guard CGImageDestinationFinalize(destination) else {throw Failure.check("png encode")}
  try (data as Data).write(to:out.appendingPathComponent("synthetic-\(kind)-cover.png"))
  guard let decoded=NowPlayingArtworkDecoder.decode(imageData:data as Data,trackKey:track) else {throw Failure.check("actual decoder")}
  return decoded
 }
 @MainActor static func render(_ out:URL) async throws {
  _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
  try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
  var frames:[[String:Any]]=[]
  for appearance in [NSAppearance.Name.aqua,.darkAqua] {
   let parent=appearance == .aqua ? "light":"dark"
   for state in ["warm","cool","neutral","paused","removed","routes-eight","no-artist"] {
    let panel=NotchPanel(notch:NSRect(x:-8000,y:866.5,width:185,height:33.5),virtual:false)
    panel.isReleasedWhenClosed=false;panel.alphaValue=0;panel.appearance=NSAppearance(named:appearance)
    let card=NowPlayingCard(geometry:.init(width:185,height:33.5,virtual:false))
    defer {card.revoke();panel.setInteraction(nil,animated:false);panel.close()}
    card.inputIsCurrent={true};card.clock={1000};card.onCommand={_ in};card.onSeek={_ in};card.onSelectRoute={_ in}
    card.onSizeChange={ [weak panel] opening in panel?.interactionSizeChanged(opening:opening)}
    var reads=0
    var routes:[AudioOutputRoute]=[]
    for index in 0..<8 {
     routes.append(.init(id:UInt32(index+1),uid:"synthetic-\(index)",name:"样件耳机 \(index+1) · "+String(repeating:"较长的设备名字",count:8),kind:index==0 ? .mac:.headphones,isCurrent:index==0))
    }
    card.loadRoutes={reads += 1;return routes}
    let content=NowPlayingCardContent(title:"样件封面",artist:state=="no-artist" ? "":"合成颜色资料",isPaused:state=="paused",bundleID:"design.synthetic",timeline:.init(duration:240,elapsed:65,stamp:1000,rate:state=="paused" ? 0:1),seekable:true)
    let kind=state=="cool" ? "cool":state=="neutral" ? "neutral":"warm"
    let image=try artwork(kind,track:parent+state,out:out)
    card.update(content,artwork:image);panel.setInteraction(card,animated:false)
    try await Task.sleep(nanoseconds:700_000_000)
    if state=="removed" {card.update(content,artwork:nil)}
    if state=="routes-eight" {card.openList()}
    try await Task.sleep(nanoseconds:500_000_000)
    guard let canvas=panel.contentView else {throw Failure.check("canvas")}
    canvas.layoutSubtreeIfNeeded()
    let outside=NSScreen.screens.allSatisfy{!$0.frame.intersects(panel.frame)}
    guard outside,!NSApp.isActive,panel.alphaValue==0 else {throw Failure.check("escaped")}
    func fields(_ view:NSView)->[NSTextField] {(view as? NSTextField).map{[$0]} ?? view.subviews.flatMap{fields($0)}}
    let artist=fields(card).first{$0.stringValue==content.artist}
    let actual=artist?.textColor?.usingColorSpace(.sRGB)
    let expected=state=="removed" ? ArtworkPalette.neutral:image.palette
    func capture(_ suffix:String) throws {
     let name=parent+"-"+suffix+".png"
     guard let rep=canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds) else {throw Failure.check("bitmap")}
     canvas.cacheDisplay(in:canvas.bounds,to:rep)
     guard let png=rep.representation(using:.png,properties:[:]) else {throw Failure.check("png")}
     try png.write(to:out.appendingPathComponent(name))
     frames.append(["image":name,"state":suffix,"synthetic":true,"width":canvas.bounds.width,"height":canvas.bounds.height,"contentWidth":card.bounds.width,"contentHeight":card.bounds.height,"panelAlpha":panel.alphaValue,"intersectsScreen":!outside,"activeApplication":NSApp.isActive,"routeReads":reads,"routeCount":card.routes.count,"listOpen":card.listOpen,"hasDecodedColor":image.palette.hasColor,"expectedTextRGB":[expected.text.r,expected.text.g,expected.text.b],"actualArtistRGB":actual.map{[$0.redComponent,$0.greenComponent,$0.blueComponent]} ?? [],"artist":content.artist,"artworkRemoved":state=="removed","decodedRGBABytes":image.rgba.count])
     try JSONSerialization.data(withJSONObject:frames,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("frames.json"))
    }
    try capture(state)
    if state=="routes-eight" {
     func scrolls(_ view:NSView)->[NSScrollView] {(view as? NSScrollView).map{[$0]} ?? view.subviews.flatMap{scrolls($0)}}
     guard let scroll=scrolls(card).first,let document=scroll.documentView else {throw Failure.check("route scroll")}
     let offset=max(0,document.bounds.height-scroll.contentView.bounds.height)
     scroll.contentView.scroll(to:NSPoint(x:0,y:offset));scroll.reflectScrolledClipView(scroll.contentView)
     guard offset>0,abs(scroll.contentView.bounds.minY-offset) < 0.1 else {throw Failure.check("scroll endpoint")}
     try await Task.sleep(nanoseconds:100_000_000)
     try capture("routes-last")
    }
   }
  }
  print("Rendered \(frames.count) production colored media/scroll endpoint frames; synthetic inputs only.")
 }
}
