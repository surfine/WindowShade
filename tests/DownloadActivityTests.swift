// 下载进度卡的行为测试：只看公开接口的输入输出。纯 Foundation，无权限、无 UI。

import Foundation

@main struct DownloadActivityTests {
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, "断言失败: \(message)")
    }

    static func entries(_ names: [String], modified: Double? = nil) -> [DownloadFileEntry] {
        names.map { DownloadFileEntry(name: $0, modifiedAt: modified) }
    }

    static func main() {
        testClassification()
        testCountAggregation()
        testFinishedVersusCancelled()
        testStaleLeftoversIgnored()
        testQuantityNeverInvented()
        print("DownloadActivityTests ok")
    }

    static func testClassification() {
        expect(DownloadTempName.finalName(of: "report.pdf.crdownload") == "report.pdf", "Chrome 系")
        expect(DownloadTempName.finalName(of: "report.pdf.download") == "report.pdf", "Safari 包")
        expect(DownloadTempName.finalName(of: "report.pdf.part") == "report.pdf", "Firefox")
        expect(DownloadTempName.finalName(of: "REPORT.PDF.CRDOWNLOAD") == "REPORT.PDF", "后缀不分大小写，文件名原样保留")
        expect(DownloadTempName.finalName(of: "a.part.crdownload") == "a.part", "只剥最外一层")
        for name in ["report.pdf", "notes.txt", "download", "part", "crdownload.pdf", "x.partial", "a.downloaded", ".crdownload", ".part", ".download"] {
            expect(DownloadTempName.finalName(of: name) == nil, "不是临时文件: \(name)")
        }
    }

    static func testCountAggregation() {
        var tracker = DownloadTracker()
        var update = tracker.update(entries(["b.zip.crdownload", "a.iso.download", "c.mp4.part", "done.pdf", "readme.txt"]), now: 100)
        expect(update.active?.count == 3, "三家浏览器各一个，共 3 个")
        expect(update.active?.names == ["a.iso", "b.zip", "c.mp4"], "名字已排序、已去掉后缀")
        expect(update.finished.isEmpty && update.cancelled == 0, "第一次看到不算结束")

        // 两个浏览器下同一个文件，只算一个。
        update = tracker.update(entries(["x.zip.crdownload", "x.zip.part"]), now: 101)
        expect(update.active?.count == 1, "同名只算一个")

        update = tracker.update(entries(["readme.txt"]), now: 102)
        expect(update.active == nil, "没有临时文件就没有活动")
    }

    static func testFinishedVersusCancelled() {
        var tracker = DownloadTracker()
        _ = tracker.update(entries(["a.pdf.crdownload", "b.zip.download", "c.mp4.part"]), now: 10)
        // a 改名成最终文件；b 消失且没有最终文件；c 还在。
        var update = tracker.update(entries(["a.pdf", "c.mp4.part"]), now: 11)
        expect(update.finished == ["a.pdf"], "临时文件没了、同名最终文件在 = 下好了")
        expect(update.cancelled == 1, "临时文件没了、没有最终文件 = 取消")
        expect(update.active?.count == 1 && update.active?.names == ["c.mp4"], "剩下的继续在下")

        // 取消的不会再被重复通知。
        update = tracker.update(entries(["a.pdf", "c.mp4.part"]), now: 12)
        expect(update.finished.isEmpty && update.cancelled == 0, "同一件事只说一次")

        // 全部消失：c 取消，列表里既无临时文件也无最终文件。
        update = tracker.update(entries(["a.pdf"]), now: 13)
        expect(update.active == nil && update.cancelled == 1 && update.finished.isEmpty, "取消时安静收掉")
    }

    static func testStaleLeftoversIgnored() {
        var tracker = DownloadTracker()
        let old = DownloadFileEntry(name: "old.zip.crdownload", modifiedAt: 1_000)
        let fresh = DownloadFileEntry(name: "new.zip.crdownload", modifiedAt: 1_000 + DownloadTracker.staleAfter + 5)
        let now = 1_000 + DownloadTracker.staleAfter + 10
        var update = tracker.update([old, fresh], now: now)
        expect(update.active?.names == ["new.zip"], "启动时就躺着的陈年残留不当成正在下")
        // 残留文件被清掉，不算取消，也不算下好。
        update = tracker.update([fresh], now: now + 1)
        expect(update.finished.isEmpty && update.cancelled == 0, "残留消失不惊动任何人")
        // 启动之后才出现的临时文件，哪怕很久没动也照样算。
        update = tracker.update([fresh, DownloadFileEntry(name: "slow.iso.download", modifiedAt: 0)], now: now + 2)
        expect(update.active?.count == 2, "启动后出现的不按修改时间过滤")
    }

    static func testQuantityNeverInvented() {
        var tracker = DownloadTracker()
        let update = tracker.update(entries(["a.zip.crdownload", "b.zip.part"]), now: 5)
        guard let summary = update.active else { return expect(false, "应有活动") }
        let working = DownloadCard.downloading(summary).activity(id: "source.download", generation: 1, now: 5)
        expect(working.kind == .download, "种类是下载")
        expect(working.progress == .indeterminate, "不知道总量时只画不定长的弧，没有百分比")
        expect(working.expiresAt == nil, "下载中不自己过期")
        expect(working.subtitle == "2 个文件", "只给个数")
        expect(!working.title.contains("a.zip") && !working.subtitle.contains("a.zip"), "收起时不出现文件名")
        expect(working.detail.contains("a.zip") && working.detail.contains("b.zip"), "文件名放在展开才用的 detail 里")

        let done = DownloadCard.finished(["a.zip"]).activity(id: "owned.download.done", generation: 1, now: 6)
        expect(done.title == "下载好了" && done.progress == .unknown, "下好了不画量")
        expect(done.expiresAt == 6 + 4, "下好了的提示几秒后自己消失")

        // 放进 store 里也不会冒出进度。
        var store = NotchActivityStore()
        expect(store.upsert(working, now: 5), "能放进 store")
        expect(store.selected == nil && store.activities.first?.progress == .indeterminate, "store 里没有编出来的百分比")
    }
}
