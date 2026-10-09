import Foundation

// FS-04：文件架卡的纯逻辑——那一排的末格、拖出拷贝 / ⌘ 移动、全部移出撤销、失效格、右键与读屏动作。
// 画面（FileShelfView）在 AppKit 那一层，由整模块检查和真机验收看。

@main
struct FileShelfCardTests {
    @MainActor static func main() {
        var t = TestSuite("FS-04")

        // MARK: 一排右段的末格

        t.section("FS04-01", "末格出现条件：空着或关着不在")
        t.expect(NotchRow.fileShelfCell(count: 0, enabled: true) == nil, "空着时这一格不在")
        t.expect(NotchRow.fileShelfCell(count: 6, enabled: false) == nil, "关着时这一格不在")
        t.expect(NotchRow.fileShelfCell(count: -1, enabled: true) == nil, "负数当空着")
        let cell = NotchRow.fileShelfCell(count: 6, enabled: true)
        t.expect(cell?.title == "文件架 · 6", "写“文件架 · 6”")
        t.expect(cell?.stacked == 3 && NotchRow.fileShelfCell(count: 2, enabled: true)?.stacked == 2
                 && NotchRow.fileShelfCell(count: 1, enabled: true)?.stacked == 1,
                 "叠三张缩略图，不够就有几张叠几张")
        t.expect(cell?.spoken == "文件架，6 个", "读屏念“文件架，6 个”")

        t.section("FS04-02", "末格在右段最后，不算进“最多 3 件”，放不下先被裁掉")
        t.expect(NotchRow.fit(windows: 2, ongoing: 3, room: 2000) == NotchRow.Layout(windows: 2, ongoing: 3),
                 "没有末格：行为不变（右段最多 3）")
        t.expect(NotchRow.fit(windows: 0, ongoing: 9, room: 2000) == NotchRow.Layout(windows: 0, ongoing: 3), "没有末格时仍裁成 3")
        t.expect(NotchRow.fit(windows: 2, ongoing: 4, room: 2000, tail: true) == NotchRow.Layout(windows: 2, ongoing: 4),
                 "三件加末格：多放一格，共 4")
        t.expect(NotchRow.fit(windows: 2, ongoing: 9, room: 2000, tail: true) == NotchRow.Layout(windows: 2, ongoing: 4),
                 "有末格时右段最多 4")
        t.expect(NotchRow.fit(windows: 0, ongoing: 1, room: 2000, tail: true) == NotchRow.Layout(windows: 0, ongoing: 1),
                 "只有文件架：自己一格，没有竖线")
        t.expect(NotchRow.fit(windows: 3, ongoing: 1, room: 2000, tail: true).hasDivider, "窗口加文件架：中间有竖线")
        let tight = NotchRow.fit(windows: 8, ongoing: 4, room: 600, tail: true)
        t.expect(tight == NotchRow.Layout(windows: 2, ongoing: 2), "600 宽：右段至多一半（其余由 prefix 从后面裁，末格最先没）")
        t.expect(NotchRow.fileShelfActivityID == "fileShelf" && NotchRow.fileShelfSymbol == "tray.full", "编号用的活动号与符号")

        // MARK: 卡的尺寸（稿里的数字）

        t.section("FS04-03", "卡 560×160、圆角 28；格 76×104、缩略图 52、间隔 8、边距 14")
        typealias L = FileShelfCardLayout
        t.expect(L.width == 560 && L.height == 160 && L.radius == 28, "560 × 160，圆角 28")
        t.expect(L.tileWidth == 76 && L.tileHeight == 104 && L.thumbnail == 52 && L.thumbnailRadius == 12 && L.tileRadius == 14,
                 "格与缩略图的数字")
        t.expect(L.leaveDelay == 0.3 && L.clearHold == 5, "离开 0.3 秒收回；全部移出留 5 秒")
        t.expect(L.tilesTop(hasNotch: false) == 41.5, "没有刘海：格子从 41.5 开始（稿里 top:41.5）")
        t.expect(L.tilesTop(hasNotch: true) == 8, "真刘海：视图在刘海下面，只剩 8")
        t.expect(L.contentHeight(hasNotch: true) + L.referenceStrip == L.height, "刘海条加内容高 = 160")
        t.expect(L.tilesTop(hasNotch: true) + L.tileHeight + 14.5 == L.contentHeight(hasNotch: true), "格子下面空 14.5，和稿一致")
        t.expect(L.tileX(0) == 14 && L.tileX(1) == 98, "最新的在最左，一格 84")
        t.expect(L.visibleTiles > 6 && L.visibleTiles < 7, "一屏放六格多")
        t.expect(L.documentWidth(count: 0) == 560 && L.documentWidth(count: 3) == 560
                 && L.documentWidth(count: 24) == 2 * 14 + 24 * 76 + 23 * 8,
                 "文档宽：少了不缩，多了横着滑")
        t.expect(L.scrollOffset(toReveal: 0, current: 300) == 0 && L.scrollOffset(toReveal: 10, current: 0) > 0
                 && L.scrollOffset(toReveal: 2, current: 0) == 0, "键盘选到哪格就滚到看得全")

        // MARK: 名字

        t.section("FS04-04", "名字最多两行，中间省略，保留扩展名")
        t.expect(FileShelfTileName.display("报价单.pdf") == "报价单.pdf", "短名字原样")
        let long = FileShelfTileName.display("2026年第三季度销售数据汇总与分析报告终稿.pdf")
        t.expect(long.hasSuffix(".pdf") && long.contains("…") && FileShelfTileName.width(of: long) <= FileShelfTileName.units + 1,
                 "长名字中间省略并留扩展名（\(long)）")
        let latin = FileShelfTileName.display("Screenshot 2026-10-09 at 14.20.33.png")
        t.expect(latin.hasSuffix(".png") && latin.hasPrefix("Screen") && latin.contains("…"), "西文长名字（\(latin)）")
        let noExt = FileShelfTileName.display("一个没有扩展名但是很长很长很长的文件夹名字")
        t.expect(noExt.contains("…") && FileShelfTileName.width(of: noExt) <= FileShelfTileName.units + 1, "没有扩展名也省略（\(noExt)）")
        t.expect(FileShelfTileName.display(".gitignore_but_a_really_long_hidden_file_name").contains("…"), "点开头的不当扩展名")
        t.expect(FileShelfTileName.stale("报价单终稿版本.pdf", reason: "在废纸篓里").hasSuffix("\n在废纸篓里"), "灰格：名字一行，下面写原因")
        t.expect(FileShelfTileName.stale("a.txt", reason: "硬盘没接上") == "a.txt\n硬盘没接上", "短名字不省略")

        // MARK: 拖出

        t.section("FS04-05", "拖出：默认拷贝，按住 ⌘ 移动；只有移动才让这一格离开")
        t.expect(FileShelfDrag.allowed(command: false) == [.copy], "不按 ⌘：只给拷贝")
        t.expect(FileShelfDrag.allowed(command: true) == [.move], "按住 ⌘：只给移动")
        t.expect(!FileShelfDrag.leavesShelf(after: .copy), "拷贝：这一格留着")
        t.expect(FileShelfDrag.leavesShelf(after: .move), "移动：这一格离开")
        t.expect(!FileShelfDrag.leavesShelf(after: nil), "没落下（取消、落空）：留着")
        t.expect(FileShelfDrag.canDrag(live: true), "可用的格能拖")
        t.expect([FileShelfAvailability.inTrash, .volumeOffline, .missing].allSatisfy { !FileShelfDrag.canDrag(live: $0 == .available) },
                 "灰着的格拖不出来")

        // MARK: 全部移出撤销

        t.section("FS04-06", "全部移出：留 5 秒撤销，过了收卡")
        var clear = FileShelfClearUndo()
        t.expect(!clear.isPending(at: 0), "没移过就没有撤销")
        clear.begin(count: 0, now: 10)
        t.expect(!clear.isPending(at: 10), "空架子全部移出什么也不留")
        clear.begin(count: 6, now: 10)
        t.expect(clear.isPending(at: 10) && clear.isPending(at: 14.9) && !clear.isPending(at: 15), "5 秒内有撤销，到 5 秒就没了")
        t.expect(FileShelfClearUndo.line == "文件架空了" && FileShelfClearUndo.undoTitle == "撤销", "卡上写“文件架空了”和“撤销”")
        var early = clear
        t.expect(!early.expire(at: 14), "没到时间不收卡")
        var undone = clear
        t.expect(undone.undo(at: 12) == 6 && !undone.isPending(at: 12), "时间内撤销：6 个回来，只能撤一次")
        t.expect(undone.undo(at: 12) == nil, "撤销过就没有第二次")
        var late = clear
        t.expect(late.undo(at: 15.5) == nil, "过了时间撤不了")
        t.expect(clear.expire(at: 15) && !clear.isPending(at: 11), "到时间：收卡，记录清掉")

        // 和真的存取接上：全部移出 → 撤销，原文件不动。
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("fileshelf-card-\(UUID().uuidString)", isDirectory: true)
        let files = tmp.appendingPathComponent("files", isDirectory: true)
        try? fm.createDirectory(at: files, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let store = FileShelfStore(root: tmp.appendingPathComponent("shelf"), undoDelay: 0.3, isEnabled: { true })
        store.start()
        let a = files.appendingPathComponent("a.txt"), b = files.appendingPathComponent("b.txt")
        try? Data("a".utf8).write(to: a)
        try? Data("b".utf8).write(to: b)
        store.add(urls: [a, b]); store.flush()
        store.addText("一段文字"); store.flush()
        t.expect(store.snapshot().rows.count == 3, "放了三格")
        store.removeAll(); store.flush()
        t.expect(store.snapshot().rows.isEmpty && fm.fileExists(atPath: a.path) && fm.fileExists(atPath: b.path),
                 "全部移出：架子空了，原文件不动")
        store.undoRemove(); store.flush()
        t.expect(store.snapshot().rows.count == 3, "撤销：三格回来")
        t.expect(store.snapshot().rows.first?.entry.name == "一段文字", "回到原来的位置（最新的在最前）")
        store.removeAll(); store.flush()
        Thread.sleep(forTimeInterval: 0.6); store.flush()
        let taken = tmp.appendingPathComponent("shelf/拿来的")
        t.expect(((try? fm.contentsOfDirectory(atPath: taken.path)) ?? []).isEmpty, "撤销时间过了：拿来的文字才真的删")
        store.undoRemove(); store.flush()
        t.expect(store.snapshot().rows.count == 2, "过了时间再撤：拿来的那一格已经没了，只回来两个文件")
        store.stop(); store.flush()

        // MARK: 失效格与动作

        t.section("FS04-07", "失效格：灰着写原因，只能移出")
        let live = FileShelfActions.menu(isStack: false, live: true)
        t.expect(live.map(\.title) == ["打开", "用哪个 App 打开", "在访达中显示", "隔空投送", "移出文件架"] && live.allSatisfy(\.enabled),
                 "右键：打开、用哪个 App 打开、在访达中显示、隔空投送、移出文件架")
        for state in [FileShelfAvailability.inTrash, .volumeOffline, .missing] {
            let items = FileShelfActions.menu(isStack: false, live: state == .available)
            t.expect(items.filter(\.enabled).map(\.action) == [.remove], "\(state.label ?? "")：只有“移出文件架”能点")
        }
        t.expect(FileShelfActions.menu(isStack: true, live: true).first { $0.action == .openWith }?.enabled == false,
                 "一叠不能“用哪个 App 打开”")
        t.expect(FileShelfActions.spokenActions(live: true).map(\.title) == ["大图预览", "隔空投送", "移出文件架"],
                 "读屏动作：大图预览、隔空投送、移出文件架")
        t.expect(FileShelfActions.spokenActions(live: false).map(\.title) == ["移出文件架"], "灰着的格读屏只剩移出")
        t.expect(FileShelfActions.spoken(name: "报价单.pdf", reason: FileShelfAvailability.available.label) == "报价单.pdf，文件架", "每格念“报价单.pdf，文件架”")
        t.expect(FileShelfActions.spoken(name: "报价单.pdf", reason: FileShelfAvailability.inTrash.label) == "报价单.pdf，在废纸篓里，文件架", "灰着的写上原因")
        t.expect(FileShelfActions.cardSpoken(count: 6) == "文件架，6 个" && FileShelfActions.cardSpoken(count: 0) == "文件架空了", "卡的读屏")
        t.expect(FileShelfActions.removedSpoken("a.txt") == "已移出文件架，a.txt", "移出后念一句")
        t.expect(FileShelfAvailability.volumeOffline.label == "硬盘没接上" && FileShelfAvailability.inTrash.label == "在废纸篓里",
                 "原因的说法沿用模型里的")

        t.finish()
    }
}
