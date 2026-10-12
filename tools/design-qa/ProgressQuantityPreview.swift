import Cocoa
import QuartzCore

#if !swift(>=6.0)
#error("ProgressQuantityPreview requires --swift6")
#endif

/// Production M11 canvas/content, without any source/controller/window operation.
@main enum ProgressQuantityPreview {
    enum Failure: Error { case check(String) }
    static func rect(_ r: NSRect) -> [String: Double] { ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height] }
    @MainActor static func main() async {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            var frames: [[String: Any]] = []
            for parent in [NSAppearance.Name.aqua, .darkAqua] {
                for sample in ["zero", "percent", "complete-value", "count", "large-count", "huge-count", "indeterminate", "unknown", "paused", "ended", "stale", "long", "three"] {
                    let windows = 0
                    let ongoing = sample == "three" ? 3 : 1
                    var tiles = [NotchTile]()
                    for index in 0..<ongoing {
                        let quantity: NotchActivity.Quantity
                        switch sample {
                        case "zero": quantity = .fraction(0)
                        case "complete-value", "ended": quantity = .fraction(1)
                        case "count": quantity = .count(2,9)
                        case "large-count": quantity = .count(999,1000)
                        case "huge-count": quantity = .count(999999,1000000)
                        case "indeterminate": quantity = .indeterminate
                        case "unknown": quantity = .unknown
                        case "three": quantity = index == 0 ? .fraction(0.42) : (index == 1 ? .count(2,9) : .indeterminate)
                        default: quantity = .fraction(0.42)
                        }
                        guard quantity.isValid else {throw Failure.check("valid fixture quantity")}
                        let subtitle = sample == "long" ? "WindowShade_设计评审_最终材料_" + String(repeating:"外观与动作检查", count:12) + ".zip" : "演示材料.zip"
                        var item = NotchActivity(id:"qa-progress-\(index)",kind:.download,title:sample == "paused" ? "下载已暂停" : (sample == "ended" ? "下载已完成" : "正在下载"),subtitle:subtitle,symbol:"arrow.down.circle",startedAt:0,progress:quantity,isPaused:sample == "paused",sessionPhase:nil)
                        item.isStale = sample == "stale"
                        if sample == "ended" {item.endedAt = 1}
                        guard let cell = NotchRow.ongoingCells(from:[item]).first else {throw Failure.check("actual Core projection")}
                        let value = NotchTile.Ongoing(activityID:cell.activityID,subtitle:cell.subtitle,symbol:cell.symbol,phase:cell.phase,isPaused:cell.isPaused,quantity:cell.quantity,quantityText:cell.quantityText,spoken:cell.spoken,action:cell.action,closesRow:cell.closesRow,accessory:cell.accessory,isStale:cell.isStale,isEnded:cell.isEnded)
                        tiles.append(NotchTile(id:UInt32(850+index),kind:.activity,snapshot:nil,icon:nil,title:cell.title,waiting:false,ongoing:value))
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
                    let content = NotchCanvasView.Content(tiles: tiles, dots: 0, dotsChanged: false, dotsY: 0,
                        compact: nil, compactSlots: nil, alert: nil, hint: nil, notchHeight: 33.5)
                    var completions = 0
                    canvas.morph(to: bounds, style: .init(cornerRadius: 28, allCorners: false, fill: .black, border: 1),
                        content: content, spring: nil) { completions += 1 }
                    canvas.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000); canvas.layoutSubtreeIfNeeded()
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
                        "width": width, "height": height, "tiles": actual, "completions": completions,
                        "canvasDark": canvas.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
                        "visible": window.isVisible, "active": NSApp.isActive, "alpha": window.alphaValue])
                    window.contentView = nil; window.close()
                }
            }
            try JSONSerialization.data(withJSONObject: ["frames": frames, "sourceControllers": 0, "actions": 0], options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("frames.json"))
            print("PASS \(frames.count) actual progress quantity static frames; no source/controllers/actions")
        } catch { fputs("FAIL \(error)\n", stderr); exit(1) }
    }
}
