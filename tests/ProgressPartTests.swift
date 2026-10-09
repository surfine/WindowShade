import Foundation

/// M12 进度零件：量 → 画法映射、数值更新不重排、结束一句、下载与拷贝用新的量、右段格子与右耳同一套。
/// 纯 Foundation，不碰 AppKit 与真机。
@main struct ProgressPartTests {
    typealias Quantity = NotchActivity.Quantity

    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String, line: Int = #line) {
        if !condition { failures += 1; print("FAIL line \(line): \(message)") }
    }

    static func main() {
        mapping()
        earText()
        storeValidity()
        updatesDoNotRelayout()
        sentences()
        downloadUsesQuantity()
        copySnapshot()
        copyTracker()
        copyCards()
        rowCellsShareTheSamePart()
        if failures > 0 { print("FAILED: \(failures)"); exit(1) }
        print("PASS: progress part")
    }

    // MARK: 量 → 画法

    static func mapping() {
        expect(Quantity.fraction(0.42).drawing == .ring, "比例画环")
        expect(Quantity.count(3, 12).drawing == .countText, "个数只写数，不画环")
        expect(Quantity.indeterminate.drawing == .spinningArc, "不知道多少画不确定的弧")
        expect(Quantity.unknown.drawing == .none, "什么都不知道什么都不画")

        expect(Quantity.fraction(0.425).percentText == "43%" || Quantity.fraction(0.425).percentText == "42%", "百分比四舍五入")
        expect(Quantity.fraction(0).percentText == "0%" && Quantity.fraction(1).percentText == "100%", "两端")
        expect(Quantity.count(3, 12).countText == "第 3 / 12", "个数的写法")
        expect(Quantity.count(3, 12).shortCountText == "3/12" && Quantity.fraction(0.5).shortCountText == nil, "放不下时的短写法")
        expect(Quantity.fraction(0.5).countText == nil && Quantity.count(1, 2).percentText == nil, "写法互不串")
        expect(Quantity.indeterminate.percentText == nil && Quantity.unknown.countText == nil, "没有量就没有字")
        expect(Quantity.fraction(0.4).fractionValue == 0.4 && Quantity.count(1, 2).fractionValue == nil, "只有比例有 fractionValue")
        expect(Quantity.reported(nil) == .unknown && Quantity.reported(0.3) == .fraction(0.3), "旧来源的小数")

        // 环 14、线宽 2、底环白 18%；环和弧占右耳宽度，个数和空不占。
        expect(NotchProgressPart.ringDiameter == 14 && NotchProgressPart.ringLineWidth == 2, "环的尺寸")
        expect(NotchProgressPart.trackWhiteAlpha == 0.18, "底环白 18%")
        expect(NotchProgressPart.reservedWidth(for: .ring) == 18 && NotchProgressPart.reservedWidth(for: .spinningArc) == 18, "环和弧占位")
        expect(NotchProgressPart.reservedWidth(for: .countText) == 0 && NotchProgressPart.reservedWidth(for: .none) == 0, "个数和空不占位")
    }

    static func item(_ kind: NotchActivityKind, _ quantity: Quantity, trailing: String? = nil,
                     subtitle: String = "", detail: String = "") -> NotchActivity {
        NotchActivity(id: "x", kind: kind, title: "t", subtitle: subtitle, startedAt: 0, progress: quantity,
                      detail: detail, trailing: trailing)
    }

    static func earText() {
        expect(NotchEarText.trailing(item(.download, .fraction(0.5))) == "50%", "下载比例写 %")
        expect(NotchEarText.trailing(item(.copy, .fraction(0.07))) == "7%", "拷贝比例写 %")
        expect(NotchEarText.trailing(item(.music, .fraction(0.5))) == "", "音乐的比例不写 %（环替代了细条，字还是剩余时间）")
        expect(NotchEarText.trailing(item(.music, .fraction(0.5), trailing: "2:14")) == "2:14", "音乐给了剩余时间就写它")
        expect(NotchEarText.trailing(item(.copy, .count(3, 12))) == "3/12", "只有个数：右耳写短写法“3/12”（《实时活动晋级》表：“42%”或“3/7”）")
        expect(NotchEarText.trailing(item(.download, .indeterminate, subtitle: "2 个文件")) == "2 个文件", "不确定：退回副句，不编数")
        expect(NotchEarText.trailing(item(.download, .unknown, subtitle: "2 个文件")) == "2 个文件", "不知道：退回副句")
        expect(NotchEarText.trailing(item(.download, .fraction(0.5), trailing: "还剩 1 分")) == "还剩 1 分", "来源给的字优先")
    }

    // MARK: store

    static func storeValidity() {
        var store = NotchActivityStore()
        func put(_ id: String, _ q: Quantity) -> Bool {
            store.upsert(NotchActivity(id: id, generation: 1, kind: .copy, title: "t", startedAt: 0, progress: q), now: 0)
        }
        expect(put("a", .fraction(0)) && put("b", .fraction(1)), "0 和 1 合法")
        expect(!put("c", .fraction(-0.1)) && !put("d", .fraction(1.1)) && !put("e", .fraction(.nan)), "越界与 NaN 拒绝")
        expect(put("f", .count(1, 1)) && put("g", .count(3, 12)), "个数合法")
        expect(!put("h", .count(0, 5)) && !put("i", .count(6, 5)) && !put("j", .count(1, 0)), "个数越界拒绝")
        expect(put("k", .indeterminate) && put("l", .unknown), "不确定与不知道合法")
        // 旧写法 progress: Double? 仍然能用。
        let legacy = NotchActivity(id: "m", generation: 1, kind: .music, title: "t", startedAt: 0, progress: 0.25)
        let none = NotchActivity(id: "n", generation: 1, kind: .music, title: "t", startedAt: 0, progress: nil)
        expect(legacy.progress == .fraction(0.25) && none.progress == .unknown, "旧写法对应新的量")
        expect(NotchActivity(id: "o", kind: .music, title: "t", startedAt: 0).progress == .unknown, "默认是不知道")
    }

    // MARK: 数值更新不重排

    static func updatesDoNotRelayout() {
        var model = NotchProgressPart.Model()
        expect(model.apply(.unknown) == .none && model.layoutPasses == 0, "起点就是不知道，不算重排")
        expect(model.apply(.fraction(0)) == .relayout, "第一次出现环要排一次")
        var valueOnly = 0
        for step in 1...100 where model.apply(.fraction(Double(step) / 100)) == .valueOnly { valueOnly += 1 }
        expect(valueOnly == 100 && model.layoutPasses == 1, "一百次数值更新只改数和终点，总共只排过一次（\(model.layoutPasses)）")
        expect(model.apply(.fraction(1)) == .none, "同一个量重复来什么都不做")
        expect(model.apply(.indeterminate) == .relayout && model.layoutPasses == 2, "环变弧：画法变了才重排")
        expect(model.apply(.indeterminate) == .none, "弧一直转，重复来不重启")
        expect(model.apply(.count(1, 3)) == .relayout, "弧变个数：重排")
        expect(model.apply(.count(2, 3)) == .valueOnly && model.apply(.count(3, 3)) == .valueOnly, "个数往前走只改数")
        expect(model.layoutPasses == 3, "全程 3 次重排：环、弧、个数")
        expect(model.apply(.unknown) == .relayout && model.quantity == .unknown, "收掉也是一次重排")
    }

    // MARK: 结束一句

    static func sentences() {
        let copy = NotchSentence.progressDone(.copy, names: ["年度报告.pdf"])
        expect(copy.headline == "拷好了" && copy.detail == "年度报告.pdf", "拷好了，副句是文件名")
        let download = NotchSentence.progressDone(.download, names: ["a.iso"])
        expect(download.headline == "下载好了" && download.detail == "a.iso", "下载好了")
        let long = String(repeating: "很长的名字", count: 10) + ".pdf"
        let cut = NotchSentence.progressDone(.copy, names: [long])
        expect(cut.detail.count == NotchSentence.detailLimit && cut.detail.contains("…"), "文件名超长从中间截断")
        expect(cut.detail.hasPrefix("很长") && cut.detail.hasSuffix(".pdf"), "头尾都在，扩展名留着")
        expect(NotchSentence.progressDone(.copy, names: ["a", "b", "c"]).detail == "3 个文件", "几个文件写个数")
        expect(NotchSentence.progressDone(.copy, names: []).detail.isEmpty, "没有名字不编")
        let failed = NotchSentence.progressFailed(.copy, reason: "中途停了")
        expect(failed.headline == "没拷完" && failed.detail == "中途停了", "没拷完加原因")
        expect(NotchSentence.progressFailed(.download, reason: nil).headline == "没下完" && NotchSentence.progressFailed(.download, reason: nil).detail.isEmpty,
               "没有原因不编")
        for work in [NotchSentence.ProgressWork.copy, .download] {
            expect(work.doneHeadline.count <= NotchSentence.headlineLimit && work.failedHeadline.count <= NotchSentence.headlineLimit, "主句不超过 8 个字")
        }
    }

    // MARK: 下载

    static func downloadUsesQuantity() {
        let unknownTotal = DownloadCard.downloading(DownloadSummary(count: 2, names: ["a.zip", "b.zip"]))
        expect(unknownTotal.quantity == .indeterminate, "没有总量：不确定的弧")
        let known = DownloadCard.downloading(DownloadSummary(count: 1, names: ["a.zip"], fraction: 0.4))
        expect(known.quantity == .fraction(0.4), "有总量：比例")
        expect(DownloadCard.downloading(DownloadSummary(count: 1, names: ["a.zip"], fraction: 1.5)).quantity == .indeterminate, "越界的总量不信")
        expect(DownloadCard.downloading(DownloadSummary(count: 1, names: ["a.zip"], fraction: .nan)).quantity == .indeterminate, "NaN 不信")
        let activity = known.activity(id: "source.download", generation: 1, now: 5)
        expect(activity.progress == .fraction(0.4) && activity.expiresAt == nil, "卡片带着量")
        var store = NotchActivityStore()
        expect(store.upsert(unknownTotal.activity(id: "source.download", generation: 1, now: 5), now: 5), "不确定的下载能放进 store")

        let done = DownloadCard.finished(["report.pdf"])
        expect(done.title == "下载好了" && done.subtitle == "report.pdf" && done.quantity == .unknown, "下好了：副句是文件名，不画量")
        expect(done.detail.isEmpty, "全名已经在副句里，不再重复")
        let many = DownloadCard.finished(["a", "b"])
        expect(many.subtitle == "2 个文件" && many.detail == "a、b", "几个文件")
        let longName = String(repeating: "x", count: 40) + ".dmg"
        let longDone = DownloadCard.finished([longName])
        expect(longDone.subtitle.count == NotchSentence.detailLimit && longDone.detail == longName, "名字被截短时全名留在展开用的 detail 里")
        expect(done.lifetime == 4, "几秒后自己消失")
    }

    // MARK: 拷贝

    static func copySnapshot() {
        expect(CopyProgressSnapshot(fractionCompleted: 0.25, completedUnitCount: 25, totalUnitCount: 100).quantity == .fraction(0.25), "有总量用比例")
        expect(CopyProgressSnapshot(fractionCompleted: 1.7, completedUnitCount: 170, totalUnitCount: 100).quantity == .fraction(1), "比例夹在 0…1")
        expect(CopyProgressSnapshot(totalUnitCount: 0, fileCompletedCount: 2, fileTotalCount: 5).quantity == .count(3, 5),
               "没有总量、知道几个：写第几个，共几个")
        expect(CopyProgressSnapshot(isIndeterminate: true, fileCompletedCount: 9, fileTotalCount: 9).quantity == .count(9, 9), "不会超过总数")
        expect(CopyProgressSnapshot(totalUnitCount: 0).quantity == .indeterminate, "什么都不知道：画不确定的弧")
        expect(CopyProgressSnapshot(fractionCompleted: .nan, completedUnitCount: 1, totalUnitCount: 10).quantity == .indeterminate, "NaN 不画比例")
        expect(CopyProgressSnapshot(totalUnitCount: 0, fileCompletedCount: 0, fileTotalCount: 1).quantity == .indeterminate, "只有一个文件不写“第 1 / 1”")
        expect(CopyProgressSnapshot(completedUnitCount: 10, totalUnitCount: 10).isComplete, "做完的数目相等")
        expect(!CopyProgressSnapshot(fractionCompleted: 0.5, completedUnitCount: 5, totalUnitCount: 10).isComplete, "没做完")
        expect(CopyProgressTracker.outcome(final: CopyProgressSnapshot(fractionCompleted: 1, completedUnitCount: 10, totalUnitCount: 10), cancelled: false) == .completed, "拷好了")
        expect(CopyProgressTracker.outcome(final: CopyProgressSnapshot(fractionCompleted: 0.3, completedUnitCount: 3, totalUnitCount: 10), cancelled: true) == .cancelled, "用户取消")
        expect(CopyProgressTracker.outcome(final: CopyProgressSnapshot(fractionCompleted: 0.3, completedUnitCount: 3, totalUnitCount: 10), cancelled: false) == .interrupted, "中途停了")
    }

    static func snap(_ fraction: Double, name: String? = "a.mov") -> CopyProgressSnapshot {
        CopyProgressSnapshot(fractionCompleted: fraction, completedUnitCount: Int64(fraction * 100), totalUnitCount: 100, name: name)
    }

    static func copyTracker() {
        var tracker = CopyProgressTracker()
        var update = tracker.update(id: 1, snapshot: snap(0.1))
        expect(update.active?.count == 1 && update.active?.name == "a.mov" && update.active?.quantity == .fraction(0.1), "一件在拷")
        update = tracker.update(id: 1, snapshot: snap(0.6))
        expect(update.active?.quantity == .fraction(0.6) && update.finished.isEmpty, "数变了")
        update = tracker.update(id: 2, snapshot: snap(0.2, name: "b.mov"))
        expect(update.active?.count == 2 && update.active?.name == nil && update.active?.quantity == .indeterminate, "几件同时拷：不合成一个比例")
        update = tracker.end(id: 1, outcome: .completed, final: snap(1))
        expect(update.finished == ["a.mov"] && update.active?.count == 1 && update.active?.name == "b.mov", "一件拷好了")
        update = tracker.end(id: 2, outcome: .cancelled, final: nil)
        expect(update.active == nil && update.finished.isEmpty && update.failed.isEmpty, "用户取消：安静收掉")
        _ = tracker.update(id: 3, snapshot: snap(0.4, name: "c.mov"))
        update = tracker.end(id: 3, outcome: .interrupted, final: nil)
        expect(update.failed == [CopyFailure(name: "c.mov", reason: "中途停了")] && update.active == nil, "中途停了")
        update = tracker.end(id: 99, outcome: .completed, final: nil)
        expect(update.finished.isEmpty && update.failed.isEmpty, "没见过的编号什么都不说")
        for id in 100..<140 { _ = tracker.update(id: id, snapshot: snap(0.1, name: "n\(id)")) }
        expect(tracker.update(id: 500, snapshot: snap(0.1)).active?.count == CopyProgressTracker.capacity, "同时记的件数有上限")
        tracker.reset()
        expect(tracker.update(id: 7, snapshot: snap(0.5)).active?.count == 1, "清掉以后重新开始")
    }

    static func copyCards() {
        let one = CopyCard.copying(CopyActiveSummary(count: 1, name: "a.mov", quantity: .fraction(0.3)))
        expect(one.title == "正在拷贝" && one.subtitle == "a.mov" && one.symbol == "doc.on.doc" && one.lifetime == nil, "拷贝卡")
        let activity = one.activity(id: "source.copy", generation: 1, now: 3)
        expect(activity.kind == .copy && activity.progress == .fraction(0.3) && activity.expiresAt == nil, "拷贝活动带着量")
        expect(CopyCard.copying(CopyActiveSummary(count: 3, name: nil, quantity: .indeterminate)).subtitle == "3 项", "几件在拷")
        let done = CopyCard.finished(["a.mov"])
        expect(done.title == "拷好了" && done.subtitle == "a.mov" && done.quantity == .unknown && done.lifetime == 4, "拷好了")
        let failed = CopyCard.failed(CopyFailure(name: "a.mov", reason: CopyProgressTracker.interruptedReason))
        expect(failed.title == "没拷完" && failed.subtitle == "中途停了" && failed.quantity == .unknown, "没拷完加原因")
        expect(NotchActivityKind.copy.writesPercent && NotchActivityKind.copy.priority == NotchActivityKind.download.priority, "拷贝和下载同一档")
        var store = NotchActivityStore()
        expect(store.upsert(activity, now: 3) && store.activities.first?.progress == .fraction(0.3), "拷贝活动能放进 store")
    }

    // MARK: 右段的格子与右耳同一套

    static func rowCellsShareTheSamePart() {
        let download = NotchActivity(id: "source.download", kind: .download, title: "正在下载", subtitle: "1 个文件",
                                     symbol: "arrow.down.circle", startedAt: 0, progress: .fraction(0.42))
        let copying = NotchActivity(id: "source.copy", kind: .copy, title: "正在拷贝", symbol: "doc.on.doc",
                                    startedAt: 1, progress: .count(2, 9))
        let unknown = NotchActivity(id: "source.download2", kind: .download, title: "正在下载", symbol: "arrow.down.circle",
                                    startedAt: 2, progress: .indeterminate)
        let music = NotchActivity(id: "source.music", kind: .music, title: "September", symbol: "music.note",
                                  startedAt: 3, progress: .fraction(0.5))
        let cells = NotchRow.ongoingCells(from: [download, copying, unknown, music])
        expect(cells.count == 3, "右段最多 3 格")
        expect(cells[0].quantity == .fraction(0.42) && cells[0].quantityDrawing == .ring && cells[0].quantityText == "42%", "下载格：环加百分比")
        expect(cells[1].quantityDrawing == .countText && cells[1].quantityText == "第 2 / 9", "拷贝格：只写第几个")
        expect(cells[2].quantityDrawing == .spinningArc && cells[2].quantityText == nil, "不确定：弧，没有字")
        // 格子上的画法就是右耳上的画法。
        for (cell, source) in zip(cells, [download, copying, unknown]) {
            expect(cell.quantityDrawing == source.progress.drawing, "格子和右耳画法一致")
            expect(cell.quantityText == source.progress.valueText(writesPercent: source.kind.writesPercent), "格子和右耳的字一致")
        }
        expect(!cells[0].spoken.contains("%") && cells[0].spoken == "正在下载，1 个文件", "读屏的句子不随进度每次变（量放进读屏的“值”）")
        let focus = NotchActivity(id: "ws2.focus", kind: .focus, title: "专注", symbol: "timer", startedAt: 0, progress: .fraction(0.3), trailing: "18 分")
        expect(NotchRow.ongoingCells(from: [focus])[0].quantityDrawing == .none, "番茄钟的圈在左耳，格子里不再画")
        let withMusic = NotchRow.ongoingCells(from: [music])
        expect(withMusic[0].quantityText == nil && withMusic[0].quantityDrawing == .ring, "音乐在格子里有环、不写 %")
        expect(withMusic[0].spoken == "September，正在播放", "音乐读屏不变")
    }
}
