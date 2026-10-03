// 启动台的纯规则（可单测）：一页排几行几列、翻页停在哪一页、搜索怎么匹配（中文可以打拼音、拼音首字母、小鹤双拼）。

import CoreGraphics
import Foundation

/// 启动台里的一个 App。
struct LaunchpadApp: Hashable {
    let path: String
    let name: String
    let bundleID: String?
    /// App 自己在 Info.plist 里写的类别（LSApplicationCategoryType），App 资料库按它分组。
    let category: String?
    /// 装进来的时间（“最近添加”）、上次打开的时间（“建议”）。
    let added: Date?
    let lastUsed: Date?
    /// 全拼（小写、无声调、音节之间不留空）和每个音节的首字母：中文名可以打 “weixin” 或 “wx”。
    let pinyin: String
    let initials: String
    /// 小鹤双拼：每个音节两个键（“微信”是 wwxb，“计算器”是 jisrqi）。
    let shuangpin: String

    init(path: String, name: String, bundleID: String?, category: String? = nil, added: Date? = nil, lastUsed: Date? = nil) {
        self.path = path
        self.name = name
        self.bundleID = bundleID
        self.category = category
        self.added = added
        self.lastUsed = lastUsed
        let latin = LaunchpadSearch.latin(name)
        let syllables = latin.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        pinyin = syllables.joined()
        initials = String(syllables.compactMap(\.first))
        shuangpin = LaunchpadSearch.xiaohe(name)
    }
}

enum LaunchpadSearch {
    /// 名字转成拉丁字母：中文转拼音，去掉声调和大小写。
    static func latin(_ text: String) -> String {
        let mandarin = text.applyingTransform(.mandarinToLatin, reverse: false) ?? text
        let plain = mandarin.applyingTransform(.stripDiacritics, reverse: false) ?? mandarin
        return plain.lowercased()
    }

    /// 小鹤双拼的韵母键（声母 zh / ch / sh 是 v / i / u，其余声母照原字母）。
    static let xiaoheFinals: [String: String] = [
        "iu": "q", "ei": "w", "uan": "r", "van": "r", "ue": "t", "ve": "t", "un": "y", "uo": "o", "ie": "p",
        "ong": "s", "iong": "s", "ai": "d", "en": "f", "eng": "g", "ang": "h", "an": "j", "ing": "k", "uai": "k",
        "iang": "l", "uang": "l", "ou": "z", "ua": "x", "ia": "x", "ao": "c", "ui": "v", "in": "b", "iao": "n",
        "ian": "m", "a": "a", "o": "o", "e": "e", "i": "i", "u": "u", "v": "v",
    ]

    /// 名字转成小鹤双拼，和全拼用同一个系统转换（多音字取它给的读音，和全拼搜索一致）；
    /// 没有汉字的名字没有双拼；英文单词转不成双拼音节的就跳过。
    static func xiaohe(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }),
              let mandarin = text.applyingTransform(.mandarinToLatin, reverse: false) else { return "" }
        // ü 先记成 v（lǜ → lv），再去声调。
        let marked = mandarin.lowercased().map { "üǖǘǚǜ".contains($0) ? "v" : String($0) }.joined()
        let plain = marked.applyingTransform(.stripDiacritics, reverse: false) ?? marked
        return plain.split(whereSeparator: { !($0.isASCII && $0.isLetter) })
            .compactMap { xiaoheSyllable(String($0)) }.joined()
    }

    static func xiaoheSyllable(_ syllable: String) -> String? {
        guard !syllable.isEmpty else { return nil }
        var initial = "", rest = Substring(syllable)
        for (spelled, key) in [("zh", "v"), ("ch", "i"), ("sh", "u")] where syllable.hasPrefix(spelled) {
            initial = key; rest = syllable.dropFirst(2)
        }
        if initial.isEmpty, let first = syllable.first, "bpmfdtnlgkhjqxrzcsyw".contains(first) {
            initial = String(first); rest = syllable.dropFirst()
        }
        let final = String(rest)
        if initial.isEmpty {
            // 零声母：一个字母的双写（a → aa），两个字母照写（ai → ai），三个以上是首字母加韵母键（ang → ah）。
            switch final.count {
            case 1: return final + final
            case 2: return final
            default: return xiaoheFinals[final].map { String(final.prefix(1)) + $0 }
            }
        }
        return xiaoheFinals[final].map { initial + $0 }
    }

    /// 匹配得多好：0 不匹配；越大越靠前。名字开头 > 词开头 > 拼音开头 > 双拼开头 > 首字母 > 名字中间 > 拼音中间。
    static func score(_ app: LaunchpadApp, query raw: String) -> Int {
        let query = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return 1 }
        let name = app.name.lowercased()
        if name.hasPrefix(query) { return 100 }
        if name.split(whereSeparator: { $0 == " " || $0 == "-" }).contains(where: { $0.hasPrefix(query) }) { return 80 }
        let compact = query.replacingOccurrences(of: " ", with: "")
        if app.pinyin.hasPrefix(compact) { return 70 }
        if compact.count >= 2, app.shuangpin.hasPrefix(compact) { return 65 }
        if app.initials.hasPrefix(compact) { return 60 }
        if name.contains(query) { return 40 }
        if app.pinyin.contains(compact) { return 30 }
        return 0
    }

    /// 按名字排：中文按拼音，和英文名混在一起按字母排（iOS 中文环境就是这样）。
    static func ordered(_ a: LaunchpadApp, _ b: LaunchpadApp) -> Bool {
        let order = a.pinyin.localizedStandardCompare(b.pinyin)
        return order == .orderedSame ? a.name.localizedStandardCompare(b.name) == .orderedAscending : order == .orderedAscending
    }

    /// 按匹配程度排好的结果（同分按名字）。
    static func filter(_ apps: [LaunchpadApp], query: String) -> [LaunchpadApp] {
        let scored: [(app: LaunchpadApp, score: Int)] = apps.map { ($0, score($0, query: query)) }.filter { $0.1 > 0 }
        let sorted = scored.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            return ordered(a.app, b.app)
        }
        return sorted.map(\.app)
    }
}

/// 一页的格子：经典启动台是 7 列 × 5 行，图标占格子的一大半，四周留边。
struct LaunchpadGrid: Equatable {
    var columns: Int
    var rows: Int
    /// 格子（点）和图标边长（点）。
    var cell: CGSize
    var icon: CGFloat
    /// 格子区域在页面里的外框（点，左上原点）。
    var area: CGRect

    var perPage: Int { columns * rows }

    /// 按屏幕大小排：采用 macOS 15 官方截图的主屏幕比例；底部给独立页码和程序坞留空。
    static func layout(for size: CGSize, dock: CGFloat = 0) -> LaunchpadGrid {
        // 竖放的屏幕（外接屏转 90°）：5 列 × 7 行，一页的数量和横屏差不多，图标按短边算，不缩成一排小点。
        let portrait = size.width < size.height
        let columns = portrait ? 5 : (size.width / size.height < 1.4 ? 6 : 7)
        let rows = portrait ? 7 : 5
        let top = max(64, size.height * 0.083), bottom = max(100, size.height * 0.17, dock + 52)
        let side = max(36, size.width * 0.099)
        let area = CGRect(x: side, y: top, width: size.width - side * 2, height: size.height - top - bottom)
        let cell = CGSize(width: area.width / CGFloat(columns), height: area.height / CGFloat(rows))
        let across = portrait ? size.width * 0.083 : size.width * 0.052
        let down = portrait ? size.height * 0.052 : size.height * 0.081
        let icon = min(across, down, cell.width * 0.62, cell.height * 0.62, 128)
        return LaunchpadGrid(columns: columns, rows: rows, cell: cell, icon: icon.rounded(), area: area)
    }

    func pages(for count: Int) -> Int { max(1, (count + perPage - 1) / perPage) }

    /// 第 index 个 App 在第几页、格子中心（页面坐标，左上原点）。
    func slot(_ index: Int) -> (page: Int, center: CGPoint) {
        let page = index / perPage, local = index % perPage
        let row = local / columns, column = local % columns
        return (page, CGPoint(x: area.minX + (CGFloat(column) + 0.5) * cell.width,
                              y: area.minY + (CGFloat(row) + 0.5) * cell.height))
    }

    /// 页面坐标里的这一点落在第几个格子上（没落在格子上为 nil）。
    func index(at point: CGPoint, page: Int) -> Int? {
        guard area.contains(point) else { return nil }
        let column = Int((point.x - area.minX) / cell.width), row = Int((point.y - area.minY) / cell.height)
        return page * perPage + row * columns + column
    }
}

enum LaunchpadPaging {
    /// 手指松开时停在哪一页：按惯性推算（WWDC18：(v/1000)·r/(1−r)，r = 0.99），离哪页近停哪页，一次最多翻一页。
    /// offset：当前拖出去多少页（往左拖为正，比如 0.3 表示朝下一页拖了三成）；velocity：页/秒，同一方向为正。
    static func settle(page: Int, offset: Double, velocity: Double, pages: Int) -> Int {
        let projected = offset + velocity / 1000 * 0.99 / (1 - 0.99)
        let step = projected > 0.5 ? 1 : projected < -0.5 ? -1 : 0
        return min(max(page + step, 0), max(pages - 1, 0))
    }

    /// 第一页往右、最后一页往左拖：越拖越沉，不撞墙。
    static func rubberBand(_ overshoot: Double, width: Double) -> Double {
        let x = abs(overshoot), c = 0.55
        let value = x * width * c / (width + c * x)
        return overshoot < 0 ? -value : value
    }
}

/// 把 App 从启动台拖出来，松在哪儿就怎么开（照 iPadOS 26.2 从程序坞拖出 App 的做法）：
/// 最外边一条 → 侧拉；靠左、靠右 → 那一半（靠上、靠下的角 → 那一角）；顶上正中 → 铺满；中间 → 照常打开。
enum LaunchpadDrop: Equatable {
    case slideOver(left: Bool)
    case half(left: Bool)
    case quarter(left: Bool, top: Bool)
    case fill
    case notch
    case open

    /// point、screen：同一套坐标（x 向右、y 向下）。边上那一条宽屏宽的 6%（至少 48 点、最多 96 点），
    /// 半屏区到屏宽的 30%，其中上下各四分之一是角；顶上 12% 的正中那一块是铺满。
    static func zone(at point: CGPoint, in screen: CGRect, notch: CGRect? = nil) -> LaunchpadDrop {
        if let notch, notch.contains(point) { return .notch }
        let edge = min(max(screen.width * 0.06, 48), 96)
        let x = point.x - screen.minX, y = point.y - screen.minY
        if x < edge { return .slideOver(left: true) }
        if x > screen.width - edge { return .slideOver(left: false) }
        let left = x < screen.width * 0.3, right = x > screen.width * 0.7
        if left || right {
            if y < screen.height * 0.25 { return .quarter(left: left, top: true) }
            if y > screen.height * 0.75 { return .quarter(left: left, top: false) }
            return .half(left: left)
        }
        if y < screen.height * 0.12 { return .fill }
        return .open
    }
}

/// 编辑时挪动一格。
enum LaunchpadOrder {
    /// 把 from 那一个挪到 to（其余依次让位）。
    static func move<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard items.indices.contains(from) else { return items }
        var list = items
        let item = list.remove(at: from)
        list.insert(item, at: min(max(to, 0), list.count))
        return list
    }
}

// MARK: - 主屏幕：App 和文件夹（照 iPadOS）

/// 文件夹：名字和里面的 App（按路径）。
struct LaunchpadFolder: Codable, Hashable {
    var id: String
    var name: String
    var apps: [String]
}

/// 主屏幕上的一格：一个 App，或者一个文件夹。
enum LaunchpadItem: Codable, Hashable {
    case app(String)
    case folder(LaunchpadFolder)

    var paths: [String] {
        switch self {
        case .app(let path): return [path]
        case .folder(let folder): return folder.apps
        }
    }

    var folderID: String? {
        if case .folder(let folder) = self { return folder.id }
        return nil
    }
}

/// 主屏幕的排法（存下来）：一格一格的顺序，和“从主屏幕移除”的 App（像 iOS 一样只留在 App 资料库里）。
struct LaunchpadLayout: Codable, Equatable {
    var items: [LaunchpadItem] = []
    var removed: [String] = []

    /// 第一次：照旧版启动台——苹果自带的在前（常用的排前面），别的按名字接在后面；实用工具和几样不常用的收进“其他”文件夹，
    /// 放在苹果自带的后面。
    static func initial(apps: [LaunchpadApp], otherName: String) -> LaunchpadLayout {
        // 同一个路径只算一次（目录里重复扫到的条目不能让主屏幕出现两份），保留第一次出现的那个。
        var seenPaths = Set<String>()
        let unique = apps.filter { seenPaths.insert($0.path).inserted }
        let rank = Dictionary(appleOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = unique.sorted { a, b in
            let ra = a.bundleID.flatMap { rank[$0] }, rb = b.bundleID.flatMap { rank[$0] }
            if let ra, let rb { return ra < rb }
            if (ra == nil) != (rb == nil) { return ra != nil }
            let appleA = a.bundleID?.hasPrefix("com.apple.") == true, appleB = b.bundleID?.hasPrefix("com.apple.") == true
            if appleA != appleB { return appleA }
            return LaunchpadSearch.ordered(a, b)
        }
        func other(_ app: LaunchpadApp) -> Bool {
            app.path.contains("/Utilities/") || app.bundleID.map(otherApple.contains) == true
        }
        let tucked = sorted.filter(other)
        let apple = sorted.filter { !other($0) && $0.bundleID?.hasPrefix("com.apple.") == true }
        let rest = sorted.filter { !other($0) && $0.bundleID?.hasPrefix("com.apple.") != true }
        var items = apple.map { LaunchpadItem.app($0.path) }
        if !tucked.isEmpty {
            items.append(.folder(LaunchpadFolder(id: "other", name: otherName, apps: tucked.map(\.path))))
        }
        items += rest.map { .app($0.path) }
        return LaunchpadLayout(items: items)
    }

    /// 苹果自带的 App 在第一页的顺序（照旧版启动台，常用的在前）；没列到的苹果 App 按名字排在它们后面。
    static let appleOrder = [
        "com.apple.AppStore", "com.apple.Safari", "com.apple.mail", "com.apple.MobileSMS", "com.apple.FaceTime",
        "com.apple.Maps", "com.apple.Photos", "com.apple.iCal", "com.apple.AddressBook", "com.apple.reminders",
        "com.apple.Notes", "com.apple.freeform", "com.apple.Music", "com.apple.podcasts", "com.apple.TV",
        "com.apple.iBooksX", "com.apple.news", "com.apple.stocks", "com.apple.weather", "com.apple.clock",
        "com.apple.Home", "com.apple.findmy", "com.apple.VoiceMemos", "com.apple.journal", "com.apple.Passwords",
        "com.apple.ScreenContinuity", "com.apple.PhotoBooth", "com.apple.Preview", "com.apple.calculator",
        "com.apple.Dictionary", "com.apple.shortcuts", "com.apple.exposelauncher", "com.apple.systempreferences",
    ]

    /// 旧版启动台放进“其他”文件夹的几样（实用工具文件夹里的都算，这里是不在那个文件夹里的）。
    static let otherApple: Set<String> = [
        "com.apple.Chess", "com.apple.FontBook", "com.apple.Image_Capture", "com.apple.Stickies", "com.apple.TextEdit",
        "com.apple.Automator", "com.apple.backup.launcher", "com.apple.ScriptEditor2", "com.apple.Siri", "com.apple.Tips",
    ]

    /// 按这次扫到的 App 整理：已经删掉的 App 去掉，空了的文件夹去掉，新装的接在最后（iOS：新 App 放在最后一页）。
    func reconciled(with apps: [LaunchpadApp]) -> LaunchpadLayout {
        // 这次扫到的 App：同一个路径只算一次。主屏幕上的位置也是“先出现的赢”：
        // 顶层 App、文件夹里的 App、removed 依次认领路径，每个路径在整个 layout 里只出现一次。
        var present = Set<String>()
        let installed = apps.filter { present.insert($0.path).inserted }
        // 文件夹 ID 要唯一且非空：第一个用到的 ID 原样保留，重复的、空的都改成一个确定的新 ID，
        // 并且避开存档里所有出现过的 ID（包括稍后被删掉的文件夹占着的）。
        let reservedIDs = Set(self.items.compactMap(\.folderID).filter { !$0.isEmpty })
        var seenIDs = Set<String>()
        func repairedID(_ id: String) -> String {
            let base = id.isEmpty ? "folder" : id
            guard id.isEmpty || !seenIDs.insert(id).inserted else { return id }
            var suffix = 1
            while seenIDs.contains("\(base)-\(suffix)") || reservedIDs.contains("\(base)-\(suffix)") { suffix += 1 }
            let made = "\(base)-\(suffix)"
            seenIDs.insert(made)
            return made
        }
        var seen = Set<String>()
        var items: [LaunchpadItem] = []
        for item in self.items {
            switch item {
            case .app(let path):
                if present.contains(path), seen.insert(path).inserted { items.append(item) }
            case .folder(var folder):
                folder.id = repairedID(folder.id)
                folder.apps = folder.apps.filter { present.contains($0) && seen.insert($0).inserted }
                if !folder.apps.isEmpty { items.append(.folder(folder)) }
            }
        }
        let removed = self.removed.filter { present.contains($0) && seen.insert($0).inserted }
        let known = seen.union(removed)
        // installed 已经按路径去过重，所以同一个路径不会接进来两次。
        let fresh = installed.filter { !known.contains($0.path) }.sorted(by: LaunchpadSearch.ordered)
        items += fresh.map { .app($0.path) }
        return LaunchpadLayout(items: items, removed: removed)
    }

    /// 编辑时拖动一格到 to（其余依次让位）。
    mutating func move(from: Int, to: Int) {
        items = LaunchpadOrder.move(items, from: from, to: to)
    }

    /// 编辑时把一格 App 拖到另一格上：落在 App 上就一起建一个文件夹（名字用 suggested），落在文件夹上就放进去。
    /// 返回文件夹在哪一格。
    @discardableResult
    mutating func drop(_ dragged: Int, onto target: Int, suggested: String, id: String) -> Int? {
        guard items.indices.contains(dragged), items.indices.contains(target), dragged != target,
              case .app(let path) = items[dragged] else { return nil }
        switch items[target] {
        case .app(let other):
            items[target] = .folder(LaunchpadFolder(id: id, name: suggested, apps: [other, path]))
        case .folder(var folder):
            folder.apps.append(path)
            items[target] = .folder(folder)
        }
        items.remove(at: dragged)
        return dragged < target ? target - 1 : target
    }

    /// 从打开的文件夹里把一个 App 拖出来，放到主屏幕的 at 格；文件夹空了就去掉。
    mutating func takeOut(_ path: String, from id: String, at index: Int) {
        guard let folderIndex = items.firstIndex(where: { $0.folderID == id }),
              case .folder(var folder) = items[folderIndex], folder.apps.contains(path) else { return }
        folder.apps.removeAll { $0 == path }
        var target = min(max(index, 0), items.count)
        if folder.apps.isEmpty {
            items.remove(at: folderIndex)
            if folderIndex < target { target -= 1 }
        } else {
            items[folderIndex] = .folder(folder)
        }
        items.insert(.app(path), at: min(target, items.count))
    }

    /// 文件夹里的 App 重新排。
    mutating func reorder(in id: String, from: Int, to: Int) {
        guard let index = items.firstIndex(where: { $0.folderID == id }), case .folder(var folder) = items[index] else { return }
        folder.apps = LaunchpadOrder.move(folder.apps, from: from, to: to)
        items[index] = .folder(folder)
    }

    mutating func rename(_ id: String, to name: String) {
        guard let index = items.firstIndex(where: { $0.folderID == id }), case .folder(var folder) = items[index] else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.name = trimmed
        items[index] = .folder(folder)
    }

    /// “从主屏幕移除”：App 不删，只是不在主屏幕上，App 资料库里还有（iOS 的做法）。
    mutating func removeFromHome(_ path: String) {
        for (index, item) in items.enumerated() {
            switch item {
            case .app(let p) where p == path:
                items.remove(at: index)
                removed.append(path)
                return
            case .folder(var folder) where folder.apps.contains(path):
                folder.apps.removeAll { $0 == path }
                if folder.apps.isEmpty { items.remove(at: index) } else { items[index] = .folder(folder) }
                removed.append(path)
                return
            default:
                continue
            }
        }
    }

    /// 从 App 资料库拖回主屏幕（或者被移除后重新加回来）。
    mutating func addToHome(_ path: String, at index: Int? = nil) {
        guard !items.contains(where: { $0.paths.contains(path) }) else { return }
        removed.removeAll { $0 == path }
        items.insert(.app(path), at: min(max(index ?? items.count, 0), items.count))
    }
}

// MARK: - App 资料库

/// App 资料库里的一类：iOS 那样的分组（按 App 自己在 Info.plist 里写的类别归）。
struct LaunchpadCategory: Equatable {
    let id: String
    let title: String
    let apps: [LaunchpadApp]
}

enum LaunchpadLibrary {
    /// Info.plist 的 LSApplicationCategoryType 归到 iOS App 资料库的那几类（Mac 上开发工具多，单独一类）。
    static func group(for category: String?) -> String {
        guard let category, category.hasPrefix("public.app-category.") else { return "other" }
        let name = String(category.dropFirst("public.app-category.".count))
        if name.hasSuffix("games") { return "games" }
        switch name {
        case "utilities", "weather": return "utilities"
        case "developer-tools": return "developer"
        case "productivity", "business", "finance": return "productivity"
        case "social-networking": return "social"
        case "graphics-design", "photography", "video": return "creativity"
        case "music", "entertainment": return "entertainment"
        case "news", "reference", "books", "education", "magazines-newspapers": return "reading"
        case "healthcare-fitness", "medical", "sports": return "health"
        case "travel", "navigation": return "travel"
        case "food-drink", "shopping": return "shopping"
        default: return "other"
        }
    }

    static let titles: [String: String] = [
        "suggestions": "建议", "recent": "最近添加", "utilities": "工具", "developer": "开发工具", "productivity": "效率与财务",
        "social": "社交", "creativity": "创意", "entertainment": "娱乐", "reading": "信息与阅读", "health": "健康与健身",
        "travel": "旅行", "shopping": "购物与美食", "games": "游戏", "other": "其他",
    ]
    static let order = ["suggestions", "recent", "productivity", "creativity", "social", "entertainment", "utilities",
                        "developer", "reading", "health", "travel", "shopping", "games", "other"]

    /// 排好的各类：“建议”（最近用过的 4 个）、“最近添加”（最近装的，不算随系统更新的）在前，其余按固定顺序；
    /// 每类里按名字排；空的类不出现。
    static func categories(apps: [LaunchpadApp]) -> [LaunchpadCategory] {
        var groups: [String: [LaunchpadApp]] = [:]
        for app in apps { groups[group(for: app.category), default: []].append(app) }
        let used: [(LaunchpadApp, Date)] = apps.compactMap { app in app.lastUsed.map { (app, $0) } }
        groups["suggestions"] = Array(used.sorted { $0.1 > $1.1 }.prefix(4).map(\.0))
        let dated: [(LaunchpadApp, Date)] = apps.compactMap { app in
            app.path.hasPrefix("/System/") ? nil : app.added.map { (app, $0) }
        }
        groups["recent"] = Array(dated.sorted { $0.1 > $1.1 }.prefix(8).map(\.0))
        return order.compactMap { id in
            guard var list = groups[id], !list.isEmpty else { return nil }
            if id != "suggestions", id != "recent" { list.sort(by: LaunchpadSearch.ordered) }
            return LaunchpadCategory(id: id, title: titles[id] ?? id, apps: list)
        }
    }

    /// 新建文件夹时的名字：照 iOS，用落点那个 App 的类别（没写类别的叫“文件夹”）。
    static func folderName(for app: LaunchpadApp) -> String {
        let id = group(for: app.category)
        return id == "other" ? "文件夹" : titles[id] ?? "文件夹"
    }

    /// 搜索列表的分组字母：名字（中文按拼音）的第一个字母，不是字母的归到“#”。
    static func section(for app: LaunchpadApp) -> String {
        guard let first = app.pinyin.first, first.isASCII, first.isLetter else { return "#" }
        return first.uppercased()
    }
}
