import Cocoa
import QuartzCore

#if !swift(>=6.0)
#error("NotchRetargetPreview requires render-native-surfaces.sh --swift6")
#endif

/// 第26批动效探针：同一实际 NotchCanvasView、隐藏自有宿主。逐轴记录接力配置（position.x/y、
/// bounds.size.width/height、cornerRadius）、呈现轨迹、富内容延迟收形状的实际起点、近零行程 kick、
/// 取消与过期回调、减少动态效果。配置与隐藏呈现证据，不是帧率/可见合成/真机验收。
@main enum NotchRetargetPreview {
    enum Failure: Error { case check(String) }
    /// 时间点诊断：不把线程本地状态带过 await。
    @MainActor static func mainThreadNow() -> Bool { Thread.isMainThread }
    @MainActor static func field(_ object: Any, _ name: String) -> Any? {
        guard let value = Mirror(reflecting: object).children.first(where: { $0.label == name })?.value else { return nil }
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional ? mirror.children.first?.value : value
    }
    @MainActor static func box(_ r: NSRect) -> [String: CGFloat] { ["x":r.minX,"y":r.minY,"width":r.width,"height":r.height] }
    /// 带真实内容的岛内容（一排一格，足够的“富内容”触发先退文字的路）。
    @MainActor static func richContent(id: UInt32, count: Int = 2) throws -> NotchCanvasView.Content {
        let item = NotchActivity(id: "qa-retarget-\(id)", kind: .download, title: "演示下载", subtitle: "演示材料.zip",
                                 symbol: "arrow.down.circle", startedAt: 0, progress: .count(count, 9),
                                 isPaused: false, sessionPhase: nil)
        guard let cell = NotchRow.ongoingCells(from: [item]).first else { throw Failure.check("pure Core projection") }
        let ongoing = NotchTile.Ongoing(activityID: cell.activityID, subtitle: cell.subtitle, symbol: cell.symbol,
            phase: cell.phase, isPaused: cell.isPaused, quantity: cell.quantity, quantityText: cell.quantityText,
            spoken: cell.spoken, action: cell.action, closesRow: cell.closesRow, accessory: cell.accessory,
            isStale: cell.isStale, isEnded: cell.isEnded)
        return .init(tiles: [NotchTile(id: id, kind: .activity, snapshot: nil, icon: nil, title: cell.title,
                                       waiting: false, ongoing: ongoing)],
                     dots: 0, dotsChanged: false, dotsY: 0, compact: nil, compactSlots: nil, alert: nil, hint: nil,
                     notchHeight: 33.5)
    }
    @MainActor static func emptyContent() -> NotchCanvasView.Content {
        .init(tiles: [], dots: 0, dotsChanged: false, dotsY: 0, compact: nil, compactSlots: nil, alert: nil, hint: nil,
              notchHeight: 33.5)
    }
    /// 一根轴上的动画：弹簧记录实际系数与归一化初速度；关键帧记录采样值（kick 路）。
    @MainActor static func animations(_ layer: CALayer) -> [[String: Any]] {
        var out = [[String: Any]]()
        for key in (layer.animationKeys() ?? []).sorted() {
            guard let a = layer.animation(forKey: key) else { continue }
            if let s = a as? CASpringAnimation {
                var d: [String: Any] = ["key":key,"keyPath":s.keyPath ?? "","class":"CASpringAnimation",
                                        "mass":Double(s.mass),"stiffness":Double(s.stiffness),"damping":Double(s.damping),
                                        "duration":s.duration,"beginTime":s.beginTime,"additive":s.isAdditive,
                                        "velocity":Double(s.initialVelocity)]
                if let f = s.fromValue as? NSNumber { d["from"] = f.doubleValue }
                out.append(d)
            } else if let k = a as? CAKeyframeAnimation {
                var d: [String: Any] = ["key":key,"keyPath":k.keyPath ?? "","class":"CAKeyframeAnimation",
                                        "duration":k.duration,"beginTime":k.beginTime,"additive":k.isAdditive]
                if let vs = k.values { d["values"] = vs.compactMap { ($0 as? NSNumber)?.doubleValue } }
                if let kt = k.keyTimes { d["keyTimes"] = kt.map(\.doubleValue) }
                out.append(d)
            }
        }
        return out
    }
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        guard Thread.isMainThread, NSApp.delegate == nil else { fatalError("own main-thread entry only") }
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        Task { @MainActor in
            do { try await run(out); exit(0) }
            catch {
                try? String(describing: error).write(to: out.appendingPathComponent("failure.txt"), atomically: true, encoding: .utf8)
                print("FAILED retarget probe: \(error)"); exit(1)
            }
        }
        // 只有本入口驱动 Cocoa；没有产品 delegate、监听、控制器、菜单或输入注入。
        NSApp.run()
    }
    @MainActor static func run(_ out: URL) async throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let oldOverride = Motion.reducedOverrideForProbe
        defer { Motion.reducedOverrideForProbe = oldOverride }
        var records = [[String: Any]]()
        var trajectory = [[String: Any]]()
        var counts = [String: Int]()
        for reduced in [false, true] {
            Motion.reducedOverrideForProbe = reduced
            let mode = reduced ? "reduced" : "regular"
            let bounds = NSRect(x:0,y:0,width:800,height:400)
            let canvas = NotchCanvasView(frame: bounds)
            let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.alphaValue = 0; window.contentView = canvas
            window.setFrame(NSRect(x:-8000,y:-8000,width:800,height:400), display:false)
            defer { window.close() }
            guard let island = field(canvas,"island") as? CALayer else { throw Failure.check("actual island layer") }
            let compact = NSRect(x:307.5,y:366.5,width:185,height:33.5)
            let expanded = NSRect(x:247.5,y:180,width:305,height:220)
            let wide = NSRect(x:187.5,y:180,width:425,height:220)
            let rich = try richContent(id: 900), rich2 = try richContent(id: 901, count: 4)
            let empty = emptyContent()
            func token(_ shape: Motion.NotchShape) -> NotchCanvasView.Spring {
                let value = Motion.notchSpring(for:shape)
                return .init(response:value.response,bounce:value.bounce)
            }
            func tileIDs() -> [[String: UInt32]] {
                var ids = [[String: UInt32]]()
                guard let current = field(canvas,"current") as? NSView else { return ids }
                func visit(_ view:NSView) {
                    if let tile = view as? NotchTileView, let model = field(tile,"tile") as? NotchTile {
                        ids.append(["id": model.id])
                    }
                    view.subviews.forEach(visit)
                }
                visit(current)
                return ids
            }
            func record(_ stage: String) {
                let presented = island.presentation()
                let current = field(canvas,"current") as? NSView
                records.append(["stage":mode+"-"+stage, "mode":mode, "reduced":reduced, "time":CACurrentMediaTime(),
                    "model":box(island.frame),
                    "presentation":presented.map{box($0.frame)} as Any? ?? NSNull(),
                    "presentedRadius":presented?.cornerRadius as Any? ?? NSNull(),
                    "modelRadius":island.cornerRadius,
                    "animations":animations(island),
                    "otherKeys":["clip":(field(canvas,"clip") as? CALayer)?.animationKeys() ?? [],
                                 "keyLine":(field(canvas,"keyLine") as? CALayer)?.animationKeys() ?? [],
                                 "keyMask":(field(canvas,"keyMask") as? CALayer)?.animationKeys() ?? []],
                    "counts":counts,
                    "pendingExit":field(canvas,"contentExitPending") as? Bool ?? false,
                    "currentIdentity":current.map{String(describing:ObjectIdentifier($0))} as Any? ?? NSNull(),
                    "tileIDs":tileIDs(),
                    "active":NSApp.isActive, "visible":window.isVisible, "alpha":window.alphaValue,
                    "mainThread":Thread.isMainThread, "delegateNil":NSApp.delegate == nil, "cacheOnly":true])
            }
            func trajectorySample(_ stage: String, _ count: Int, everyMilliseconds ms: UInt64 = 12) async throws {
                var samples = [[String: Any]]()
                for _ in 0..<count {
                    let presented = island.presentation()
                    var s: [String: Any] = ["t":CACurrentMediaTime(), "model":box(island.frame)]
                    if let frame = presented?.frame {
                        s["presentation"] = box(frame); s["midX"] = frame.midX; s["midY"] = frame.midY
                    }
                    s["radius"] = presented?.cornerRadius as Any? ?? NSNull()
                    samples.append(s)
                    try await Task.sleep(nanoseconds: ms*1_000_000)
                }
                trajectory.append(["stage":mode+"-"+stage, "reduced":reduced, "samples":samples])
            }
            func morph(_ name: String, to rect: NSRect, content: NotchCanvasView.Content, spring: NotchCanvasView.Spring?) {
                let key = mode+"-"+name
                canvas.morph(to:rect,style:.init(cornerRadius:rect.height>34 ? 28:12,allCorners:false,fill:.black,border:0.5),
                             content:content,spring:spring) { counts[key,default:0] += 1 }
            }
            func sleep(_ ms: UInt64) async throws { try await Task.sleep(nanoseconds: ms*1_000_000) }

            morph("initial", to: compact, content: empty, spring: nil); try await sleep(60); record("initial")
            // 一、展开；中途反向；再次改向。每段记 before（旧动画配置）与 new/attach（新配置）。
            record("open-old")
            morph("open", to: expanded, content: rich, spring: token(.expanded))
            record("open-new"); try await sleep(12); record("open-attach")
            try await sleep(78); record("open-sample")
            try await trajectorySample("open-flight", 6)
            record("reverse-old")
            morph("reverse", to: compact, content: rich, spring: token(.compact))
            record("reverse-new"); try await sleep(12); record("reverse-attach")
            try await trajectorySample("reverse-flight", 8); record("reverse-sample")
            record("reopen-old")
            morph("reopen", to: expanded, content: rich, spring: token(.expanded))
            record("reopen-new"); try await sleep(12); record("reopen-attach")
            try await trajectorySample("reopen-flight", 8)
            // 二、只改宽度：飞行中把目标换成更宽的（位置/高度/圆角各自的行程独立）。
            record("width-old")
            morph("width", to: wide, content: rich, spring: token(.expanded))
            record("width-new"); try await sleep(12); record("width-attach")
            try await trajectorySample("width-flight", 6)
            try await sleep(700); record("wide-settled")
            // 三、停稳后只改宽度回展开：这一跳应当只有宽度轴有动画（其它轴零行程）。
            record("width-reverse-old")
            morph("width-reverse", to: expanded, content: rich, spring: token(.expanded))
            record("width-reverse-new"); try await sleep(12); record("width-reverse-attach")
            try await sleep(700); record("settled")
            morph("pre-compact", to: compact, content: rich2, spring: token(.compact))
            try await sleep(700); record("pre-compact-settled")
            if !reduced {
                // 四、富内容先退文字：形状收得晚（0.10 淡出 + 0.04 一拍）。期间岛仍在飞，
                // 结束时要读那一刻的呈现层——不能用发起时缓存的位置。
                morph("rich-exit-open", to: expanded, content: rich2, spring: token(.expanded))
                try await sleep(90)
                record("rich-exit-old")
                morph("rich-exit", to: compact, content: empty, spring: token(.compact))
                try await sleep(40); record("rich-exit-fade")
                try await trajectorySample("rich-exit-gap", 10)
                try await sleep(40); record("rich-exit-new")
                try await sleep(500); record("rich-exit-settled")
                // 五、近零行程 kick：还在飞时把目标设成此刻的外框（各轴几乎零行程、速度还在）。
                morph("kick-open", to: expanded, content: empty, spring: token(.expanded))
                try await sleep(90)
                if let p = island.presentation()?.frame {
                    let target = NSRect(x: (p.midX*20).rounded()/20 - p.width/2, y: (p.midY*20).rounded()/20 - p.height/2,
                                        width: p.width, height: p.height)
                    record("kick-old")
                    morph("kick", to: target, content: empty, spring: token(.expanded))
                    record("kick-new"); try await sleep(12); record("kick-attach")
                    try await trajectorySample("kick-flight", 8)
                    try await sleep(500); record("kick-settled")
                }
                // 六、取消：退场淡出还没完又改回展开。旧退场的收尾不能清掉新内容，过期回调不重放。
                morph("cancel-open", to: expanded, content: rich, spring: token(.expanded))
                record("cancel-open-new")
                try await sleep(80)
                record("cancel-close-old")
                morph("cancel-close", to: compact, content: empty, spring: token(.compact))
                record("cancel-close-new"); try await sleep(50); record("cancel-close-fade")
                record("cancel-reopen-old")
                morph("cancel-reopen", to: expanded, content: rich2, spring: token(.expanded))
                record("cancel-reopen-new")
                try await sleep(600); record("cancel-reopen-settled")
                morph("final-close", to: compact, content: empty, spring: token(.compact))
                try await sleep(600); record("final-closed")
            } else {
                // 减少动态效果：形状没有动画，直接到位。
                morph("rm-open", to: expanded, content: rich, spring: token(.expanded))
                record("rm-open-after"); try await sleep(60); record("rm-open-settled")
                morph("rm-close", to: compact, content: empty, spring: token(.compact))
                record("rm-close-after"); try await sleep(60); record("rm-close-settled")
            }
            window.close()
        }
        Motion.reducedOverrideForProbe = oldOverride
        let report: [String: Any] = ["records":records, "trajectory":trajectory, "counts":counts,
            "overrideRestored":Motion.reducedOverrideForProbe == oldOverride, "cacheOnly":true,
            "compositorAccepted":false, "realSources":0, "globalInputEvents":0, "productEntry":false,
            "swiftLanguageVersion":6, "mainThread":mainThreadNow()]
        try JSONSerialization.data(withJSONObject:report, options: [.prettyPrinted,.sortedKeys])
            .write(to: out.appendingPathComponent("retarget.json"), options: .atomic)
        print("PASS \(records.count) actual retarget records; per-axis config; compositor untested")
    }
}
