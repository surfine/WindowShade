import Cocoa
import QuartzCore

#if !swift(>=6.0)
#error("NotchMotionPreview requires render-native-surfaces.sh --swift6")
#endif

@main enum NotchMotionPreview {
    enum Failure: Error { case check(String) }
    /// Point-in-time diagnostic; no thread-local state is carried across an await.
    @MainActor static func mainThreadNow() -> Bool { Thread.isMainThread }
    @MainActor static func field(_ object: Any, _ name: String) -> Any? {
        guard let value = Mirror(reflecting: object).children.first(where: { $0.label == name })?.value else { return nil }
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional ? mirror.children.first?.value : value
    }
    @MainActor static func box(_ r: NSRect) -> [String: CGFloat] { ["x":r.minX,"y":r.minY,"width":r.width,"height":r.height] }
    @MainActor static func content(id: UInt32?, count: Int = 2) throws -> NotchCanvasView.Content {
        var tiles = [NotchTile]()
        if let id {
            let item = NotchActivity(id: "qa-motion-\(id)", kind: .download, title: "演示下载", subtitle: "演示材料.zip", symbol: "arrow.down.circle", startedAt: 0, progress: .count(count,9), isPaused: false, sessionPhase: nil)
            guard let cell = NotchRow.ongoingCells(from: [item]).first else { throw Failure.check("pure Core projection") }
            let ongoing = NotchTile.Ongoing(activityID: cell.activityID, subtitle: cell.subtitle, symbol: cell.symbol,
                phase: cell.phase, isPaused: cell.isPaused, quantity: cell.quantity, quantityText: cell.quantityText,
                spoken: cell.spoken, action: cell.action, closesRow: cell.closesRow, accessory: cell.accessory,
                isStale: cell.isStale, isEnded: cell.isEnded)
            tiles.append(NotchTile(id: id, kind: .activity, snapshot: nil, icon: nil, title: cell.title, waiting: false, ongoing: ongoing))
        }
        return .init(tiles: tiles, dots: 0, dotsChanged: false, dotsY: 0, compact: nil, compactSlots: nil, alert: nil, hint: nil, notchHeight: 33.5)
    }
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        guard Thread.isMainThread, NSApp.delegate == nil else { fatalError("own main-thread entry only") }
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        Task { @MainActor in
            do { try await run(out); exit(0) }
            catch {
                try? String(describing: error).write(to: out.appendingPathComponent("failure.txt"), atomically: true, encoding: .utf8)
                print("FAILED motion probe: \(error)"); exit(1)
            }
        }
        // Only our entry pumps Cocoa; no product delegate, listener, controller, menu or input injection.
        NSApp.run()
    }
    @MainActor static func run(_ out: URL) async throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let oldOverride = Motion.reducedOverrideForProbe
        defer { Motion.reducedOverrideForProbe = oldOverride }
        var frames = [[String: Any]](), callbacks = [[String: Any]]()
        var counts = [String: Int]()
        var report: [String: Any] = ["swiftLanguageVersion":6,"productEntry":false,"realSources":0,"globalInputEvents":0,"windowActions":0,"mainThread":mainThreadNow()]
        func flush() throws {
            report["frames"] = frames; report["callbacks"] = callbacks; report["counts"] = counts
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: out.appendingPathComponent("frames.json"), options: .atomic)
        }
        for reduced in [false,true] {
            Motion.reducedOverrideForProbe = reduced
            let mode = reduced ? "reduced" : "regular"
            let bounds = NSRect(x:0,y:0,width:800,height:400)
            let canvas = NotchCanvasView(frame: bounds)
            let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.alphaValue = 0; window.contentView = canvas
            window.setFrame(NSRect(x:-8000,y:-8000,width:800,height:400),display:false)
            defer { window.close() }
            guard let island = field(canvas,"island") as? CALayer else { throw Failure.check("actual island layer") }
            let empty = try content(id:nil), first = try content(id:900), updated = try content(id:900,count:3), replacement = try content(id:901,count:4)
            let compact = NSRect(x:(800-185)/2,y:400-33.5,width:185,height:33.5)
            let expandedHeight = 33.5 + NotchIsland.peninsulaContentHeight(142)
            let expanded = NSRect(x:(800-305)/2,y:400-expandedHeight,width:305,height:expandedHeight)
            func token(_ shape: Motion.NotchShape) -> NotchCanvasView.Spring {
                let value = Motion.notchSpring(for:shape)
                return .init(response:value.response,bounce:value.bounce)
            }
            func morph(_ name: String, to rect: NSRect, content: NotchCanvasView.Content, spring: NotchCanvasView.Spring?) {
                let key = mode + "-" + name
                canvas.morph(to:rect,style:.init(cornerRadius:rect.height>34 ? 28:12,allCorners:false,fill:.black,border:0.5),content:content,spring:spring) {
                    counts[key,default:0] += 1
                    callbacks.append(["name":key,"mainThread":Thread.isMainThread,"time":CACurrentMediaTime()])
                    try? flush()
                }
            }
            func snapshot(_ stage: String) throws {
                guard !window.isVisible, !NSApp.isActive, Thread.isMainThread, NSApp.delegate == nil,
                      !NSScreen.screens.contains(where:{$0.frame.intersects(window.frame)}) else { throw Failure.check("own hidden main-thread host") }
                canvas.layoutSubtreeIfNeeded()
                let current = field(canvas,"current") as? NSView
                var ids = [UInt32](), identities = [String](), quantities = [[String:Int]]()
                func visit(_ view:NSView) {
                    if let tile = view as? NotchTileView, let model = field(tile,"tile") as? NotchTile {
                        ids.append(model.id); identities.append(String(describing:ObjectIdentifier(tile)))
                        if case let .count(k,n) = model.ongoing?.quantity ?? .unknown { quantities.append(["completed":k,"total":n]) }
                    }
                    view.subviews.forEach(visit)
                }
                if let current { visit(current) }
                let name = mode + "-" + stage
                guard let bitmap=canvas.bitmapImageRepForCachingDisplay(in:bounds) else {throw Failure.check("bitmap")}
                canvas.cacheDisplay(in:bounds,to:bitmap)
                guard let png=bitmap.representation(using:.png,properties:[:]) else {throw Failure.check("PNG")}
                try png.write(to:out.appendingPathComponent(name+".png"))
                let keys=island.animationKeys() ?? []
                var animations=[[String:Any]]()
                for key in keys { if let a=island.animation(forKey:key) { animations.append(["key":key,"duration":a.duration,"class":String(describing:type(of:a))]) } }
                frames.append(["name":name,"stage":stage,"reduced":reduced,"time":CACurrentMediaTime(),"model":box(island.frame),
                    "presentation":island.presentation().map{box($0.frame)} as Any? ?? NSNull(),"animations":animations,
                    "pendingExit":field(canvas,"contentExitPending") as? Bool ?? false,"tileIDs":ids,"tileIdentities":identities,"tileQuantities":quantities,
                    "currentIdentity":current.map{String(describing:ObjectIdentifier($0))} as Any? ?? NSNull(),
                    "active":NSApp.isActive,"visible":window.isVisible,"alpha":window.alphaValue,"mainThread":Thread.isMainThread,
                    "cacheOnly":true])
                try flush()
            }
            func wait(_ key: String) async throws {
                let animationTime = (island.animationKeys() ?? []).compactMap { island.animation(forKey:$0)?.duration }.max() ?? 0
                let deadline=ProcessInfo.processInfo.systemUptime+max(4,animationTime+1)
                while counts[mode+"-"+key,default:0]==0, ProcessInfo.processInfo.systemUptime<deadline {try await Task.sleep(nanoseconds:10_000_000)}
                guard counts[mode+"-"+key,default:0]==1 else {throw Failure.check("completion \(mode)-\(key)")}
                try await Task.sleep(nanoseconds:180_000_000)
            }
            morph("initial",to:compact,content:empty,spring:nil); try await wait("initial"); try snapshot("initial")
            morph("open",to:expanded,content:first,spring:token(.expanded)); try snapshot("open-start"); try await wait("open"); canvas.settle(); try snapshot("open-settled")
            // refreshOngoingRows routes quantity-only changes through this actual
            // Canvas endpoint; Content.same intentionally does not recreate tiles.
            for tile in updated.tiles {
                if let ongoing = tile.ongoing {
                    canvas.updateOngoingQuantity(id: tile.id, quantity: ongoing.quantity, text: ongoing.quantityText)
                }
            }
            morph("same-id",to:expanded,content:updated,spring:token(.expanded)); try await wait("same-id"); canvas.settle(); try snapshot("same-id")
            morph("replace-id",to:expanded,content:replacement,spring:token(.expanded)); try await wait("replace-id"); canvas.settle(); try snapshot("replace-id")
            morph("close-interrupted",to:compact,content:empty,spring:token(.compact)); try snapshot("close-before-interrupt")
            try await Task.sleep(nanoseconds:10_000_000)
            morph("reopen",to:expanded,content:replacement,spring:token(.expanded)); try await wait("reopen"); canvas.settle()
            try await Task.sleep(nanoseconds:200_000_000); try snapshot("reopened")
            morph("close-final",to:compact,content:empty,spring:token(.compact)); try await wait("close-final"); canvas.settle(); try snapshot("closed")
            window.close()
        }
        Motion.reducedOverrideForProbe = oldOverride
        report["overrideRestoredTo"] = Motion.reducedOverrideForProbe as Any? ?? NSNull()
        report["overrideRestored"] = Motion.reducedOverrideForProbe == oldOverride
        report["status"] = "completed_callbacks_static_cache_only"
        try flush(); print("PASS \(frames.count) actual Swift6 motion/cancellation snapshots; callbacks main-thread; visual compositor untested")
    }
}
