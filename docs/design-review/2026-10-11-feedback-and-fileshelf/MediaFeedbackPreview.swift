import Cocoa

/// Actual production media card with synthetic data and local callback recordings only.
enum MediaFeedbackPreview {
    enum Failure:Error { case check(String) }
    @MainActor static func main() async {
        let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        do { try await render(out) } catch {
            let failure:[String:Any]=["passed":false,"complete":false,"error":String(describing:error)]
            try? JSONSerialization.data(withJSONObject:failure,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("failure.json"))
            print("FAILED synthetic media preview: \(error)")
            exit(1)
        }
    }
    @MainActor static func render(_ out:URL) async throws {
        _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        var frames:[[String:Any]]=[],checks:[[String:Any]]=[]
        for appearance in [NSAppearance.Name.aqua,.darkAqua] {
            let parent=appearance == .aqua ? "light":"dark"
            for state in ["playing","paused","live","long-title","empty-routes","routes"] {
                let panel=NotchPanel(notch:NSRect(x:-8000,y:866.5,width:185,height:33.5),virtual:false)
                panel.isReleasedWhenClosed=false;panel.alphaValue=0;panel.appearance=NSAppearance(named:appearance)
                let card=NowPlayingCard(geometry:.init(width:185,height:33.5,virtual:false))
                defer { card.revoke();panel.setInteraction(nil,animated:false);panel.close() }
                var current=true,commands=0,routeReads=0,devicesAvailable=false
                card.inputIsCurrent={current};card.clock={1000}
                card.onCommand={_ in commands += 1};card.onSeek={_ in};card.onSelectRoute={_ in}
                card.onSizeChange={ [weak panel] opening in panel?.interactionSizeChanged(opening:opening) }
                var syntheticRoutes:[AudioOutputRoute]=[]
                for index in 0..<5 {
                    let kind:AudioOutputKind=index==0 ? .mac:.headphones
                    let name=index==0 ? "样件 Mac":"样件耳机 \(index)"
                    let route=AudioOutputRoute(id:UInt32(index+1),uid:"synthetic-\(index)",name:name,kind:kind,isCurrent:index==0)
                    syntheticRoutes.append(route)
                }
                card.loadRoutes={
                    routeReads += 1
                    return state == "routes" || devicesAvailable ? syntheticRoutes:[]
                }
                let live=state == "live",paused=state == "paused"
                let title=state == "long-title" ? String(repeating:"很长的样件歌名 · ",count:18):"样件音乐"
                card.update(.init(title:title,artist:"合成资料 · 未连接播放器",isPaused:paused,bundleID:"design.synthetic",timeline:.init(duration:live ? nil:240,elapsed:65,stamp:1000,rate:paused ? 0:1),seekable:!live),artwork:nil)
                panel.setInteraction(card,animated:false)
                if state == "empty-routes" || state == "routes" { card.openList() }
                // Wait for actual content fade and host resize endpoints; no animation quality claim.
                try await Task.sleep(nanoseconds:900_000_000)
                guard let canvas=panel.contentView else { throw Failure.check("canvas") }
                canvas.layoutSubtreeIfNeeded()
                let outside=NSScreen.screens.allSatisfy{!$0.frame.intersects(panel.frame)}
                guard outside,!NSApp.isActive else { throw Failure.check("fixture escaped bounds") }
                let isList=state == "routes" || state == "empty-routes"
                guard card.listOpen==isList,card.routes.count==(state == "routes" ? 5:0) else { throw Failure.check("synthetic routes") }
                let size=card.interactionSize
                let expectedWindow=NSRect(x:-7907.5-size.width/2,y:900-33.5-size.height,width:size.width,height:33.5+size.height).integral
                let deadline=ProcessInfo.processInfo.systemUptime+3
                while (abs(canvas.bounds.width-expectedWindow.width)>0.1 || abs(canvas.bounds.height-expectedWindow.height)>0.1),ProcessInfo.processInfo.systemUptime<deadline {
                    try await Task.sleep(nanoseconds:10_000_000)
                    canvas.layoutSubtreeIfNeeded()
                }

                func emptyLabel(_ node:NSView)->NSTextField? {
                    if let field=node as? NSTextField,field.stringValue=="暂未找到设备" {return field}
                    return node.subviews.compactMap{emptyLabel($0)}.first
                }
                guard let empty=emptyLabel(card) else {throw Failure.check("empty label missing")}
                let labelRect=empty.convert(empty.bounds,to:card)
                let image="\(parent)-\(state).png"
                guard let rep=canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds) else { throw Failure.check("bitmap") }
                canvas.cacheDisplay(in:canvas.bounds,to:rep)
                guard let png=rep.representation(using:.png,properties:[:]) else { throw Failure.check("png") }
                try png.write(to:out.appendingPathComponent(image))
                frames.append(["image":image,"state":state,"parentAppearance":appearance.rawValue,"synthetic":true,"width":canvas.bounds.width,"height":canvas.bounds.height,"contentWidth":card.bounds.width,"contentHeight":card.bounds.height,"requestedWidth":size.width,"requestedHeight":size.height,"panelAlpha":panel.alphaValue,"intersectsScreen":!outside,"activeApplication":NSApp.isActive,"title":title,"listOpen":card.listOpen,"routeCount":card.routes.count,"routeReads":routeReads,"emptyText":empty.stringValue,"emptyVisible":!empty.isHiddenOrHasHiddenAncestor,"emptyBounds":[labelRect.minX,labelRect.minY,labelRect.width,labelRect.height]])
                try JSONSerialization.data(withJSONObject:frames,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("frames.json"))
                if state == "empty-routes" {
                    guard !empty.isHiddenOrHasHiddenAncestor,card.bounds.contains(labelRect),routeReads==1 else {throw Failure.check("empty feedback")}
                    card.closeList()
                    try await Task.sleep(nanoseconds:400_000_000)
                    guard !card.listOpen,empty.isHiddenOrHasHiddenAncestor else {throw Failure.check("return from empty")}
                    devicesAvailable=true;card.openList()
                    try await Task.sleep(nanoseconds:400_000_000)
                    guard card.listOpen,card.routes.count==5,empty.isHiddenOrHasHiddenAncestor,routeReads==2 else {throw Failure.check("retry routes")}
                    card.closeList();current=false;card.openList()
                    guard !card.listOpen,routeReads==2 else {throw Failure.check("stale query")}
                    card.revoke();card.openList()
                    guard !card.listOpen,routeReads==2,card.pendingTimerCount==0 else {throw Failure.check("revoked query")}
                    checks.append(["parent":parent,"kind":"empty-feedback","returned":true,"retryDeviceCount":5,"totalRouteReads":routeReads,"pendingTimersAfterRevoke":card.pendingTimerCount,"passed":true])
                }
                if state == "playing" {
                    func find(_ node:NSView)->NSButton? {
                        if let b=node as? NSButton,b.action==NSSelectorFromString("playAction") {return b}
                        return node.subviews.compactMap{find($0)}.first
                    }
                    guard let button=find(card),let action=button.action else {throw Failure.check("play control")}
                    let delivered=NSApp.sendAction(action,to:button.target,from:button)
                    guard delivered,commands==1 else {throw Failure.check("local play callback")}
                    current=false;_=NSApp.sendAction(action,to:button.target,from:button)
                    guard commands==1 else {throw Failure.check("stale command")}
                    card.revoke();_=NSApp.sendAction(action,to:button.target,from:button)
                    guard commands==1,card.pendingTimerCount==0 else {throw Failure.check("revoke/timers")}
                    checks.append(["parent":parent,"kind":"play-guard","localPlayCallbacks":commands,"staleAndRevokedCallbacks":commands-1,"pendingTimersAfterRevoke":card.pendingTimerCount,"passed":true])
                }
            }
        }
        for (name,value) in [("frames.json",frames),("checks.json",checks)] {
            try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent(name))
        }
        print("Rendered \(frames.count) synthetic media frames; \(checks.count) real control guard checks; no media/system commands.")
    }
}
