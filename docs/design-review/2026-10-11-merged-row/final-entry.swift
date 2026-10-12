import Cocoa

/// Production M11 canvas/content, without any source/controller/window operation.
@main enum MergedRowPreview {
    enum Failure: Error { case check(String) }
    static func rect(_ r: NSRect) -> [String: Double] { ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height] }
    @MainActor static func main() async {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            var frames: [[String: Any]] = []
            for parent in [NSAppearance.Name.aqua, .darkAqua] {
                for sample in ["windows", "activities", "mixed", "long", "unknown", "stale-ended"] {
                    let windows = sample == "activities" ? 0 : 2
                    let ongoing = sample == "windows" ? 0 : 3
                    var tiles: [NotchTile] = (0..<windows).map { index in
                        NotchTile(id: UInt32(700 + index), kind: .tucked, snapshot: nil,
                            icon: NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil),
                            title: sample == "long" ? String(repeating: "设计评审记录", count: 16) : "样件窗口 \(index + 1)", changed: index == 0)
                    }
                    for index in 0..<ongoing {
                        let baseTitle = index == 0 ? "设计工作间" : (index == 1 ? "正在播放" : "正在下载")
                        let title = sample == "long" ? baseTitle + String(repeating: " — 长项目与文件名", count: 12) : baseTitle
                        let activityKind: NotchActivityKind = index == 0 ? .session : (index == 1 ? .music : .download)
                        let quantity: NotchActivity.Quantity = sample == "unknown" || index == 0 ? .unknown
                            : (index == 2 ? .count(2, 9) : .fraction(0.42))
                        var item = NotchActivity(id: "qa-activity-\(index)", kind: activityKind, title: title,
                            subtitle: sample == "long" ? String(repeating: "下一段长内容", count: 12) : (index == 0 ? "等你" : (index == 1 ? "样件歌曲" : "演示材料.zip")),
                            symbol: index == 0 ? "terminal" : (index == 1 ? "music.note" : "arrow.down.circle"),
                            startedAt: 0, progress: quantity, isPaused: sample == "stale-ended" && index == 1,
                            sessionPhase: index == 0 ? .waiting : nil)
                        item.isStale = sample == "stale-ended" && index == 0
                        if sample == "stale-ended" && index == 2 { item.endedAt = 1 }
                        guard let cell = NotchRow.ongoingCells(from: [item]).first else { throw Failure.check("actual projection") }
                        let kind: NotchTile.Kind = cell.isSession ? .session : (cell.kind == .music ? .playing : .activity)
                        let content = NotchTile.Ongoing(activityID: cell.activityID, subtitle: cell.subtitle, symbol: cell.symbol,
                            phase: cell.phase, isPaused: cell.isPaused, quantity: cell.quantity, quantityText: cell.quantityText,
                            spoken: cell.spoken, action: cell.action, closesRow: cell.closesRow, accessory: cell.accessory,
                            isStale: cell.isStale, isEnded: cell.isEnded)
                        tiles.append(NotchTile(id: UInt32(800 + index), kind: kind, snapshot: nil, icon: nil,
                            title: cell.title,
                            waiting: index == 0, ongoing: content))
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
            print("PASS 12 actual merged-row static frames; no source/controllers/actions")
        } catch { fputs("FAIL \(error)\n", stderr); exit(1) }
    }
}
