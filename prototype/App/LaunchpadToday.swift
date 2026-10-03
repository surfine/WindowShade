import Cocoa

/// 负一屏照 iPad 的排法：一列小组件——左边日期/时钟与当月日历，右边实时活动与四个快捷方式。
/// 只展示本机实时数据；不读取日历事件，也不模拟第三方小组件。搜索不在这里，是 Home Screen 底部那枚胶囊。
@MainActor
final class LaunchpadTodayPage {
    enum Action: Equatable { case spotlight, calendar, app(String), activity(String, NotchActivityAction), activityTool(NotchActivityAction) }
    struct Item { let frame: CGRect; let title: String; let action: Action }
    let root = CALayer()
    private(set) var items: [Item] = []
    private var scale: CGFloat = 2
    let activities = LaunchpadActivityCards()
    private var baseItems: [Item] = []
    func updateActivities(_ values: [NotchActivity]) {
        activities.update(values)
        refreshActivityHits()
    }
    private func refreshActivityHits() {
        items = baseItems + activities.hits.map { Item(frame: $0.frame, title: $0.title, action: .activity($0.id, $0.action)) }
    }

    func layout(size: CGSize, top: CGFloat, bottom: CGFloat, date: Date = Date(),
                running: [(path: String, name: String, icon: CGImage?)]) {
        root.sublayers?.filter { $0 !== activities.root }.forEach { $0.removeFromSuperlayer() }
        if activities.root.superlayer == nil { root.addSublayer(activities.root) }
        items = []
        scale = NSScreen.main?.backingScaleFactor ?? 2
        let width = min(820, max(280, size.width - 80))
        let left = (size.width - width) / 2
        let column = (width - 24) / 2
        let available = max(280, bottom - top)
        let y = top + max(0, (available - 530) / 2)
        let clockHeight = min(172, available * 0.31)
        let calendarHeight = min(310, available - clockHeight - 24)
        let clock = CGRect(x: left, y: y, width: column, height: clockHeight)
        let month = CGRect(x: left, y: clock.maxY + 24, width: column, height: calendarHeight)
        plate(clock); plate(month)
        text(date.formatted(.dateTime.month(.wide).day().weekday(.wide)),
             frame: clock.insetBy(dx: 24, dy: 16).withHeight(24), font: 16)
        text(date.formatted(date: .omitted, time: .shortened),
             frame: CGRect(x: clock.minX + 22, y: clock.minY + 44, width: column - 44, height: clockHeight - 56),
             font: min(64, clockHeight * 0.40), weight: .light)
        drawMonth(date, frame: month)
        items.append(Item(frame: month, title: "打开日历", action: .calendar))
        // 右边那一列：小组件标题在上，活动卡片铺开，四个快捷方式压在列底。
        let rightX = clock.maxX + 24
        let toolsHeight: CGFloat = 30
        let toolRow = CGRect(x: rightX, y: month.maxY - toolsHeight, width: column, height: toolsHeight)
        text("实时活动", frame: CGRect(x: rightX + 4, y: y, width: column - 8, height: 28), font: 20, weight: .semibold)
        let tools: [(String, NotchActivityAction)] = [("音乐", .enableMusic), ("隔空投送", .airDrop), ("路线", .route), ("语音备忘录", .voiceMemos), ("番茄钟", .focusOpen)]
        for (index, tool) in tools.enumerated() {
            let rect = CGRect(x: toolRow.minX + CGFloat(index) * column / CGFloat(tools.count), y: toolRow.minY, width: column / CGFloat(tools.count) - 4, height: toolsHeight)
            plate(rect, radius: 15)
            text(tool.0, frame: rect.insetBy(dx: 4, dy: 6), font: 12, alignment: .center)
            items.append(Item(frame: rect, title: tool.0, action: .activityTool(tool.1)))
        }
        let activityTop = y + 36
        activities.layout(CGRect(x: rightX, y: activityTop, width: column,
                                 height: max(0, toolRow.minY - 22 - activityTop)), scale: scale)
        baseItems = items
        refreshActivityHits()
        activities.root.removeFromSuperlayer(); root.addSublayer(activities.root)
    }

    func target(at point: CGPoint) -> Action? { items.first { $0.frame.contains(point) }?.action }

    private func plate(_ frame: CGRect, radius: CGFloat = 28) {
        let layer = LaunchpadGlass.make(blur: 26, tint: 0.14)
        layer.frame = frame; layer.cornerRadius = radius
        root.addSublayer(layer)
    }

    private func text(_ string: String, frame: CGRect, font: CGFloat, weight: NSFont.Weight = .regular,
                      alpha: CGFloat = 1, alignment: CATextLayerAlignmentMode = .left) {
        let layer = CATextLayer()
        layer.string = string
        layer.font = NSFont.systemFont(ofSize: font, weight: weight)
        layer.fontSize = font; layer.foregroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
        layer.alignmentMode = alignment; layer.truncationMode = .end
        layer.contentsScale = scale; layer.frame = frame
        root.addSublayer(layer)
    }

    private func drawMonth(_ date: Date, frame: CGRect) {
        let calendar = Calendar.current
        let formatter = DateFormatter(); formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        text(formatter.string(from: date), frame: CGRect(x: frame.minX + 24, y: frame.minY + 18, width: frame.width - 48, height: 26), font: 20, weight: .semibold)
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let days = calendar.range(of: .day, in: .month, for: date) else { return }
        let leading = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let current = calendar.component(.day, from: date)
        let col = (frame.width - 36) / 7
        let row = (frame.height - 84) / 6
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? ["日", "一", "二", "三", "四", "五", "六"]
        for i in 0..<7 {
            let symbol = symbols[(calendar.firstWeekday - 1 + i) % 7]
            text(symbol, frame: CGRect(x: frame.minX + 18 + CGFloat(i) * col, y: frame.minY + 53, width: col, height: 20), font: 12, alpha: 0.6, alignment: .center)
        }
        for day in days {
            let index = leading + day - 1
            let box = CGRect(x: frame.minX + 18 + CGFloat(index % 7) * col,
                             y: frame.minY + 78 + CGFloat(index / 7) * row, width: col, height: row)
            if day == current {
                let highlight = CALayer(); let side = min(30, row)
                highlight.frame = CGRect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side)
                highlight.cornerRadius = side / 2; highlight.backgroundColor = NSColor.systemRed.cgColor
                root.addSublayer(highlight)
            }
            text(String(day), frame: CGRect(x: box.minX, y: box.midY - 9, width: col, height: 20), font: 14,
                 weight: day == current ? .semibold : .regular, alignment: .center)
        }
    }
}

private extension CGRect {
    func withHeight(_ height: CGFloat) -> CGRect { CGRect(x: minX, y: minY, width: width, height: height) }
}
