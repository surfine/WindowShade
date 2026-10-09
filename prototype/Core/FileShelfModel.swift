// 文件架（FileShelf）的纯数据模型：只用 Foundation，没有画面，没有磁盘访问。
// 规则来自 docs/design-drafts/文件架.html 的“存什么、存在哪”和“边缘情况”。
// 注意：代码里 NotchShelf 是“刘海里收着的窗口”，和这里无关；文件架一律叫 FileShelf。
import Foundation

/// 一格里放的是什么。
enum FileShelfKind: String, Codable, Sendable, CaseIterable {
    case file, folder, stack, text, image, link
}

/// “哪块磁盘 + 文件编号”。改名、挪位置之后还是同一个。
struct FileShelfIdentity: Hashable, Codable, Sendable {
    var volume: String
    var fileID: UInt64
}

/// 文件或文件夹：只记位置（书签 + 放进来时的路径和显示名），不拷贝。
struct FileShelfMember: Codable, Equatable, Sendable {
    var name: String
    var path: String
    var isFolder: Bool
    var bookmark: Data?
    var identity: FileShelfIdentity?
}

/// 架子上的一格。
struct FileShelfEntry: Codable, Equatable, Sendable, Identifiable {
    static let maxStackCount = 999

    var id: UUID
    var kind: FileShelfKind
    var name: String
    /// 文件、文件夹：单个成员；叠放：5 个以上的成员；文字、图片、链接：空。
    var members: [FileShelfMember]
    /// 文字、图片、链接：存在“拿来的”文件夹里的文件名（不含目录）。
    var takenFile: String?
    var addedAt: Double

    /// 这一格代表几件东西（叠放是成员数，其余是 1）。
    var itemCount: Int { kind == .stack ? members.count : 1 }

    /// 读回来的一条是否站得住；站不住的只丢它自己。
    var isValid: Bool {
        switch kind {
        case .file, .folder:
            guard members.count == 1, let m = members.first else { return false }
            return m.isFolder == (kind == .folder) && !(m.path.isEmpty && m.bookmark == nil)
        case .stack:
            return members.count >= 2
                && members.count <= Self.maxStackCount
                && members.allSatisfy { !($0.path.isEmpty && $0.bookmark == nil) }
        case .text, .image, .link:
            guard let f = takenFile else { return false }
            return members.isEmpty && !f.isEmpty && !f.contains("/") && f != "." && f != ".."
        }
    }
}

/// 失效状态。
enum FileShelfAvailability: Equatable, Sendable {
    case available, inTrash, volumeOffline, missing

    /// 灰格上写的话；可用时没有。
    var label: String? {
        switch self {
        case .available: return nil
        case .inTrash: return "在废纸篓里"
        case .volumeOffline: return "硬盘没接上"
        case .missing: return "找不到了"
        }
    }
}

/// 什么时候做的检查，决定哪些失效要移出。
enum FileShelfSweepPhase: Equatable, Sendable { case launch, cardOpen, volumeChange }

/// 往架子里放：成功、重复挪前、还是拒收。
struct FileShelfAddOutcome: Equatable, Sendable {
    enum Rejection: Equatable, Sendable { case full, empty, disabled }
    var added: [UUID] = []
    var bumped: [UUID] = []
    var rejection: Rejection?
    var accepted: Bool { rejection == nil }
}

struct FileShelfModel: Equatable, Sendable {
    static let capacity = 24
    static let stackThreshold = 5

    private(set) var items: [FileShelfEntry] = []   // 最新的在最前

    init(items: [FileShelfEntry] = []) {
        var seen = Set<UUID>()
        self.items = Array(items.filter { $0.isValid && seen.insert($0.id).inserted }.prefix(Self.capacity))
    }

    var isFull: Bool { items.count >= Self.capacity }

    // MARK: 放进来

    /// 一批文件或文件夹。1 到 4 个各占一格，5 个以上叠成一格（一叠最多 999，更多就再叠一格）。
    /// 已经在架子上的（按磁盘 + 文件编号认）不放第二份，原来那一格挪到最前。
    /// 格子不够就整批拒收，不挤掉旧的。
    mutating func add(files: [FileShelfMember], now: Date = Date(), makeID: () -> UUID = UUID.init) -> FileShelfAddOutcome {
        var outcome = FileShelfAddOutcome()
        // 批内去重（有编号的按编号，没编号的按路径）。
        var seenIDs = Set<FileShelfIdentity>()
        var seenPaths = Set<String>()
        var batch: [FileShelfMember] = []
        for m in files {
            if let id = m.identity {
                if !seenIDs.insert(id).inserted { continue }
            } else if !seenPaths.insert(m.path).inserted { continue }
            batch.append(m)
        }
        guard !batch.isEmpty else { outcome.rejection = .empty; return outcome }

        var fresh: [FileShelfMember] = []
        var bump: [UUID] = []
        for m in batch {
            if let hit = items.first(where: { Self.contains($0, m) }) {
                if !bump.contains(hit.id) { bump.append(hit.id) }
            } else { fresh.append(m) }
        }

        let stamp = now.timeIntervalSince1970
        var newEntries: [FileShelfEntry] = []
        if fresh.count >= Self.stackThreshold {
            for chunk in Self.chunks(fresh, FileShelfEntry.maxStackCount) {
                if chunk.count == 1 {
                    newEntries.append(FileShelfEntry(id: makeID(), kind: chunk[0].isFolder ? .folder : .file, name: chunk[0].name,
                                                     members: chunk, takenFile: nil, addedAt: stamp))
                } else {
                    newEntries.append(FileShelfEntry(id: makeID(), kind: .stack, name: "\(chunk.count) 个文件",
                                                     members: chunk, takenFile: nil, addedAt: stamp))
                }
            }
        } else {
            for m in fresh {
                newEntries.append(FileShelfEntry(id: makeID(), kind: m.isFolder ? .folder : .file, name: m.name,
                                                 members: [m], takenFile: nil, addedAt: stamp))
            }
        }
        if newEntries.count > Self.capacity - items.count {
            outcome.rejection = .full
            return outcome
        }
        for id in bump { moveToFront(id) }
        items.insert(contentsOf: newEntries.reversed(), at: 0)
        outcome.bumped = bump
        outcome.added = newEntries.map(\.id)
        return outcome
    }

    /// 文字、图片、链接：内容已经写成了“拿来的”文件夹里的 takenFile。
    mutating func add(taken kind: FileShelfKind, name: String, takenFile: String,
                      now: Date = Date(), id: UUID = UUID()) -> FileShelfAddOutcome {
        var outcome = FileShelfAddOutcome()
        guard [.text, .image, .link].contains(kind) else { outcome.rejection = .empty; return outcome }
        guard !isFull else { outcome.rejection = .full; return outcome }
        let entry = FileShelfEntry(id: id, kind: kind, name: name, members: [], takenFile: takenFile,
                                   addedAt: now.timeIntervalSince1970)
        guard entry.isValid else { outcome.rejection = .empty; return outcome }
        items.insert(entry, at: 0)
        outcome.added = [id]
        return outcome
    }

    // MARK: 移出

    @discardableResult
    mutating func remove(ids: Set<UUID>) -> [FileShelfEntry] {
        let gone = items.filter { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        return gone
    }

    /// 撤销移出：放回原来的位置；装不下的不挤旧的。
    mutating func restore(_ entries: [(entry: FileShelfEntry, index: Int)]) {
        for (entry, index) in entries.sorted(by: { $0.index < $1.index })
        where !isFull && !items.contains(where: { $0.id == entry.id }) && entry.isValid {
            items.insert(entry, at: min(max(index, 0), items.count))
        }
    }

    @discardableResult
    mutating func removeAll() -> [FileShelfEntry] {
        let gone = items
        items = []
        return gone
    }

    mutating func moveToFront(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), i != 0 else { return }
        items.insert(items.remove(at: i), at: 0)
    }

    /// 书签跟着走：名字、路径、书签更新（改名、挪位置之后）。
    mutating func updateMember(entryID: UUID, at index: Int, with m: FileShelfMember) {
        guard let i = items.firstIndex(where: { $0.id == entryID }), items[i].members.indices.contains(index) else { return }
        items[i].members[index] = m
        if items[i].kind != .stack { items[i].name = m.name }
    }

    // MARK: 失效

    /// 磁盘接着没、文件在不在、路径在不在废纸篓 → 状态。先看磁盘，再看文件，最后看废纸篓。
    static func judge(path: String, volumeMounted: Bool, exists: Bool) -> FileShelfAvailability {
        if !volumeMounted { return .volumeOffline }
        if !exists { return .missing }
        let parts = path.split(separator: "/").map(String.init)
        if parts.contains(".Trash") || parts.contains(".Trashes") { return .inTrash }
        return .available
    }

    /// 一格的状态：叠放里所有成员都可用才算可用，否则取最差的（磁盘 > 找不到 > 废纸篓）。
    static func combine(_ states: [FileShelfAvailability]) -> FileShelfAvailability {
        for s in [FileShelfAvailability.volumeOffline, .missing, .inTrash] where states.contains(s) { return s }
        return .available
    }

    /// 该移出的格子：启动时清掉“在废纸篓里”的；打开卡时清掉“找不到了”的。磁盘没接上的永远留着。
    static func sweepIDs(states: [UUID: FileShelfAvailability], phase: FileShelfSweepPhase) -> Set<UUID> {
        switch phase {
        case .launch: return Set(states.filter { $0.value == .inTrash }.keys)
        case .cardOpen: return Set(states.filter { $0.value == .missing }.keys)
        case .volumeChange: return []
        }
    }

    static func missingNotice(count: Int) -> String? { count > 0 ? "\(count) 个找不到了" : nil }

    // MARK: items.json 编解码（逐条容错）

    private struct File: Codable { var version: Int; var items: [Lossy] }
    private struct Lossy: Codable {
        var value: FileShelfEntry?
        init(_ v: FileShelfEntry) { value = v }
        init(from decoder: Decoder) throws { value = try? FileShelfEntry(from: decoder) }
        func encode(to encoder: Encoder) throws { try value?.encode(to: encoder) }
    }

    func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(File(version: 1, items: items.map(Lossy.init)))
    }

    /// 整份读不懂就当空架子；其中一条坏了只丢那一条。dropped 是丢掉的条数。
    static func decode(_ data: Data) -> (model: FileShelfModel, dropped: Int) {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return (FileShelfModel(), 0) }
        let model = FileShelfModel(items: file.items.compactMap(\.value))
        return (model, file.items.count - model.items.count)
    }

    // MARK: 内部

    private static func contains(_ entry: FileShelfEntry, _ m: FileShelfMember) -> Bool {
        entry.members.contains { e in
            if let a = e.identity, let b = m.identity { return a == b }
            return e.identity == nil && m.identity == nil && e.path == m.path
        }
    }

    private static func chunks(_ a: [FileShelfMember], _ n: Int) -> [[FileShelfMember]] {
        stride(from: 0, to: a.count, by: n).map { Array(a[$0..<min($0 + n, a.count)]) }
    }
}
