// FS-01 / FS-02：文件架模型与存取。
import Foundation

@main
struct FileShelfTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ c: Bool, _ m: String) {
        if c { print("ok   \(m)") } else { failures += 1; print("FAIL \(m)") }
    }

    static func member(_ n: Int, vol: String = "V1", folder: Bool = false) -> FileShelfMember {
        FileShelfMember(name: "f\(n).txt", path: "/tmp/f\(n).txt", isFolder: folder, bookmark: Data([1]),
                        identity: FileShelfIdentity(volume: vol, fileID: UInt64(n)))
    }

    static func main() {
        modelTests()
        storeTests()
        if failures > 0 { print("\(failures) 项失败"); exit(1) }
        print("全部通过")
    }

    static func modelTests() {
        // 改名后仍认得：同一个磁盘 + 文件编号，名字路径不同，不放两份，原来那格挪到最前。
        var m = FileShelfModel()
        _ = m.add(files: [member(1)])
        _ = m.add(files: [member(2)])
        var renamed = member(1)
        renamed.name = "新名字.txt"; renamed.path = "/tmp/新名字.txt"
        let o = m.add(files: [renamed])
        expect(o.accepted && o.added.isEmpty && o.bumped.count == 1, "改名后仍认得同一个（不添加，只挪前）")
        expect(m.items.count == 2 && m.items[0].members[0].identity?.fileID == 1, "挪到最前、个数不变")
        // 不同磁盘同编号不是同一个。
        _ = m.add(files: [member(1, vol: "V2")])
        expect(m.items.count == 3, "编号相同但磁盘不同算两个")

        // 4 个分开，5 个叠。
        var a = FileShelfModel()
        let o4 = a.add(files: (10..<14).map { member($0) })
        expect(o4.added.count == 4 && a.items.count == 4 && a.items.allSatisfy { $0.kind == .file }, "4 个分开")
        var b = FileShelfModel()
        let o5 = b.add(files: (10..<15).map { member($0) })
        expect(o5.added.count == 1 && b.items.count == 1 && b.items[0].kind == .stack && b.items[0].itemCount == 5, "5 个叠成一格")
        expect(b.items[0].name == "5 个文件", "叠放名字")
        // 一叠最多 999。
        var big = FileShelfModel()
        _ = big.add(files: (0..<1500).map { member($0) })
        expect(big.items.count == 2 && big.items.map(\.itemCount).max() == 999, "一叠最多 999，多的另起一格")

        // 满了拒收，不挤旧的。
        var full = FileShelfModel()
        for i in 0..<24 { _ = full.add(files: [member(100 + i)]) }
        expect(full.items.count == 24 && full.isFull, "24 格上限")
        let first = full.items.last?.id
        let rej = full.add(files: [member(999)])
        expect(rej.rejection == .full && full.items.count == 24 && full.items.last?.id == first, "满了拒收，不挤旧的")
        let rejTaken = full.add(taken: .text, name: "x", takenFile: "x.txt")
        expect(rejTaken.rejection == .full, "满了文字也拒收")
        var near = full
        near.remove(ids: [full.items[0].id, full.items[1].id])
        let rej5 = near.add(files: (500..<505).map { member($0) })
        expect(rej5.accepted && near.items.count == 23, "叠成一格只占一格")
        var near2 = full
        near2.remove(ids: [full.items[0].id])
        let rej2 = near2.add(files: [member(700), member(701)])
        expect(rej2.rejection == .full && near2.items.count == 23, "格子不够整批拒收")

        // 逐条容错。
        var src = FileShelfModel()
        _ = src.add(files: [member(1), member(2), member(3)])
        _ = src.add(taken: .text, name: "笔记", takenFile: "笔记.txt")
        let data = (try? src.encoded()) ?? Data()
        let rt = FileShelfModel.decode(data)
        expect(rt.model == src && rt.dropped == 0, "编码再解码相等")
        if var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], var arr = obj["items"] as? [[String: Any]] {
            arr[1]["kind"] = "bogus"          // 种类读不懂
            arr[2].removeValue(forKey: "members") // 缺字段
            arr.append(["garbage": 1])
            obj["items"] = arr
            let bad = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
            let r = FileShelfModel.decode(bad)
            expect(r.model.items.count == 2 && r.dropped == 3, "一条坏了只丢那一条（剩 \(r.model.items.count)，丢 \(r.dropped)）")
            expect(r.model.items.map(\.name).contains("笔记"), "好的那几条还在")
        } else { expect(false, "无法构造坏数据") }
        expect(FileShelfModel.decode(Data("not json".utf8)).model.items.isEmpty, "整份读不懂当空架子")
        // 带路径穿越的拿来文件名被当作坏条。
        let evil = FileShelfEntry(id: UUID(), kind: .text, name: "x", members: [], takenFile: "../x", addedAt: 0)
        expect(!evil.isValid, "拿来的文件名不能带目录")

        // 失效判定。
        expect(FileShelfModel.judge(path: "/Volumes/U/a", volumeMounted: false, exists: false) == .volumeOffline, "磁盘没接上")
        expect(FileShelfModel.judge(path: "/Volumes/U/a", volumeMounted: true, exists: false) == .missing, "磁盘在、文件没了")
        expect(FileShelfModel.judge(path: "/Users/a/.Trash/x.pdf", volumeMounted: true, exists: true) == .inTrash, "在废纸篓里")
        expect(FileShelfModel.judge(path: "/Volumes/U/.Trashes/501/x", volumeMounted: true, exists: true) == .inTrash, "外置盘的废纸篓")
        expect(FileShelfModel.judge(path: "/Users/a/Trash.pdf", volumeMounted: true, exists: true) == .available, "名字里有 Trash 不算")
        expect(FileShelfModel.combine([.available, .inTrash, .volumeOffline]) == .volumeOffline, "叠放取最差")
        expect(FileShelfAvailability.volumeOffline.label == "硬盘没接上" && FileShelfAvailability.inTrash.label == "在废纸篓里", "灰格上的话")
        let ids = [UUID(), UUID(), UUID()]
        let st: [UUID: FileShelfAvailability] = [ids[0]: .inTrash, ids[1]: .missing, ids[2]: .volumeOffline]
        expect(FileShelfModel.sweepIDs(states: st, phase: .launch) == [ids[0]], "启动移出废纸篓里的")
        expect(FileShelfModel.sweepIDs(states: st, phase: .cardOpen) == [ids[1]], "打开卡移出找不到的，磁盘没接上的留着")
        expect(FileShelfModel.sweepIDs(states: st, phase: .volumeChange).isEmpty, "磁盘接拔不移出")
        expect(FileShelfModel.missingNotice(count: 1) == "1 个找不到了" && FileShelfModel.missingNotice(count: 0) == nil, "找不到的提示")
    }

    static func storeTests() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("fileshelf-tests-\(UUID().uuidString)", isDirectory: true)
        let root = tmp.appendingPathComponent("shelf", isDirectory: true)
        let files = tmp.appendingPathComponent("files", isDirectory: true)
        try? fm.createDirectory(at: files, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // 主线程不碰书签。
        let probe = files.appendingPathComponent("probe.txt")
        try? Data("p".utf8).write(to: probe)
        do { _ = try FileShelfBookmarks.member(for: probe); expect(false, "主线程应拒绝") } catch {
            expect((error as? FileShelfBookmarks.Failure) == .mainThread, "主线程建书签被拒")
        }

        let store = FileShelfStore(root: root, undoDelay: 0.3, isEnabled: { true })
        store.start()
        let a = files.appendingPathComponent("a.txt"), b = files.appendingPathComponent("b.txt")
        try? Data("a".utf8).write(to: a); try? Data("b".utf8).write(to: b)
        store.add(urls: [a, b])
        store.flush()
        var snap = store.snapshot()
        expect(snap.rows.count == 2 && snap.rows.allSatisfy { $0.availability == .available }, "放进去两格都可用")
        expect(snap.rows.allSatisfy { $0.entry.members[0].bookmark != nil && $0.entry.members[0].identity != nil }, "记了书签和文件编号")

        // 同一个再放：不放两份。
        store.add(urls: [a])
        store.flush()
        expect(store.snapshot().rows.count == 2 && store.snapshot().rows[0].entry.name == "a.txt", "同一个再放不重复且挪前")

        // 改名：书签跟着走，名字变，仍认得。
        let a2 = files.appendingPathComponent("renamed.txt")
        try? fm.moveItem(at: a, to: a2)
        store.refreshForCardOpen(); store.flush()
        snap = store.snapshot()
        expect(snap.rows.contains { $0.entry.name == "renamed.txt" && $0.availability == .available }, "改名后书签跟着走")
        store.add(urls: [a2]); store.flush()
        expect(store.snapshot().rows.count == 2, "改名后再放仍认得是同一个")

        // 清单落盘、重启读回。
        let reborn = FileShelfStore(root: root, isEnabled: { true })
        reborn.start(); reborn.flush()
        expect(reborn.snapshot().rows.count == 2, "跨启动保留")
        reborn.stop(); reborn.flush()

        // 原文件删了：打开卡时移出并说一句。
        try? fm.removeItem(at: b)
        final class Box: @unchecked Sendable { var notice: String? }
        let box = Box()
        store.observe { box.notice = $0.notice ?? box.notice }
        store.refreshForCardOpen(); store.flush()
        expect(store.snapshot().rows.count == 1 && box.notice == "1 个找不到了", "删了原文件，打开卡移出并说一句（\(box.notice ?? "nil")）")

        // 文字、图片、链接：写进“拿来的”。
        store.addText("这是一段很长很长很长的文字需要被截断"); store.flush()
        store.addImage(Data([1, 2, 3]), fileExtension: "JPG"); store.flush()
        store.addLink(URL(string: "https://example.com/notch")!); store.flush()
        let taken = root.appendingPathComponent("拿来的")
        let names = ((try? fm.contentsOfDirectory(atPath: taken.path)) ?? []).sorted()
        expect(names.contains("这是一段很长很长很长的文.txt"), "文字存成 .txt，名字取前 12 个字（\(names)）")
        expect(names.contains("图片.jpg") && names.contains("example.com.webloc"), "图片按原格式、链接存成 .webloc")
        let linkRow = store.snapshot().rows.first { $0.entry.kind == .link }
        expect(linkRow != nil && linkRow?.availability == .available, "拿来的文件可用")

        // 移出：延时删除，撤销期内能撤销。
        let textID = store.snapshot().rows.first { $0.entry.kind == .text }!.entry.id
        store.remove(ids: [textID]); store.flush()
        let textFile = taken.appendingPathComponent("这是一段很长很长很长的文.txt")
        expect(fm.fileExists(atPath: textFile.path), "移出后撤销期内文件还在")
        store.undoRemove(); store.flush()
        expect(store.snapshot().rows.contains { $0.entry.id == textID }, "撤销放回")
        Thread.sleep(forTimeInterval: 0.5); store.flush()
        expect(fm.fileExists(atPath: textFile.path), "撤销后不会被删")
        store.remove(ids: [textID]); store.flush()
        Thread.sleep(forTimeInterval: 0.6); store.flush()
        expect(!fm.fileExists(atPath: textFile.path), "撤销期过了才真的删")
        expect(fm.fileExists(atPath: a2.path), "原文件不动")

        // 满了拒收，且不留文件。
        for i in 0..<30 { store.addText("填满 \(i)") }
        store.flush()
        let rows = store.snapshot().rows
        expect(rows.count == 24, "满了 24 格")
        let takenCount = rows.filter { $0.entry.takenFile != nil }.count
        expect((try? fm.contentsOfDirectory(atPath: taken.path).count) == takenCount, "拿来的文件夹里的文件和格子一一对应")

        // 关掉即清空。
        store.clearAll(); store.flush()
        expect(store.snapshot().rows.isEmpty && !fm.fileExists(atPath: taken.path) && !fm.fileExists(atPath: root.appendingPathComponent("items.json").path),
               "关掉清空，连拿来的文件夹一起删")

        // 关着的时候不记任何东西。
        let off = FileShelfStore(root: tmp.appendingPathComponent("off"), isEnabled: { false })
        off.start(); off.addText("不该记"); off.flush()
        expect(off.snapshot().rows.isEmpty && !fm.fileExists(atPath: tmp.appendingPathComponent("off").path), "关着不记任何东西")
        store.stop(); store.flush()
    }
}
