import Cocoa
import QuartzCore

#if !swift(>=6.0)
#error("UsageQuantityPreview requires --swift6")
#endif

/// Production M11 canvas/content, without any source/controller/window operation.
@main enum UsageQuantityPreview {
    enum Failure: Error { case check(String) }
    static func rect(_ r: NSRect) -> [String: Double] { ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height] }
    @MainActor static func main() async {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            var frames: [[String: Any]] = []
            for parent in [NSAppearance.Name.aqua, .darkAqua] {
                for sample in ["normal", "low", "low-updated", "zero", "unknown", "expired", "weekly", "long-model", "waiting", "shared"] {
                    let windows = 0, ongoing = 1
                    let now = 1_800_000_000.0
                    let used = sample == "low-updated" ? 96 : (sample == "zero" ? 100 : (["low", "expired", "waiting"].contains(sample) ? 95 : 76))
                    let reset = sample == "expired" ? Int(now)-5 : Int(now)+3600
                    let payload: String = sample == "weekly"
                        ? #"{"rateLimits":{"primary":{"usedPercent":5,"windowDurationMins":300,"resetsAt":1800003600},"secondary":{"usedPercent":93,"windowDurationMins":10080,"resetsAt":1800400000}}}"#
                        : #"{"rateLimits":{"primary":{"usedPercent":\#(used),"windowDurationMins":300,"resetsAt":\#(reset)}}}"#
                    let json = try JSONDecoder().decode(WireJSON.self,from:Data(payload.utf8))
                    let reading = sample == "unknown" ? nil : UsageReading.parse(json)
                    var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(secondsFromGMT:0)!
                    let model = sample == "long-model" ? "演示模型-" + String(repeating:"跨领域思考与图像分析",count:7) : "演示模型"
                    let usage = reading?.sessionUsage(now:now,model:model,effort:"深入",calendar:calendar)
                    var sessions = CodingSessionActivities()
                    sessions.apply(.init(id:"qa-usage",project:"设计工作间",cwd:"/qa/usage",assistant:"Codex",status:sample == "waiting" ? .waiting : .running),now:1)
                    let bloom = sessions.applyUsage(usage)
                    guard let spec = sessions.liveSpec else {throw Failure.check("actual session spec")}
                    let item = NotchActivity(id:"qa-usage",kind:.session,title:spec.title,subtitle:spec.subtitle,symbol:spec.symbol,startedAt:0,trailing:spec.trailing,sessionPhase:spec.phase)
                    guard let cell = NotchRow.ongoingCells(from:[item]).first else {throw Failure.check("actual row projection")}
                    let value = NotchTile.Ongoing(activityID:cell.activityID,subtitle:cell.subtitle,symbol:cell.symbol,phase:cell.phase,isPaused:cell.isPaused,quantity:cell.quantity,quantityText:cell.quantityText,spoken:cell.spoken,action:cell.action,closesRow:cell.closesRow,accessory:cell.accessory,isStale:cell.isStale,isEnded:cell.isEnded)
                    var tiles = [NotchTile(id:950,kind:.session,snapshot:nil,icon:nil,title:cell.title,waiting:cell.waiting,ongoing:value)]
                    if sample == "shared" {tiles[0] = tiles[0].sessionRedacted()}
                    var usageRecord: [String:Any] = ["leftPercent":usage?.leftPercent as Any? ?? NSNull(),"compactText":usage?.compactText as Any? ?? NSNull(),"recovery":usage?.recovery as Any? ?? NSNull(),"detail":usage?.detailText as Any? ?? NSNull(),"chosenWindowMinutes":reading?.tightest?.windowMinutes as Any? ?? NSNull(),"readingWindowCount":reading?.windows.count ?? 0,"phase":String(describing:spec.phase),"trailing":spec.trailing,"subtitle":spec.subtitle,"bloomDetail":bloom?.detail as Any? ?? NSNull()]
                    var presentedTiles = tiles
                    if sample == "low-updated" {
                        var priorSessions = sessions
                        let priorUsage = UsageReading(windows:[.init(usedPercent:95,windowMinutes:300,resetsAt:now+3600)]).sessionUsage(now:now,model:model,effort:"深入",calendar:calendar)
                        _ = priorSessions.applyUsage(priorUsage)
                        guard let priorSpec = priorSessions.liveSpec else {throw Failure.check("prior usage spec")}
                        let priorItem = NotchActivity(id:"qa-usage",kind:.session,title:priorSpec.title,subtitle:priorSpec.subtitle,symbol:priorSpec.symbol,startedAt:0,trailing:priorSpec.trailing,sessionPhase:priorSpec.phase)
                        guard let priorCell=NotchRow.ongoingCells(from:[priorItem]).first else {throw Failure.check("prior cell")}
                        presentedTiles[0].ongoing?.quantityText = priorCell.quantityText
                        usageRecord["samePhaseSignature"] = presentedTiles[0].ongoingSignature == tiles[0].ongoingSignature
                    }
                    let layout = NotchRow.layout(windows: windows, ongoing: ongoing)
                    let width = max(185 + 120, layout.islandWidth(minimum: 0))
                    let height = 33.5 + NotchIsland.peninsulaContentHeight(142)
                    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
                    let canvas = NotchCanvasView(frame: bounds)
                    let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false; window.alphaValue = 0
                    window.appearance = NSAppearance(named: parent); window.contentView = canvas
                    window.setFrame(NSRect(x: -8000, y: -8000, width: width, height: height), display: false)
                    let content = NotchCanvasView.Content(tiles: presentedTiles, dots: 0, dotsChanged: false, dotsY: 0,
                        compact: nil, compactSlots: nil, alert: nil, hint: nil, notchHeight: 33.5)
                    var completions = 0
                    canvas.morph(to: bounds, style: .init(cornerRadius: 28, allCorners: false, fill: .black, border: 1),
                        content: content, spring: nil) { completions += 1 }
                    canvas.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000); canvas.layoutSubtreeIfNeeded()
                    if sample == "low-updated" {
                        func find(_ v: NSView) -> NotchTileView? {
                            if let tile=v as? NotchTileView {return tile}
                            return v.subviews.compactMap {find($0)}.first
                        }
                        guard let mounted=find(canvas) else {throw Failure.check("mounted usage")}
                        let identity=ObjectIdentifier(mounted)
                        usageRecord["beforeUpdateValue"] = mounted.accessibilityValue() as Any? ?? NSNull()
                        canvas.updateOngoingQuantity(id:950,quantity:value.quantity,text:value.quantityText)
                        usageRecord["retainedTileIdentity"] = find(canvas).map {ObjectIdentifier($0)==identity} ?? false
                        usageRecord["afterUpdateValue"] = mounted.accessibilityValue() as Any? ?? NSNull()
                        canvas.layoutSubtreeIfNeeded()
                    }
                    var actual: [[String: Any]] = []
                    func visit(_ view: NSView) {
                        if let tile = view as? NotchTileView, !tile.isHiddenOrHasHiddenAncestor {
                            guard let payload = Mirror(reflecting: tile).children.first(where: { $0.label == "tile" })?.value as? NotchTile else { return }
                            var record: [String: Any] = ["id": tile.tileID, "frame": rect(tile.convert(tile.bounds, to: canvas)),
                                "title": payload.title, "kind": String(describing: payload.kind), "dark": tile.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
                                "accessibility": tile.accessibilityLabel() ?? ""]
                            if let value = payload.ongoing {
                                record["subtitle"] = value.subtitle; record["quantity"] = String(describing: value.quantity)
                                record["quantityText"] = value.quantityText as Any? ?? NSNull()
                                record["stale"] = value.isStale; record["ended"] = value.isEnded
                                record["shelf"] = value.shelfCount as Any? ?? NSNull()
                                record["drawing"] = String(describing:value.quantity.drawing)
                                record["paused"] = value.isPaused
                                record["accessibilityValue"] = tile.accessibilityValue() as Any? ?? NSNull()
                                record["tooltip"] = tile.toolTip as Any? ?? NSNull()
                                let font = NSFont.monospacedDigitSystemFont(ofSize:10.5,weight:.semibold)
                                let rounded = font.fontDescriptor.withDesign(.rounded).flatMap {NSFont(descriptor:$0,size:font.pointSize)} ?? font
                                record["naturalQuantityWidth"] = NSAttributedString(string:value.quantityText ?? "",attributes:[.font:rounded]).size().width
                                let reserve: CGFloat = value.quantity.drawing == .ring || value.quantity.drawing == .spinningArc ? CGFloat(NotchProgressPart.ringDiameter + NotchProgressPart.textGap) : 0
                                let available = tile.bounds.width - 20 - reserve
                                let rendered = NotchTileView.quantityLabel(value.quantity,text:value.quantityText ?? "",font:rounded,availableWidth:available)
                                record["renderedQuantityText"] = rendered.string
                                record["renderedQuantityWidth"] = rendered.size().width
                                record["quantityAvailableWidth"] = available
                                if let part = Mirror(reflecting:tile).children.first(where:{$0.label == "part"})?.value as? NotchProgressPartLayers {
                                    record["partHidden"] = part.root.isHidden
                                    record["partFrame"] = rect(part.root.frame)
                                    record["partQuantity"] = String(describing:part.model.quantity)
                                    record["layerChildren"] = (part.root.sublayers ?? []).map {layer -> [String:Any] in
                                        var entry: [String:Any] = ["hidden":layer.isHidden,"animations":layer.animationKeys() ?? []]
                                        if let shape=layer as? CAShapeLayer {entry["strokeEnd"]=shape.strokeEnd}
                                        return entry
                                    }
                                }
                            }
                            actual.append(record)
                        }
                        view.subviews.forEach(visit)
                    }
                    visit(canvas)
                    guard actual.count == tiles.count, completions == 1, !window.isVisible, !NSApp.isActive,
                        window.alphaValue == 0, NSScreen.screens.allSatisfy({ !window.frame.intersects($0.frame) }) else { throw Failure.check("actual tiles/host") }
                    let name = "\(parent == .aqua ? "light" : "dark")-\(sample)"
                    guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { throw Failure.check("bitmap") }
                    canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
                    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure.check("png") }
                    try png.write(to: out.appendingPathComponent(name + ".png"))
                    frames.append(["name": name, "sample": sample, "windows": windows, "ongoing": ongoing,
                        "width": width, "height": height, "tiles": actual, "usage":usageRecord,"completions": completions,
                        "canvasDark": canvas.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
                        "visible": window.isVisible, "active": NSApp.isActive, "alpha": window.alphaValue])
                    window.contentView = nil; window.close()
                }
            }
            try JSONSerialization.data(withJSONObject: ["frames": frames, "sourceControllers": 0, "actions": 0], options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("frames.json"))
            print("PASS \(frames.count) actual usage quantity static frames; no source/controllers/actions")
        } catch { fputs("FAIL \(error)\n", stderr); exit(1) }
    }
}
