import Cocoa

/// FS-04 文件架卡的画面接线：尺寸照稿，格子按清单摆，键盘就能选、预览以外的动作都走得通，
/// 输入权被撤销后一律不响应，真刘海时右耳的按钮在视图上沿以外也点得到。
/// 纯逻辑在 tests/run-file-shelf-card-tests.sh；这里编的是整个 App 模块（要 AppKit，不要图形会话里的真屏幕）。
@main enum FileShelfCardViewTests {
    @MainActor static func main() async {
        _ = NSApplication.shared
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            if condition { print("ok   \(label)") } else { failures += 1; print("FAIL \(label)") }
        }
        func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], characters: String = "") -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                             characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        func wait(_ seconds: Double = 3, until done: () -> Bool) {
            let end = Date().addingTimeInterval(seconds)
            while !done(), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        }

        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("fileshelf-view-\(UUID().uuidString)", isDirectory: true)
        let files = tmp.appendingPathComponent("files", isDirectory: true)
        try? fm.createDirectory(at: files, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let urls = (1...3).map { files.appendingPathComponent("文件\($0).txt") }
        for url in urls { try? Data("x".utf8).write(to: url) }

        print("CASE FS04-V01 | 尺寸照稿：真刘海内容高 126.5，没有刘海整张 160")
        let store = FileShelfStore(root: tmp.appendingPathComponent("shelf"), undoDelay: 5, isEnabled: { true })
        let controller = FileShelfController(store: store)
        controller.start()
        let real = FileShelfView(controller: controller, hasNotch: true, strip: 33.5)
        let virtual = FileShelfView(controller: controller, hasNotch: false, strip: 33.5)
        expect(real.interactionSize == NSSize(width: 560, height: 126.5), "真刘海 560 × (160 − 33.5)")
        expect(virtual.interactionSize == NSSize(width: 560, height: 160), "没有刘海 560 × 160")

        print("CASE FS04-V02 | 格子按清单摆：最新的在最左，名字和读屏")
        store.add(urls: [urls[0]]); store.flush()
        store.add(urls: [urls[1]]); store.flush()
        store.add(urls: [urls[2]]); store.flush()
        wait { controller.rows.count == 3 }
        expect(controller.rows.count == 3 && controller.rows[0].entry.name == "文件3.txt", "清单到了，最新的在最前")
        expect(controller.cell?.title == "文件架 · 3", "末格写“文件架 · 3”")
        expect(controller.cellArt().count == 3, "一排里叠三张图")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 300))
        real.frame = NSRect(x: 0, y: 40, width: 560, height: 126.5)
        container.addSubview(real)
        real.rowsChanged()
        real.layoutSubtreeIfNeeded()
        let tiles = real.subviewsRecursive.compactMap { $0 as? FileShelfTileView }.sorted { $0.frame.minX < $1.frame.minX }
        expect(tiles.count == 3, "三格")
        expect(tiles.map { $0.row.entry.name } == ["文件3.txt", "文件2.txt", "文件1.txt"], "最新的在左")
        expect(tiles.first?.frame.size == NSSize(width: 76, height: 104) && tiles.first?.frame.minX == 14, "76 × 104，边距 14")
        expect(tiles[1].frame.minX - tiles[0].frame.minX == 84, "格间 8")
        expect(tiles.first?.accessibilityLabel() == "文件3.txt，文件架", "读屏念“文件3.txt，文件架”")
        let actions = tiles.first?.accessibilityCustomActions()?.map(\.name) ?? []
        expect(actions == ["大图预览", "隔空投送", "移出文件架"], "读屏动作齐：大图预览、隔空投送、移出文件架")
        expect(tiles.first.map { real.scrollFrame.minY == 8 && $0.frame.height == 104 } == true, "真刘海：格子从视图上沿下 8 点开始")
        let noNotch = FileShelfView(controller: controller, hasNotch: false, strip: 33.5)
        noNotch.frame = NSRect(x: 0, y: 0, width: 560, height: 160)
        container.addSubview(noNotch)
        noNotch.rowsChanged()
        noNotch.layoutSubtreeIfNeeded()
        expect(noNotch.scrollFrame.minY == 41.5, "没有刘海：格子从 41.5 开始")

        print("CASE FS04-V03 | 真刘海：右耳的按钮在视图上沿以外，点击靠 hitTest 转给它们")
        let air = real.subviewsRecursive.compactMap { $0 as? FileShelfPill }.first { $0.accessibilityLabel() == "隔空投送" }
        let clear = real.subviewsRecursive.compactMap { $0 as? FileShelfPill }.first { $0.accessibilityLabel() == "全部移出" }
        expect(air != nil && clear != nil, "右耳有“隔空投送”“全部移出”")
        if let clear {
            let inRealSpace = real.convert(NSPoint(x: clear.frame.midX, y: clear.frame.midY), from: clear.superview)
            expect(inRealSpace.y < 0, "按钮在视图上沿以外（刘海那一条里）")
            let hit = real.hitTest(real.convert(inRealSpace, to: container))
            expect(hit === clear, "点那里命中按钮")
            let blank = real.hitTest(real.convert(NSPoint(x: 5, y: -2), to: container))
            expect(blank == nil || blank === real.header, "刘海条里没有按钮的地方不吃点击（或只落在耳朵条上）")
        }

        print("CASE FS04-V04 | 键盘：→ 选格，Delete 移出，⌘Z 撤销，Esc 收卡；输入权撤销后不响应")
        var cancelled = 0
        real.onCancel = { cancelled += 1 }
        real.inputIsCurrent = { true }
        real.keyDown(with: key(124))
        expect(tiles[0].focused, "→ 选到最新的一格")
        real.keyDown(with: key(124))
        expect(tiles[1].focused && !tiles[0].focused, "再 → 选下一格")
        real.keyDown(with: key(51))
        store.flush()
        wait { controller.rows.count == 2 }
        expect(controller.rows.count == 2 && !controller.rows.contains { $0.entry.name == "文件2.txt" }, "Delete：移出文件架")
        expect(fm.fileExists(atPath: urls[1].path), "原文件不动")
        let handled = real.performKeyEquivalent(with: key(6, flags: .command, characters: "z"))
        store.flush()
        wait { controller.rows.count == 3 }
        expect(handled && controller.rows.count == 3, "⌘Z：放回来")
        real.cancelOperation(nil)
        expect(cancelled == 1, "Esc：收卡")
        real.inputIsCurrent = { false }
        real.keyDown(with: key(124)); real.keyDown(with: key(51))
        _ = real.performKeyEquivalent(with: key(6, flags: .command, characters: "z"))
        store.flush()
        expect(controller.rows.count == 3, "输入权被撤销后不响应")
        real.inputIsCurrent = { true }

        print("CASE FS04-V05 | 全部移出：留“文件架空了”和“撤销”，撤销放回")
        controller.removeAll()
        store.flush()
        wait { controller.rows.isEmpty }
        real.rowsChanged()
        expect(controller.clear.isPending(at: controller.now), "5 秒内可以撤销")
        expect(real.subviewsRecursive.contains { ($0 as? NSTextField)?.stringValue == "文件架空了" && !$0.isHidden }, "卡上写“文件架空了”")
        expect(fm.fileExists(atPath: urls[0].path) && fm.fileExists(atPath: urls[2].path), "原文件不动")
        controller.undo()
        store.flush()
        wait { controller.rows.count == 3 }
        expect(controller.rows.count == 3 && !controller.clear.isPending(at: controller.now), "撤销：三格回来")

        print("CASE FS04-V06 | 右键清单与关掉即清空")
        if let tile = tiles.first {
            let menu = real.contextMenu(for: tile)
            expect(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["打开", "用哪个 App 打开", "在访达中显示", "隔空投送", "移出文件架"],
                   "右键：打开、用哪个 App 打开、在访达中显示、隔空投送、移出文件架")
        }
        controller.setEnabled(false)
        store.flush()
        expect(controller.rows.isEmpty && controller.cell == nil, "关掉：清空，末格不在")
        FileShelf.enabled = true
        let image = FileShelfView.dragImage(art: NSImage(size: NSSize(width: 20, height: 20)), count: 5)
        expect(image.size.width > 52, "拖出预览带个数角标")

        print(failures == 0 ? "PASS FileShelfCardViewTests" : "FAIL FileShelfCardViewTests: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}

extension NSView {
    var subviewsRecursive: [NSView] { subviews + subviews.flatMap(\.subviewsRecursive) }
}
