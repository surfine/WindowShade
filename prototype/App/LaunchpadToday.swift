import Cocoa

/// 负一屏只展示本机实时数据；不读取日历事件或模拟第三方小组件。
@MainActor
final class LaunchpadTodayPage {
    enum Action: Equatable { case spotlight, calendar, app(String) }
    struct Item { let frame: CGRect; let title: String; let action: Action }
    let root = CALayer()
    private(set) var items: [Item] = []
    private var scale: CGFloat = 2

    func layout(size: CGSize, top: CGFloat, bottom: CGFloat, date: Date = Date(),
                running: [(path: String, name: String, icon: CGImage?)]) {
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
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
        let search = CGRect(x: clock.maxX + 24, y: y, width: column, height: 60)
        plate(clock); plate(month); plate(search, radius: 22)
        text(date.formatted(.dateTime.month(.wide).day().weekday(.wide)),
             frame: clock.insetBy(dx: 24, dy: 16).withHeight(24), font: 16)
        text(date.formatted(date: .omitted, time: .shortened),
             frame: CGRect(x: clock.minX + 22, y: clock.minY + 44, width: column - 44, height: clockHeight - 56),
             font: min(64, clockHeight * 0.40), weight: .light)
        drawMonth(date, frame: month)
        items.append(Item(frame: month, title: "打开日历", action: .calendar))
        let symbol = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .regular))
        let icon = CALayer()
        icon.contents = symbol?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        icon.frame = CGRect(x: search.minX + 20, y: search.midY - 11, width: 22, height: 22)
        icon.contentsGravity = .resizeAspect; root.addSublayer(icon)
        text("Spotlight", frame: CGRect(x: search.minX + 54, y: search.minY + 9, width: column - 70, height: 23), font: 18)
        text("搜索 App、文件与更多内容", frame: CGRect(x: search.minX + 54, y: search.minY + 32, width: column - 70, height: 20), font: 12, alpha: 0.7)
        items.append(Item(frame: search, title: "打开 Spotlight", action: .spotlight))
        text("正在运行", frame: CGRect(x: search.minX + 4, y: search.maxY + 26, width: column - 8, height: 28), font: 20, weight: .semibold)
        let listTop = search.maxY + 68
        let count = min(6, running.count)
        let pitch = min(66, max(40, (bottom - listTop) / CGFloat(max(1, count))))
        for (index, app) in running.prefix(count).enumerated() {
            let rect = CGRect(x: search.minX, y: listTop + CGFloat(index) * pitch, width: column, height: pitch)
            let side = min(48, pitch - 8)
            let icon = CALayer(); icon.contents = app.icon; icon.contentsGravity = .resizeAspect
            icon.frame = CGRect(x: rect.minX, y: rect.midY - side / 2, width: side, height: side)
            root.addSublayer(icon)
            text(app.name, frame: CGRect(x: rect.minX + side + 14, y: rect.midY - 12, width: column - side - 20, height: 24), font: 15)
            items.append(Item(frame: rect, title: app.name, action: .app(app.path)))
        }
        if count == 0 {
            text("没有正在运行的 App", frame: CGRect(x: search.minX + 4, y: listTop, width: column - 8, height: 24), font: 14, alpha: 0.65)
        }
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
