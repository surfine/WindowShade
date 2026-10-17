// 文件架的存取与失效检查（没有画面、没有调用方；入口接上之前不会记任何东西）。
// 规则见 docs/design-drafts/文件架.html：文件、文件夹只记位置；文字、图片、链接写成文件放进
// ~/Library/Application Support/WindowShade/文件架/拿来的/；清单 items.json 原子写；
// 磁盘接拔靠系统通知检查，不轮询；书签只在后台队列里建和解析，主线程不碰。
import AppKit
import Foundation

enum FileShelf {
    static let enabledKey = "FileShelf.enabled"

    /// 1.0.18 起 Aaron 拍板默认开；没有入口前不会记任何东西。设置里关掉即清空。
    static var enabled: Bool {
        get { (UserDefaults.standard.object(forKey: enabledKey) as? Bool) ?? ReleaseDefaults.value(enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("WindowShade/文件架", isDirectory: true)
    }
}

/// 书签的建立与解析。必须在后台线程调用；在主线程调用直接报错，不去碰书签。
enum FileShelfBookmarks {
    enum Failure: Error, Equatable { case mainThread, unreadable }

    static func member(for url: URL) throws -> FileShelfMember {
        guard !Thread.isMainThread else { throw Failure.mainThread }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .volumeUUIDStringKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { throw Failure.unreadable }
        // 普通书签：macOS 26 上不在沙盒里的 App 建不了 security-scoped 的。
        let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        return FileShelfMember(name: url.lastPathComponent, path: url.path,
                               isFolder: values.isDirectory ?? false, bookmark: data,
                               identity: identity(of: url, volumeUUID: values.volumeUUIDString))
    }

    /// 不弹窗、不去挂网络盘。
    static func resolve(_ m: FileShelfMember) throws -> (url: URL, stale: Bool) {
        guard !Thread.isMainThread else { throw Failure.mainThread }
        guard let data = m.bookmark else { throw Failure.unreadable }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }

    static func identity(of url: URL, volumeUUID: String? = nil) -> FileShelfIdentity? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = attrs[.systemFileNumber] as? NSNumber else { return nil }
        let volume = volumeUUID
            ?? (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
            ?? "dev:\((attrs[.systemNumber] as? NSNumber)?.intValue ?? 0)"
        return FileShelfIdentity(volume: volume, fileID: number.uint64Value)
    }

    /// 现在接着的磁盘（读系统的挂载表，不碰网络）。
    static func mountedVolumeUUIDs() -> Set<String> {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeUUIDStringKey], options: []) ?? []
        return Set(urls.compactMap { try? $0.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString })
    }
}

struct FileShelfRow: Equatable, Sendable {
    var entry: FileShelfEntry
    var availability: FileShelfAvailability
}

struct FileShelfUpdate: Equatable, Sendable {
    var rows: [FileShelfRow]
    /// 比如“1 个找不到了”；没有就是 nil。
    var notice: String?
}

/// 所有状态都只在 io 队列里读写。
final class FileShelfStore: @unchecked Sendable {
    private let root: URL
    private let undoDelay: TimeInterval
    private let isEnabled: @Sendable () -> Bool
    private let io = DispatchQueue(label: "WindowShade.FileShelf.io", qos: .utility)

    private var model = FileShelfModel()
    private var states: [UUID: FileShelfAvailability] = [:]
    private var onChange: (@Sendable (FileShelfUpdate) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var undoBatch: [(entry: FileShelfEntry, index: Int)] = []
    private var pendingDeletes: [UUID: DispatchWorkItem] = [:]
    private var started = false

    init(root: URL = FileShelf.defaultRoot, undoDelay: TimeInterval = 5,
         isEnabled: @escaping @Sendable () -> Bool = { FileShelf.enabled }) {
        self.root = root
        self.undoDelay = undoDelay
        self.isEnabled = isEnabled
    }

    private var itemsURL: URL { root.appendingPathComponent("items.json") }
    private var takenDir: URL { root.appendingPathComponent("拿来的", isDirectory: true) }

    // MARK: 生命周期

    func observe(_ handler: (@Sendable (FileShelfUpdate) -> Void)?) { io.async { self.onChange = handler } }

    /// 读清单，订阅磁盘接拔通知，后台检查一次。关着的时候什么都不做。
    func start() {
        io.async { [weak self] in
            guard let self else { return }
            guard !self.started, self.isEnabled() else { return }
            self.started = true
            if let data = try? Data(contentsOf: self.itemsURL) {
                let decoded = FileShelfModel.decode(data)
                self.model = decoded.model
                if decoded.dropped > 0 { self.persist() }
            }
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
                self.observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                    guard let store = self else { return }
                    store.io.async { store.sweep(.volumeChange) }
                })
            }
            self.sweep(.launch)
        }
    }

    func stop() {
        io.async {
            let center = NSWorkspace.shared.notificationCenter
            for o in self.observers { center.removeObserver(o) }
            self.observers = []
            self.started = false
        }
    }

    /// 打开文件架卡时调：查一次，找不到的移出并说一句。
    func refreshForCardOpen() { io.async { self.sweep(.cardOpen) } }

    /// 设置里关掉文件架：清空，连同“拿来的”文件夹一起删。
    func clearAll() {
        io.async {
            for item in self.pendingDeletes.values { item.cancel() }
            self.pendingDeletes = [:]
            self.undoBatch = []
            self.model.removeAll()
            self.states = [:]
            try? FileManager.default.removeItem(at: self.takenDir)
            try? FileManager.default.removeItem(at: self.itemsURL)
            self.publish(notice: nil)
        }
    }

    // MARK: 放进来

    func add(urls: [URL], completion: (@Sendable (FileShelfAddOutcome) -> Void)? = nil) {
        io.async {
            guard self.isEnabled() else { completion?(Self.disabled); return }
            let members = urls.compactMap { try? FileShelfBookmarks.member(for: $0) }
            let outcome = self.model.add(files: members)
            self.finish(outcome)
            completion?(outcome)
        }
    }

    func addText(_ text: String, completion: (@Sendable (FileShelfAddOutcome) -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = Self.shortName(trimmed, fallback: WSL10n.text("fileDrag.text", zh: "文字"))
        addTaken(.text, name: name, ext: "txt", body: Data(trimmed.utf8), empty: trimmed.isEmpty, completion: completion)
    }

    /// 网页上的图按原格式写下来；ext 是原格式的扩展名（png、jpg…）。
    func addImage(_ data: Data, fileExtension: String, completion: (@Sendable (FileShelfAddOutcome) -> Void)? = nil) {
        let ext = String(fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(5))
        addTaken(.image, name: WSL10n.text("fileDrag.image", zh: "图片"), ext: ext.isEmpty ? "png" : ext, body: data, empty: data.isEmpty, completion: completion)
    }

    func addLink(_ url: URL, completion: (@Sendable (FileShelfAddOutcome) -> Void)? = nil) {
        let plist: [String: Any] = ["URL": url.absoluteString]
        let body = (try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)) ?? Data()
        let name = Self.shortName(url.host ?? url.absoluteString, fallback: WSL10n.text("fileDrag.link", zh: "链接"))
        addTaken(.link, name: name, ext: "webloc", body: body, empty: url.absoluteString.isEmpty, completion: completion)
    }

    private func addTaken(_ kind: FileShelfKind, name: String, ext: String, body: Data, empty: Bool,
                          completion: (@Sendable (FileShelfAddOutcome) -> Void)?) {
        io.async {
            guard self.isEnabled() else { completion?(Self.disabled); return }
            var outcome = FileShelfAddOutcome()
            if empty { outcome.rejection = .empty; completion?(outcome); return }
            if self.model.isFull { outcome.rejection = .full; completion?(outcome); return }
            let fm = FileManager.default
            try? fm.createDirectory(at: self.takenDir, withIntermediateDirectories: true)
            var file = "\(name).\(ext)"
            var n = 2
            while fm.fileExists(atPath: self.takenDir.appendingPathComponent(file).path) {
                file = "\(name) \(n).\(ext)"; n += 1
            }
            do { try body.write(to: self.takenDir.appendingPathComponent(file), options: .atomic) } catch {
                outcome.rejection = .empty; completion?(outcome); return
            }
            outcome = self.model.add(taken: kind, name: name, takenFile: file)
            if !outcome.accepted { try? fm.removeItem(at: self.takenDir.appendingPathComponent(file)) }
            self.finish(outcome)
            completion?(outcome)
        }
    }

    // MARK: 移出与撤销

    /// 移出：原文件不动；拿来的文件等撤销时间过了才删。
    func remove(ids: Set<UUID>) {
        io.async {
            self.finalizeUndoBatch()
            let before = self.model.items
            let gone = self.model.remove(ids: ids)
            self.undoBatch = gone.compactMap { e in before.firstIndex(where: { $0.id == e.id }).map { (e, $0) } }
            self.scheduleDeletes(for: gone)
            self.persist()
            self.publish(notice: nil)
        }
    }

    func removeAll() { io.async { self.removeAllNow() } }

    private func removeAllNow() {
        finalizeUndoBatch()
        let before = model.items
        let gone = model.removeAll()
        undoBatch = gone.compactMap { e in before.firstIndex(where: { $0.id == e.id }).map { (e, $0) } }
        scheduleDeletes(for: gone)
        persist()
        publish(notice: nil)
    }

    /// 撤销上一次移出（撤销时间内）。
    func undoRemove() {
        io.async {
            guard !self.undoBatch.isEmpty else { return }
            for (e, _) in self.undoBatch { self.pendingDeletes.removeValue(forKey: e.id)?.cancel() }
            self.model.restore(self.undoBatch)
            self.undoBatch = []
            self.persist()
            self.sweep(.volumeChange)
        }
    }

    private func scheduleDeletes(for entries: [FileShelfEntry]) {
        for e in entries {
            guard let file = e.takenFile else { continue }
            let url = takenDir.appendingPathComponent(file)
            let id = e.id
            let item = DispatchWorkItem { [weak self] in
                try? FileManager.default.removeItem(at: url)
                self?.pendingDeletes[id] = nil
                self?.undoBatch.removeAll { $0.entry.id == id }
            }
            pendingDeletes[id] = item
            io.asyncAfter(deadline: .now() + undoDelay, execute: item)
        }
    }

    /// 新的一次移出开始时，上一批的撤销机会作废：该删的立刻删。
    private func finalizeUndoBatch() {
        for (e, _) in undoBatch {
            guard let item = pendingDeletes.removeValue(forKey: e.id) else { continue }
            item.cancel()
            if let file = e.takenFile { try? FileManager.default.removeItem(at: takenDir.appendingPathComponent(file)) }
        }
        undoBatch = []
    }

    // MARK: 失效检查

    /// 查一遍：书签跟着走（改名、挪位置），判定失效，按时机移出该移出的。
    private func sweep(_ phase: FileShelfSweepPhase) {
        let fm = FileManager.default
        let mounted = FileShelfBookmarks.mountedVolumeUUIDs()
        var next: [UUID: FileShelfAvailability] = [:]
        var changed = false
        for entry in model.items {
            if let file = entry.takenFile {
                next[entry.id] = fm.fileExists(atPath: takenDir.appendingPathComponent(file).path) ? .available : .missing
                continue
            }
            var memberStates: [FileShelfAvailability] = []
            for (i, m) in entry.members.enumerated() {
                if let (url, stale) = try? FileShelfBookmarks.resolve(m) {
                    var updated = m
                    updated.path = url.path
                    updated.name = url.lastPathComponent
                    if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                        updated.bookmark = fresh
                    }
                    if updated != m { model.updateMember(entryID: entry.id, at: i, with: updated); changed = true }
                    memberStates.append(FileShelfModel.judge(path: url.path, volumeMounted: true,
                                                             exists: fm.fileExists(atPath: url.path)))
                } else {
                    let volume = m.identity?.volume
                    let isMounted = volume.map { mounted.contains($0) || $0.hasPrefix("dev:") } ?? true
                    memberStates.append(FileShelfModel.judge(path: m.path, volumeMounted: isMounted,
                                                             exists: isMounted && fm.fileExists(atPath: m.path)))
                }
            }
            next[entry.id] = FileShelfModel.combine(memberStates)
        }
        let doomed = FileShelfModel.sweepIDs(states: next, phase: phase)
        if !doomed.isEmpty {
            model.remove(ids: doomed)
            for id in doomed { next[id] = nil }
            changed = true
        }
        states = next
        if changed { persist() }
        publish(notice: phase == .cardOpen ? FileShelfModel.missingNotice(count: doomed.count) : nil)
    }

    // MARK: 内部

    private static let disabled = FileShelfAddOutcome(rejection: .disabled)

    private func finish(_ outcome: FileShelfAddOutcome) {
        guard outcome.accepted else { return }
        persist()
        sweep(.volumeChange)
    }

    private func persist() {
        guard let data = try? model.encoded() else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? data.write(to: itemsURL, options: .atomic)
    }

    private func publish(notice: String?) {
        let rows = model.items.map { FileShelfRow(entry: $0, availability: states[$0.id] ?? .available) }
        onChange?(FileShelfUpdate(rows: rows, notice: notice))
    }

    /// 取前 12 个字做名字；斜杠、冒号、换行换成空格。
    static func shortName(_ s: String, fallback: String) -> String {
        let cleaned = s.map { "/:\n\r\t".contains($0) ? " " : $0 }
        let name = String(String(cleaned).prefix(12)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name.hasPrefix(".") ? fallback : name
    }

    /// 现在有几格、满没满（异步问，不卡主线程）。落点小岛靠它把“暂存”灰掉。
    func count(_ done: @escaping @Sendable (Int, Bool) -> Void) {
        io.async { done(self.model.items.count, self.model.isFull) }
    }

    // MARK: 给测试

    func flush() { io.sync {} }
    func snapshot() -> FileShelfUpdate {
        io.sync { FileShelfUpdate(rows: model.items.map { FileShelfRow(entry: $0, availability: states[$0.id] ?? .available) }, notice: nil) }
    }
}
