import Foundation

/// R05：放回提醒只在 n>0 时说；检查更新时间的写法；缩略图的标题变化刘海不跟。
@main struct RescueAnnounceTests {
    static func main() {
        rescue()
        lastChecked()
        changeFilter()
        print("PASS: rescue announce, last-checked time, thumbnail change filter")
    }

    static func rescue() {
        precondition(RescueAnnounce.line(restored: 0) == nil)
        precondition(RescueAnnounce.line(restored: -1) == nil)
        let one = RescueAnnounce.line(restored: 3)!
        precondition(one.headline == "已放回3扇窗口", one.headline)
        precondition(one.detail == "上次意外退出了", one.detail)
        let many = RescueAnnounce.line(restored: 12)!
        precondition(many.headline.count <= NotchSentence.headlineLimit, many.headline)
        precondition(many.detail.hasSuffix("上次意外退出了"), many.detail)
    }

    static func lastChecked() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        func date(_ d: Int, _ h: Int, _ m: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
        }
        let now = date(9, 18, 5)
        precondition(UpdateCopy.lastChecked(date(9, 9, 40), now: now, calendar: calendar) == "上次检查：今天 09:40")
        precondition(UpdateCopy.lastChecked(date(8, 23, 59), now: now, calendar: calendar) == "上次检查：昨天 23:59")
        precondition(UpdateCopy.lastChecked(date(3, 7, 5), now: now, calendar: calendar) == "上次检查：10月3日 07:05")
    }

    static func changeFilter() {
        // 只有缩略图模式的窗口变了：刘海不跟。
        precondition(!NotchChangeFilter.hasVisibleChange([1, 2], isThumbnail: { _ in true }))
        precondition(!NotchChangeFilter.hasVisibleChange([Int](), isThumbnail: { _ in false }))
        // 混着卷帘条或收进刘海的：照旧跟。
        precondition(NotchChangeFilter.hasVisibleChange([1, 2], isThumbnail: { $0 == 1 }))
    }
}
