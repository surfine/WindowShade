import Cocoa

/// 自造日程输入走生产呈现纯核；不读 EventKit，不开产品或会议链接。
@main enum CalendarCardPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var frames: [[String: Any]] = []
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for state in ["normal", "long-title", "no-location", "sharing", "started", "others"] {
                let event = CalendarEventInput(id: "fixture", title: state == "long-title" ? "跨团队产品设计评审与下季度计划确认" : "设计评审",
                    start: now.addingTimeInterval(state == "started" ? -30 : 240), end: now.addingTimeInterval(1800),
                    url: "https://zoom.us/j/123456789", location: state == "no-location" ? nil : "3 号会议室", colorRGB: 0x0A84FF)
                let other = CalendarEventInput(id: "other", title: "项目周会", start: now.addingTimeInterval(280), end: now.addingTimeInterval(2000))
                let selection = CalendarActivity.select(from: state == "others" || state == "sharing" ? [event, other] : [event], now: now)!
                let text = CalendarCardText.make(selection, sharing: state == "sharing", calendar: calendar)
                let card = CalendarCard(frame: .zero)
                card.appearance = NSAppearance(named: appearance)
                card.render(text, colorRGB: event.colorRGB, spoken: text.title + "，" + text.big + text.small)
                card.frame = NSRect(origin: .zero, size: card.interactionSize)
                let container = NSView(frame: card.frame)
                container.wantsLayer = true; container.layer?.backgroundColor = NSColor.black.cgColor
                container.addSubview(card)
                let window = NSWindow(contentRect: container.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = container; window.appearance = card.appearance
                container.layoutSubtreeIfNeeded()
                let name = "\(appearance == .aqua ? "light" : "dark")-\(state)"
                guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else {
                    throw NSError(domain: "CalendarPreview", code: 1)
                }
                container.cacheDisplay(in: container.bounds, to: rep)
                guard let data = rep.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "CalendarPreview", code: 2)
                }
                try data.write(to: output.appendingPathComponent(name + ".png"))
                frames.append(["image": name + ".png", "width": card.bounds.width, "height": card.bounds.height,
                               "cornerRadius": card.interactionCornerRadius, "visibleWindow": window.isVisible,
                               "title": text.title, "location": text.location, "others": text.others ?? ""])
                window.close()
            }
        }
        try JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("frames.json"))
        print("Rendered 12 production calendar card frames; no EventKit or visible window.")
    }
}
