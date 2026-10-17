import Foundation

// 设置搜索（1.0.18 新表面稿第 2 节）：同义词表和 copy-guide「不要用」那一列一致、拼音、同义词、排序、
// 命中区间、空结果、藏着的页不出现、最多 30 条（纯逻辑，不开窗口）。
@main
struct SettingsSearchTests {
  static func main() {
    synonymsMatchCopyGuide()
    synonymRowsParse()
    let index = SettingsSearchIndex(entries: sampleEntries, synonyms: SettingsSearchSynonyms.sourceGroups)
    func names(_ query: String, visible: Set<String>? = nil) -> [String] {
      index.search(query, visiblePages: visible).map(\.entry.name.shown)
    }

    // 名字开头 → 名字里有：“收起”开头的两行在前，名字里有“收起”的接着。
    let rollUp = names("收起")
    precondition(Array(rollUp.prefix(2)) == ["收起后的样子", "收起和展开时播放音效"], "名字开头的在前：\(rollUp)")
    precondition(rollUp.contains("双击标题栏收起窗口"), "名字里有的也在：\(rollUp)")
    precondition(rollUp.firstIndex(of: "双击标题栏收起窗口")! > 1, "名字里有的排在名字开头的后面：\(rollUp)")

    // 拼音：全拼、首字母都找得到（复用启动台的匹配）。
    precondition(names("sq").first == "收起后的样子", "首字母 sq 找到收起：\(names("sq"))")
    precondition(names("shouqi").contains("收起后的样子"), "全拼 shouqi：\(names("shouqi"))")
    precondition(names("liufeng").contains("窗口之间留缝"), "全拼中间：\(names("liufeng"))")

    // 同义词：从 copy-guide「不要用」那一列来，结果说明靠哪个说法找到的。
    let hide = index.search("隐藏")
    precondition(!hide.isEmpty, "“隐藏”靠同义词找到收起")
    precondition(hide.contains { $0.entry.name.shown == "双击标题栏收起窗口" && $0.reason == .synonym("隐藏") },
                 "“隐藏”找到双击标题栏收起窗口：\(hide.map(\.entry.name.shown))")
    precondition(names("隐").contains("收起后的样子"), "打一个字“隐”就出：\(names("隐"))")
    precondition(names("隱藏").contains("双击标题栏收起窗口"), "繁体“隱藏”按简体比：\(names("隱藏"))")
    precondition(names("灵动岛").first == "收进刘海", "灵动岛 → 收进刘海：\(names("灵动岛"))")
    precondition(names("minimize").contains("双击标题栏收起窗口"), "英文 minimize：\(names("minimize"))")
    precondition(names("taskbar").contains("Dock 悬停查看窗口"), "taskbar → 窗口浏览：\(names("taskbar"))")
    precondition(names("缝").first == "窗口之间留缝", "缝：\(names("缝"))")
    precondition(names("spacing").first == "窗口之间留缝", "spacing → 窗口之间留缝：\(names("spacing"))")

    // 选项：命中分段控件里的某一段，记下第几段。
    let wide = index.search("宽")
    precondition(wide.first?.entry.name.shown == "窗口之间留缝" && wide.first?.option == 2 && wide.first?.reason == .option,
                 "“宽”命中留缝的第 3 段：\(wide)")
    let thumbnail = index.search("thumbnail")
    precondition(thumbnail.first?.entry.name.shown == "收起后的样子" && thumbnail.first?.option == 2,
                 "thumbnail 找到收起后的样子的缩略图那一段：\(thumbnail)")

    // 排序：名字 > 同义词 > 选项 > 副标题 > 页名。
    let order = index.search("刘海")
    precondition(order.first?.entry.name.shown == "收进刘海" && order.first?.reason == .name, "名字里有刘海的最前：\(order)")
    let subtitle = index.search("轻轻")
    precondition(subtitle.map(\.reason) == [.subtitle], "副标题命中：\(subtitle)")
    let page = index.search("高级")
    precondition(page.allSatisfy { $0.reason == .page } && page.map(\.entry.name.shown) == ["界面语言", "诊断日志"],
                 "页名命中只排在最后、按行序：\(page)")
    let mixed = index.search("音效")
    precondition(mixed.first?.entry.name.shown == "收起和展开时播放音效", "名字里有的排在同义词前面：\(mixed)")

    // 命中区间：标的是显示那句里的字（UTF-16），大小写、全半角不分。
    precondition(index.search("留缝").first?.highlight == NSRange(location: 4, length: 2), "留缝的区间")
    precondition(SettingsSearch.highlight(of: "ＤＯＣＫ", in: "Dock 悬停查看窗口") == NSRange(location: 0, length: 4), "全角大写也标得出")
    precondition(index.search("sq").first?.highlight == nil, "拼音命中不标字")

    // 当前语言是英文时：英文名字最前；简体源句一样找得到，只是低一点。
    let english = SettingsSearchIndex(entries: [
      entry("shade", 0, SettingsSearchText("Gap between windows", alternates: ["窗口之间留缝"])),
      entry("shade", 1, SettingsSearchText("Glance", alternates: ["看一眼"])),
    ], synonyms: SettingsSearchSynonyms.sourceGroups)
    precondition(english.search("gap").first?.score == 100, "英文名字开头")
    precondition(english.search("留缝").first?.entry.name.shown == "Gap between windows", "英文界面打中文也找得到")
    precondition(english.search("peek").first?.entry.name.shown == "Glance", "peek → Glance（同义词按简体名字找到）")

    // 没找到：空，不出“0 个结果”这种行（由界面写“没有找到”）。
    precondition(index.search("xyz").isEmpty, "xyz 没有结果")
    precondition(index.search("   ").isEmpty, "只有空白不搜")
    precondition(index.search("s").count <= SettingsSearch.limit, "最多 30 条")

    // 藏着的页（预览旗标关着的 WindowShade 2 页）不出现。
    precondition(names("平滑").contains("平滑滚动"), "页开着时找得到")
    let visible: Set<String> = ["shade", "notch", "browser", "advanced"]
    precondition(!names("平滑", visible: visible).contains("平滑滚动"), "藏着的页不出现")
    precondition(names("smooth", visible: visible).isEmpty, "藏着的页的同义词也不出现")

    let many = SettingsSearchIndex(entries: (0..<80).map { entry("shade", $0, SettingsSearchText("收起 \($0)")) }, synonyms: [])
    precondition(many.search("收起").count == 30, "最多 30 条")

    print("PASS: settings search synonyms, pinyin, ranking, highlight, empty, hidden pages")
  }

  /// copy-guide 三张固定词汇表「不要用」那一列里的每个词，都在同义词表的简体源句里（不分大小写）。
  /// 括号里的说明、「说原因：」这类前缀不算词；两格不是词（是对写法的要求），列在 notTerms 里。
  static func synonymsMatchCopyGuide() {
    let notTerms: Set<String> = ["照中文逐字直译", "不认识的型号冒充别的名字"]
    guard let guide = try? String(contentsOfFile: "docs/copy-guide.md", encoding: .utf8) else {
      preconditionFailure("从仓库根目录跑：读不到 docs/copy-guide.md")
    }
    var terms: [String] = []
    var inTable = false
    for line in guide.components(separatedBy: "\n") {
      guard line.hasPrefix("|") else { inTable = false; continue }
      let cells = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
      if cells.count >= 3, cells[2] == "不要用" { inTable = true; continue }
      guard inTable, cells.count >= 3, !cells[0].allSatisfy({ "-: ".contains($0) }) else { continue }
      let cell = cells[2].replacingOccurrences(of: "（[^）]*）", with: "", options: .regularExpression)
      for raw in cell.split(whereSeparator: { "、,，".contains($0) }) {
        var term = raw.trimmingCharacters(in: .whitespaces)
        if let colon = term.firstIndex(of: "：") { term = String(term[term.index(after: colon)...]).trimmingCharacters(in: .whitespaces) }
        if !term.isEmpty, !notTerms.contains(term) { terms.append(term) }
      }
    }
    precondition(terms.count > 250, "copy-guide 的「不要用」列读出来太少（\(terms.count)），表头变了？")
    let typed = Set(SettingsSearchSynonyms.sourceGroups.flatMap(\.typed).map(SettingsSearch.normalize))
    let missing = terms.filter { !typed.contains(SettingsSearch.normalize($0)) }
    precondition(missing.isEmpty, "copy-guide「不要用」里有词不在 SettingsSearchSynonyms：\(missing)")
  }

  static func synonymRowsParse() {
    var keys: Set<String> = []
    for text in SettingsSearchSynonyms.table {
      precondition(text.key.hasPrefix("settings.search.synonym."), "键名：\(text.key)")
      precondition(keys.insert(text.key).inserted, "重复的组：\(text.key)")
      let parsed = SettingsSynonymGroup.parse(text.zh)
      precondition(!parsed.typed.isEmpty && !parsed.targets.isEmpty, "格式是「说法、… → 名字、…」：\(text.key)")
    }
  }

  static func entry(_ page: String, _ order: Int, _ name: SettingsSearchText, subtitle: String? = nil,
                    options: [String] = []) -> SettingsSearchEntry {
    let pages = ["shade": "卷帘", "notch": "刘海", "browser": "窗口浏览", "advanced": "高级", "pointer": "鼠标与触控板"]
    return SettingsSearchEntry(page: page, order: order, pageName: SettingsSearchText(pages[page] ?? page), key: nil, name: name,
                               subtitle: subtitle.map { SettingsSearchText($0) }, options: options.map { SettingsSearchText($0) })
  }

  static var sampleEntries: [SettingsSearchEntry] {
    var order = 0
    func row(_ page: String, _ name: String, _ subtitle: String? = nil, _ options: [String] = []) -> SettingsSearchEntry {
      defer { order += 1 }
      return entry(page, order, SettingsSearchText(name), subtitle: subtitle, options: options)
    }
    return [
      row("shade", "双击标题栏收起窗口", "双击标题栏"),
      row("shade", "收起后的样子", nil, ["跟原来一样", "统一标题栏", "缩略图"]),
      row("shade", "窗口之间留缝", "排好的窗口之间", ["不留", "窄", "宽"]),
      row("shade", "收起和展开时播放音效", "轻轻一声"),
      row("notch", "收进刘海", "朝刘海甩一下标题栏"),
      row("notch", "实时活动", "音乐、下载、计时器"),
      row("browser", "Dock 悬停查看窗口", "停一下，这个 App 的窗口排出来"),
      row("advanced", "界面语言", "切换后立即生效"),
      row("advanced", "诊断日志", "出问题时导出"),
      row("pointer", "平滑滚动", nil, ["关", "轻", "中", "像触控板"]),
    ]
  }
}
