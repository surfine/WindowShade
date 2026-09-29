import CoreGraphics
import Foundation

@main struct LaunchpadModelTests {
  static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }

  static func main() {
    let t0 = Date(timeIntervalSince1970: 0)

    let finder = LaunchpadApp(path: "/System/Library/CoreServices/Finder.app", name: "Finder", bundleID: "com.apple.finder")
    let calculator = LaunchpadApp(path: "/System/Applications/Calculator.app", name: "计算器", bundleID: "com.apple.calculator")
    let wechat = LaunchpadApp(path: "/Applications/WeChat.app", name: "微信", bundleID: "com.tencent.xin")
    let keynote = LaunchpadApp(path: "/Applications/Keynote.app", name: "Keynote", bundleID: "com.apple.iWork.Keynote")
    let safari = LaunchpadApp(path: "/System/Applications/Safari.app", name: "Safari", bundleID: "com.apple.Safari")
    let terminal = LaunchpadApp(path: "/System/Applications/Utilities/Terminal.app", name: "Terminal", bundleID: "com.apple.Terminal")
    let appStore = LaunchpadApp(path: "/System/Applications/App Store.app", name: "App Store", bundleID: "com.apple.AppStore")
    let chess = LaunchpadApp(path: "/System/Applications/Chess.app", name: "Chess", bundleID: "com.apple.Chess")
    let pages = LaunchpadApp(path: "/Applications/Pages.app", name: "Pages", bundleID: "com.apple.iWork.Pages")
    let numbers = LaunchpadApp(path: "/Applications/Numbers.app", name: "Numbers", bundleID: "com.apple.iWork.Numbers")

    // 中文的拼音转换是模型的前提：先验证假设，再写依赖它的检查。
    do {
      expect(calculator.pinyin == "jisuanqi", "计算器 transliterates to the full pinyin jisuanqi")
      expect(calculator.initials == "jsq", "计算器 has the initials jsq")
      expect(wechat.pinyin == "weixin", "微信 transliterates to weixin")
      expect(wechat.initials == "wx", "微信 has the initials wx")
    }

    // 搜索：中文可以打全拼，也可以只打首字母。
    do {
      let all = [finder, calculator, wechat, keynote]
      expect(LaunchpadSearch.filter(all, query: "jisuanqi").map(\.path) == [calculator.path],
             "a Chinese name matches its full pinyin")
      expect(LaunchpadSearch.filter(all, query: "jsq").map(\.path) == [calculator.path],
             "a Chinese name matches its pinyin initials")
      expect(LaunchpadSearch.filter(all, query: "weixin").contains(wechat),
             "微信 matches the full pinyin weixin")
      expect(LaunchpadSearch.filter(all, query: "wx").contains(wechat),
             "微信 matches the initials wx")
    }

    // 搜索的排序：名字开头的匹配排在名字中间的匹配前面。
    do {
      let prefix = LaunchpadApp(path: "/Applications/Foo.app", name: "Page", bundleID: nil)
      let mid = LaunchpadApp(path: "/Applications/Bar.app", name: "Homepage", bundleID: nil)
      expect(LaunchpadSearch.score(prefix, query: "page") > LaunchpadSearch.score(mid, query: "page"),
             "a name-prefix match outranks a mid-name match")
      let ranked = LaunchpadSearch.filter([mid, prefix], query: "page")
      expect(ranked.map(\.path) == [prefix.path, mid.path],
             "the prefix match comes first in the results")
    }

    // 搜索：空查询保留全部，不匹配的被丢掉。
    do {
      let all = [finder, calculator, wechat, keynote]
      expect(LaunchpadSearch.filter(all, query: "").count == all.count, "an empty query keeps everything")
      expect(LaunchpadSearch.filter(all, query: "   ").count == all.count, "a whitespace query keeps everything")
      expect(LaunchpadSearch.filter(all, query: "zzz").isEmpty, "a query with no match drops everything")
      expect(LaunchpadSearch.filter(all, query: "key").map(\.path) == [keynote.path],
             "filter drops the apps that do not match")
    }

    // 排序：中文按拼音和英文混排（jisuanqi 落在 Finder 和 Keynote 之间）。
    do {
      let sorted = [keynote, calculator, finder].sorted(by: LaunchpadSearch.ordered)
      expect(sorted.map(\.name) == ["Finder", "计算器", "Keynote"],
             "pinyin interleaves with English names: Finder, 计算器, Keynote")
    }

    // 格子：宽屏 7 列，窄屏 6 列，都是 5 行。
    do {
      let wide = LaunchpadGrid.layout(for: CGSize(width: 1440, height: 900))
      expect(wide.columns == 7, "a 1440×900 screen gets 7 columns")
      expect(wide.rows == 5, "a 1440×900 screen gets 5 rows")
      let narrow = LaunchpadGrid.layout(for: CGSize(width: 1024, height: 768))
      expect(narrow.columns == 6, "a 1024×768 screen gets 6 columns")
      expect(narrow.rows == 5, "a 1024×768 screen gets 5 rows")
    }

    // 页数：空的时候也算一页；正好一页是一页；多一个 App 就多一页。
    do {
      let grid = LaunchpadGrid.layout(for: CGSize(width: 1440, height: 900))
      expect(grid.pages(for: 0) == 1, "an empty launchpad still shows one page")
      expect(grid.pages(for: grid.perPage) == 1, "exactly one page of apps fits on one page")
      expect(grid.pages(for: grid.perPage + 1) == 2, "one app past a page starts a second page")
    }

    // 格子中心和坐标来回算：第 i 个格子的中心落在第 i 个格子上，页数也对。
    do {
      let grid = LaunchpadGrid.layout(for: CGSize(width: 1440, height: 900))
      for i in [0, 1, grid.columns - 1, grid.columns, grid.perPage - 1, grid.perPage, grid.perPage + 3] {
        let slot = grid.slot(i)
        expect(slot.page == i / grid.perPage, "slot \(i) reports the right page")
        expect(grid.index(at: slot.center, page: slot.page) == i,
               "the centre of slot \(i) round-trips to index \(i)")
      }
      let outside = CGPoint(x: grid.area.minX - 10, y: grid.area.midY)
      expect(grid.index(at: outside, page: 0) == nil, "a point outside the area gives no index")
      let below = CGPoint(x: grid.area.midX, y: grid.area.maxY + 10)
      expect(grid.index(at: below, page: 0) == nil, "a point below the area gives no index")
    }

    // 程序坞常显时，格子区域的下边要往上让。
    do {
      let docked = LaunchpadGrid.layout(for: CGSize(width: 1440, height: 900), dock: 80)
      let plain = LaunchpadGrid.layout(for: CGSize(width: 1440, height: 900), dock: 0)
      expect(docked.area.maxY <= plain.area.maxY && docked.area.maxY < 900 - 80, "reserved bottom margin keeps icons above a visible dock")
      let tallDock = LaunchpadGrid.layout(for: CGSize(width: 1440, height: 900), dock: 220)
      expect(tallDock.area.maxY < docked.area.maxY, "a dock taller than the reserved margin moves the grid up")
      expect(docked.perPage == plain.perPage, "the dock does not change how many apps fit on a page")
    }

    // 翻页：慢慢拖一点点留在原地；拖过半页翻一页；轻轻一甩也算。
    do {
      expect(LaunchpadPaging.settle(page: 2, offset: 0.2, velocity: 0, pages: 5) == 2,
             "a small slow drag stays on the same page")
      expect(LaunchpadPaging.settle(page: 2, offset: 0.7, velocity: 0, pages: 5) == 3,
             "a drag past half a page turns one page")
      expect(LaunchpadPaging.settle(page: 2, offset: 0.1, velocity: 2000, pages: 5) == 3,
             "a fast flick with a small offset still turns the page")
      expect(LaunchpadPaging.settle(page: 2, offset: 0.1, velocity: -2000, pages: 5) == 1,
             "a fast flick backwards turns back one page")
    }

    // 翻页：再快也只翻一页；到顶到头就停住。
    do {
      expect(LaunchpadPaging.settle(page: 2, offset: 0, velocity: 100000, pages: 6) == 3,
             "a huge velocity still only turns one page")
      expect(LaunchpadPaging.settle(page: 2, offset: 0.9, velocity: -100000, pages: 6) == 1,
             "a huge backwards velocity only turns back one page")
      expect(LaunchpadPaging.settle(page: 0, offset: -0.9, velocity: 0, pages: 5) == 0,
             "the first page clamps against dragging backwards")
      expect(LaunchpadPaging.settle(page: 4, offset: 0.9, velocity: 0, pages: 5) == 4,
             "the last page clamps against dragging forwards")
    }

    // 橡皮筋：越拖越沉、永远追不上手指、方向跟着输入。
    do {
      let width = 1000.0
      let small = LaunchpadPaging.rubberBand(-100, width: width)
      let big = LaunchpadPaging.rubberBand(-400, width: width)
      expect(small < 0 && big < 0, "the rubber band keeps the sign of the input")
      expect(abs(big) > abs(small), "the rubber band grows with how far past the edge you drag")
      expect(abs(big) < width, "the rubber band stays below the limit width")
      expect(LaunchpadPaging.rubberBand(0, width: width) == 0, "no overshoot is no rubber band")
    }

    // 拖放落点：1000×800 的屏幕。
    do {
      let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
      expect(LaunchpadDrop.zone(at: CGPoint(x: 10, y: 400), in: screen) == .slideOver(left: true),
             "a point in the far left strip means slide over on the left")
      expect(LaunchpadDrop.zone(at: CGPoint(x: 990, y: 400), in: screen) == .slideOver(left: false),
             "a point in the far right strip means slide over on the right")
      expect(LaunchpadDrop.zone(at: CGPoint(x: 200, y: 400), in: screen) == .half(left: true),
             "a mid-left point means the left half")
      expect(LaunchpadDrop.zone(at: CGPoint(x: 200, y: 50), in: screen) == .quarter(left: true, top: true),
             "a top-left corner point means the top-left quarter")
      expect(LaunchpadDrop.zone(at: CGPoint(x: 800, y: 780), in: screen) == .quarter(left: false, top: false),
             "a bottom-right corner point means the bottom-right quarter")
      expect(LaunchpadDrop.zone(at: CGPoint(x: 500, y: 40), in: screen) == .fill,
             "a point at the top centre means fill the screen")
      expect(LaunchpadDrop.zone(at: CGPoint(x: 500, y: 400), in: screen) == .open,
             "a point in the centre means open normally")
    }

    // 刘海：只有传进了刘海矩形时，落在里面的点才算 notch；没传就照常按位置分。
    do {
      let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
      let notch = CGRect(x: 420, y: 0, width: 160, height: 32)
      let inside = CGPoint(x: notch.midX, y: notch.midY)
      expect(LaunchpadDrop.zone(at: inside, in: screen, notch: notch) == .notch,
             "a point inside the passed notch rect means notch")
      expect(LaunchpadDrop.zone(at: inside, in: screen, notch: CGRect(x: 0, y: 0, width: 10, height: 10)) == .fill,
             "the same point is not notch when it falls outside the passed rect")
      expect(LaunchpadDrop.zone(at: inside, in: screen) == .fill,
             "without a notch rect the top-centre point stays fill, so existing drops keep working")
    }

    // 第一次排主屏幕：苹果自带的在前（appleOrder 的次序），然后是“其他”文件夹，最后是别的 App（按名字）。
    do {
      var third: [LaunchpadApp] = []
      for name in ["Zebra", "Aurora", "Mango", "Banana"] {
        third.append(LaunchpadApp(path: "/Applications/\(name).app", name: name, bundleID: "com.example.\(name)"))
      }
      let layout = LaunchpadLayout.initial(apps: [terminal, chess, safari, appStore, pages, numbers] + third,
                                           otherName: "其他")
      expect(layout.items.count == 4 + 1 + third.count, "apple apps, one folder and the third-party apps")
      guard layout.items.count == 4 + 1 + third.count else { return }
      expect(layout.items[0] == .app(appStore.path), "App Store comes before Safari in appleOrder")
      expect(layout.items[1] == .app(safari.path), "Safari is the second apple app")
      expect(layout.items[2] == .app(numbers.path) && layout.items[3] == .app(pages.path),
             "apple apps with unlisted bundle ids follow in name order")
      guard case .folder(let other) = layout.items[4] else {
        expect(false, "the fifth slot is the 其他 folder")
        return
      }
      expect(other.id == "other", "the tucked-away folder has the id other")
      expect(other.name == "其他", "the tucked-away folder is named as asked")
      expect(other.apps == [chess.path, terminal.path],
             "Chess (a tucked-away apple app) and Terminal (in Utilities) both go into the folder")
      let tail = layout.items.dropFirst(5).flatMap { $0.paths }
      expect(tail == third.sorted(by: LaunchpadSearch.ordered).map(\.path),
             "third-party apps follow after the folder, in name order")
    }

    // 第一次排主屏幕：没有实用工具、也没列进“其他”的苹果 App，就没有文件夹。
    do {
      let layout = LaunchpadLayout.initial(apps: [safari, appStore, pages], otherName: "其他")
      expect(layout.items.allSatisfy { $0.folderID == nil }, "with no utilities there is no folder")
      expect(layout.items.map(\.paths).flatMap { $0 } == [appStore.path, safari.path, pages.path],
             "apple apps come first, then the rest")
    }

    // 整理：删掉的不见了，空文件夹没了，新装的接在最后。
    do {
      let folder = LaunchpadFolder(id: "f1", name: "Work", apps: [terminal.path, chess.path])
      var layout = LaunchpadLayout(items: [.app(safari.path), .folder(folder)], removed: [])
      let gone = LaunchpadApp(path: "/Applications/Gone.app", name: "Gone", bundleID: "com.example.Gone")
      let fresh = LaunchpadApp(path: "/Applications/Zed.app", name: "Zed", bundleID: "com.example.Zed")
      layout = layout.reconciled(with: [safari, terminal, fresh])
      expect(layout.items.first == .app(safari.path), "an installed app stays where it was")
      guard case .folder(let kept)? = layout.items.count > 1 ? layout.items[1] : nil else {
        expect(false, "the folder survives while it still holds apps")
        return
      }
      expect(kept.apps == [terminal.path], "an uninstalled app disappears from inside a folder")
      expect(layout.items.last == .app(fresh.path), "a newly installed app is appended at the end")
      _ = gone

      var short = LaunchpadLayout(items: [.folder(LaunchpadFolder(id: "f1", name: "Work", apps: [terminal.path]))],
                                  removed: [])
      short = short.reconciled(with: [safari])
      expect(short.items == [.app(safari.path)], "a folder that empties out disappears")
    }

    // 整理：被“从主屏幕移除”的 App 不回来；删掉了就不在 removed 里了。
    do {
      let layout = LaunchpadLayout(items: [.app(safari.path)], removed: [pages.path])
      let kept = layout.reconciled(with: [safari, pages])
      expect(kept.items == [.app(safari.path)], "an app removed from the home screen stays off it")
      expect(kept.removed == [pages.path], "removed keeps tracking the app while it is installed")
      let uninstalled = layout.reconciled(with: [safari])
      expect(uninstalled.removed.isEmpty, "removed forgets an app that was uninstalled")
    }

    // 整理：同一个路径列了两次，只留第一次的位置。
    do {
      let layout = LaunchpadLayout(items: [.app(safari.path), .app(pages.path), .app(safari.path)], removed: [])
      let once = layout.reconciled(with: [safari, pages])
      expect(once.items == [.app(safari.path), .app(pages.path)],
             "a path listed twice keeps only its first position")
    }

    // 整理：目录里重复扫到的路径不能在主屏幕上出现两份。
    do {
      let layout = LaunchpadLayout(items: []).reconciled(with: [safari, pages, safari, safari])
      expect(layout.items == [.app(pages.path), .app(safari.path)],
             "a repeated catalogue path is laid out once, ordered by name")
      expect(LaunchpadLayout.initial(apps: [safari, pages, safari], otherName: "其他").items
               == [.app(safari.path), .app(pages.path)],
             "initial drops duplicate catalogue paths and keeps the first entry")
    }

    // 整理：同一个路径横跨主页、文件夹和 removed 时只留一处，先出现的位置赢，顺序不变。
    do {
      let reused = LaunchpadLayout(items: [
        .folder(LaunchpadFolder(id: "f1", name: "Work", apps: [pages.path, safari.path])),
        .app(safari.path),
        .app(pages.path),
      ], removed: [safari.path, terminal.path])
      let fixed = reused.reconciled(with: [safari, pages, terminal])
      expect(fixed.items.count == 1, "a folder keeps its slot and nothing is duplicated outside it")
      guard case .folder(let only)? = fixed.items.first else {
        expect(false, "the folder survives reconciliation")
        return
      }
      expect(only.apps == [pages.path, safari.path],
             "the folder keeps its own order and the first claim on each path")
      expect(fixed.removed == [terminal.path],
             "an app inside a folder is not also recorded as removed")
    }

    // 整理：存档里的文件夹 ID 重复或为空时改成唯一的值，已有合法 ID 不动。
    do {
      let broken = LaunchpadLayout(items: [
        .folder(LaunchpadFolder(id: "", name: "Empty", apps: [safari.path])),
        .folder(LaunchpadFolder(id: "f1", name: "One", apps: [pages.path])),
        .folder(LaunchpadFolder(id: "f1", name: "Two", apps: [terminal.path])),
      ])
      let patched = broken.reconciled(with: [safari, pages, terminal])
      let ids = patched.items.compactMap(\.folderID)
      let names = patched.items.compactMap { item -> String? in
        if case .folder(let folder) = item { return folder.name }
        return nil
      }
      expect(ids.count == 3, "all three folders survive with an app each")
      expect(!ids.contains(where: \.isEmpty), "an empty folder id is replaced with a nonempty one")
      expect(Set(ids).count == 3, "duplicate folder ids all become unique")
      expect(ids[1] == "f1", "first valid folder ID is preserved even when a later folder duplicates it")
      expect(names == ["Empty", "One", "Two"], "repairing ids keeps the folders' names and order")

      // 一个没有被重复引用的合法 ID 保留原样。
      let unique = LaunchpadLayout(items: [
        .folder(LaunchpadFolder(id: "keep", name: "Keep", apps: [safari.path])),
        .folder(LaunchpadFolder(id: "", name: "Nameless", apps: [pages.path])),
      ]).reconciled(with: [safari, pages])
      expect(unique.items.compactMap(\.folderID) == ["keep", "folder-1"],
             "an id nobody else uses is kept verbatim while an empty id is repaired")

      let again = patched.reconciled(with: [safari, pages, terminal])
      expect(again == patched, "reconciling an already repaired layout changes nothing")
      expect(broken.reconciled(with: [safari, pages, terminal]) == patched,
             "the same malformed layout always repairs to the same ids")
      var edits = patched
      edits.move(from: 2, to: 0)
      expect(edits.reconciled(with: [safari, pages, terminal]) == edits,
             "the user's ordering survives reconciliation")
    }

    // 拖动：App 落在 App 上建文件夹，落在文件夹里就放进去。
    do {
      let dropper = LaunchpadApp(path: "/Applications/Cursor.app", name: "Cursor", bundleID: "com.example.Cursor")
      var layout = LaunchpadLayout(items: [.app(safari.path), .app(dropper.path)])
      let index = layout.drop(0, onto: 1, suggested: "Work", id: "new")
      expect(index == 0, "dropping onto the next slot reports the folder's position")
      expect(layout.items == [.folder(LaunchpadFolder(id: "new", name: "Work",
                                                      apps: [dropper.path, safari.path]))],
             "the folder keeps the target first and the dragged app second, named as suggested")

      var backwards = LaunchpadLayout(items: [.app(dropper.path), .app(safari.path)])
      expect(backwards.drop(1, onto: 0, suggested: "Work", id: "new") == 0,
             "dragging backwards onto a slot keeps the folder at the target's position")
      expect(backwards.items.first?.folderID == "new",
             "the folder sits where the target app was")

      var intoFolder = LaunchpadLayout(items: [
        .folder(LaunchpadFolder(id: "f1", name: "Work", apps: [safari.path])), .app(dropper.path)])
      expect(intoFolder.drop(1, onto: 0, suggested: "Ignored", id: "new") == 0,
             "dropping onto a folder reports that folder's position")
      guard case .folder(let grown)? = intoFolder.items.first else {
        expect(false, "the folder is still a folder")
        return
      }
      expect(grown.apps == [safari.path, dropper.path], "dropping onto a folder appends the app")
      expect(intoFolder.items.count == 1, "the dragged slot is gone after dropping onto a folder")
    }

    // 拖动：拖文件夹不动；拖到自己身上不动。
    do {
      let layout = LaunchpadLayout(items: [
        .folder(LaunchpadFolder(id: "f1", name: "Work", apps: [safari.path])), .app(pages.path)])
      var dragged = layout
      expect(dragged.drop(0, onto: 1, suggested: "Work", id: "new") == nil,
             "dragging a folder returns no index")
      expect(dragged == layout, "dragging a folder changes nothing")
      expect(dragged.drop(1, onto: 1, suggested: "Self", id: "new") == nil,
             "dropping an app onto itself returns no index")
      expect(dragged == layout, "dropping an app onto itself changes nothing")
    }

    // 从文件夹里拿出来：App 回到主屏幕上的指定位置；文件夹空了就消失。
    do {
      let folder = LaunchpadFolder(id: "f1", name: "Work", apps: [safari.path, terminal.path])
      var layout = LaunchpadLayout(items: [.folder(folder), .app(pages.path), .app(numbers.path)])
      layout.takeOut(safari.path, from: "f1", at: 2)
      expect(layout.items.count == 4, "taking an app out adds a slot")
      expect(layout.items[2] == .app(safari.path), "the app comes out at the requested index")
      guard case .folder(let shrunk) = layout.items[0] else {
        expect(false, "the folder stays while it still holds apps")
        return
      }
      expect(shrunk.apps == [terminal.path], "the app leaves the folder")

      var single = LaunchpadLayout(items: [
        .folder(LaunchpadFolder(id: "f1", name: "Work", apps: [safari.path])), .app(pages.path)])
      single.takeOut(safari.path, from: "f1", at: 1)
      expect(single.items == [.app(safari.path), .app(pages.path)],
             "an emptied folder disappears and the insertion index accounts for that")
    }

    // 文件夹里重排：拖到后面、拖到前面都对。
    do {
      let folder = LaunchpadFolder(id: "f1", name: "Work", apps: [safari.path, terminal.path, pages.path])
      var layout = LaunchpadLayout(items: [.folder(folder), .app(numbers.path)])
      layout.reorder(in: "f1", from: 0, to: 2)
      guard case .folder(let forward) = layout.items.first! else {
        expect(false, "the folder is still there after reordering")
        return
      }
      expect(forward.apps == [terminal.path, pages.path, safari.path],
             "reordering inside a folder moves the app to the end")
      layout.reorder(in: "f1", from: 2, to: 0)
      guard case .folder(let back) = layout.items.first! else {
        expect(false, "the folder is still there after reordering back")
        return
      }
      expect(back.apps == [safari.path, terminal.path, pages.path],
             "reordering inside a folder moves the app back to the front")
    }

    // 重命名：掐掉空格；空名字不算。
    do {
      var layout = LaunchpadLayout(items: [
        .folder(LaunchpadFolder(id: "f1", name: "Work", apps: [safari.path]))])
      layout.rename("f1", to: "  项目 \n")
      if case .folder(let named) = layout.items.first! {
        expect(named.name == "项目", "renaming trims surrounding whitespace")
      } else {
        expect(false, "the folder is still there after renaming")
      }
      layout.rename("f1", to: "   ")
      if case .folder(let kept) = layout.items.first! {
        expect(kept.name == "项目", "an empty name is ignored")
      } else {
        expect(false, "the folder is still there after an empty rename")
      }
      layout.rename("nope", to: "X")
      expect(layout.items.count == 1, "renaming an unknown folder does nothing")
    }

    // 从主屏幕移除：顶层的 App 和文件夹里的 App 都能移除，空文件夹消失，去的 App 记在 removed 里。
    do {
      var layout = LaunchpadLayout(items: [.app(safari.path), .app(pages.path)])
      layout.removeFromHome(safari.path)
      expect(layout.items == [.app(pages.path)], "removing a top-level app takes its slot away")
      expect(layout.removed == [safari.path], "the app lands in removed")

      var inside = LaunchpadLayout(items: [
        .folder(LaunchpadFolder(id: "f1", name: "Work", apps: [safari.path])), .app(pages.path)])
      inside.removeFromHome(safari.path)
      expect(inside.items == [.app(pages.path)], "removing the only app in a folder drops the folder")
      expect(inside.removed == [safari.path], "the app removed from a folder lands in removed too")
    }

    // 加回主屏幕：从 removed 里清掉，重复的不会再加一份。
    do {
      var layout = LaunchpadLayout(items: [.app(safari.path)], removed: [pages.path])
      layout.addToHome(pages.path)
      expect(layout.items == [.app(safari.path), .app(pages.path)], "adding an app puts it back at the end")
      expect(layout.removed.isEmpty, "adding an app clears it from removed")
      layout.addToHome(pages.path)
      expect(layout.items == [.app(safari.path), .app(pages.path)],
             "an app already on the home screen is never added twice")
      layout.addToHome(terminal.path, at: 0)
      expect(layout.items.first == .app(terminal.path), "adding at an index inserts there")
      var inFolder = LaunchpadLayout(items: [
        .folder(LaunchpadFolder(id: "f1", name: "Work", apps: [terminal.path]))], removed: [])
      inFolder.addToHome(terminal.path)
      expect(inFolder.items.count == 1 && inFolder.items[0].folderID == "f1",
             "an app inside a folder is not added to the top level again")
    }

    // 存下来再读回来：一模一样。
    do {
      let layout = LaunchpadLayout(items: [
        .app(safari.path),
        .folder(LaunchpadFolder(id: "f1", name: "Work", apps: [terminal.path, chess.path])),
        .app(pages.path)],
        removed: [numbers.path])
      let encoder = JSONEncoder()
      let decoder = JSONDecoder()
      let data = try! encoder.encode(layout)
      let restored = try! decoder.decode(LaunchpadLayout.self, from: data)
      expect(restored == layout, "a layout with apps, a folder and removed entries round-trips through JSON")
    }

    // 资料库归组：按 Info.plist 的类别，认不出来的都进 other。
    do {
      expect(LaunchpadLibrary.group(for: "public.app-category.developer-tools") == "developer",
             "developer tools get their own group")
      expect(LaunchpadLibrary.group(for: "public.app-category.weather") == "utilities",
             "weather joins the utilities group")
      expect(LaunchpadLibrary.group(for: nil) == "other", "an app with no category lands in other")
      expect(LaunchpadLibrary.group(for: "com.example.weird") == "other",
             "a category that is not an app category lands in other")
      expect(LaunchpadLibrary.group(for: "public.app-category.mystery") == "other",
             "an unknown app category lands in other")
      expect(LaunchpadLibrary.group(for: "public.app-category.board-games") == "games",
             "board games join the games group")
      expect(LaunchpadLibrary.group(for: "public.app-category.stroke-games") == "games",
             "any category ending in games joins the games group")
    }

    // 资料库的分组：建议、最近添加、固定顺序、空的不出现、每类按名字排。
    do {
      let older = LaunchpadApp(path: "/Applications/Old.app", name: "Old", bundleID: "com.example.Old",
                               category: "public.app-category.productivity",
                               added: t0, lastUsed: t0)
      let newer = LaunchpadApp(path: "/Applications/New.app", name: "New", bundleID: "com.example.New",
                               category: "public.app-category.productivity",
                               added: t0.addingTimeInterval(100), lastUsed: t0.addingTimeInterval(100))
      let dev = LaunchpadApp(path: "/Applications/Code.app", name: "Code", bundleID: "com.example.Code",
                             category: "public.app-category.developer-tools",
                             added: t0.addingTimeInterval(50), lastUsed: t0.addingTimeInterval(50))
      let system = LaunchpadApp(path: "/System/Applications/Safari.app", name: "Safari", bundleID: "com.apple.Safari",
                                category: "public.app-category.productivity",
                                added: t0.addingTimeInterval(300), lastUsed: t0.addingTimeInterval(300))

      let groups = LaunchpadLibrary.categories(apps: [older, newer, dev, system])
      expect(groups.map(\.id) == LaunchpadLibrary.order.filter { ["suggestions", "recent", "productivity", "developer"].contains($0) },
             "group ids appear in the library order")
      let suggestions = groups.first { $0.id == "suggestions" }
      expect(suggestions?.apps.map(\.path) == [system.path, newer.path, dev.path, older.path],
             "suggestions holds the four most recently used apps, newest first")
      let recent = groups.first { $0.id == "recent" }
      expect(recent?.apps.map(\.path) == [newer.path, dev.path, older.path],
             "recent skips apps under /System/ and orders by added, newest first")
      expect(groups.first { $0.id == "productivity" }?.apps.map(\.name) == ["New", "Old", "Safari"],
             "a regular group is sorted by name order (pinyin)")
      expect(!groups.contains { $0.apps.isEmpty }, "empty groups are absent")
      expect(!groups.contains { $0.id == "games" }, "a group with no apps does not appear")

      var many: [LaunchpadApp] = []
      for i in 0..<12 {
        many.append(LaunchpadApp(path: "/Applications/M\(i).app", name: "M\(i)", bundleID: "com.example.M\(i)",
                                 category: "public.app-category.social", added: t0.addingTimeInterval(Double(i))))
      }
      let capped = LaunchpadLibrary.categories(apps: many)
      expect(capped.first { $0.id == "recent" }?.apps.count == 8, "recent keeps at most eight apps")

      let onlyOld = LaunchpadApp(path: "/Applications/Hidden.app", name: "Hidden", bundleID: "com.example.Hidden",
                                 category: nil, added: nil, lastUsed: nil)
      let bare = LaunchpadLibrary.categories(apps: [onlyOld])
      expect(!bare.contains { $0.id == "recent" },
             "recent only holds apps that have an added date")
      expect(!bare.contains { $0.id == "suggestions" }, "suggestions appears only when something was used")
      let noneUsed = LaunchpadLibrary.categories(apps: [LaunchpadApp(path: "/Applications/Fresh.app", name: "Fresh",
                                                                     bundleID: "com.example.Fresh",
                                                                     category: nil, added: t0, lastUsed: nil)])
      expect(!noneUsed.contains { $0.id == "suggestions" },
             "never used apps leave the suggestions group empty and absent")
    }

    // 文件夹名字：照落点 App 的类别；认不出来就叫“文件夹”。
    do {
      let productive = LaunchpadApp(path: "/Applications/Office.app", name: "Office", bundleID: "com.example.Office",
                                    category: "public.app-category.productivity")
      let unknown = LaunchpadApp(path: "/Applications/Blob.app", name: "Blob", bundleID: "com.example.Blob",
                                 category: nil)
      expect(LaunchpadLibrary.folderName(for: productive) == "效率与财务",
             "a productivity app names the folder 效率与财务")
      expect(LaunchpadLibrary.folderName(for: unknown) == "文件夹",
             "an uncategorised app names the folder 文件夹")
    }

    // 搜索列表的分组字母：中文按拼音，别的按首字母，数字和符号归到 “#”。
    do {
      expect(LaunchpadLibrary.section(for: calculator) == "J", "计算器 sorts under J (jisuanqi)")
      expect(LaunchpadLibrary.section(for: safari) == "S", "Safari sorts under S")
      let digit = LaunchpadApp(path: "/Applications/1Password.app", name: "1Password", bundleID: nil)
      expect(LaunchpadLibrary.section(for: digit) == "#", "a name starting with a digit sorts under #")
    }

    // 过期拖放事件和存储脏数据不能复制入口或制造非法下标。
    do {
      let folder = LaunchpadFolder(id: "f", name: "Work", apps: [safari.path])
      var layout = LaunchpadLayout(items: [.folder(folder), .app(pages.path)])
      let original = layout
      layout.takeOut(pages.path, from: "f", at: 0)
      expect(layout == original, "taking a path not in the folder must be a no-op")
      layout.addToHome(terminal.path, at: -10)
      expect(layout.items.first == .app(terminal.path), "negative insertion clamps to the first slot")
      let dirty = LaunchpadLayout(items: [.app(safari.path)], removed: [pages.path, pages.path])
      expect(dirty.reconciled(with: [safari, pages]).removed == [pages.path],
             "reconciliation removes duplicate hidden entries")
    }

    // 竖放的外接屏：5 列 × 7 行，图标不缩成小点。
        do {
            let portrait = LaunchpadGrid.layout(for: CGSize(width: 1080, height: 1920))
            expect(portrait.columns == 5 && portrait.rows == 7, "a portrait display gets 5 columns and 7 rows")
            expect(portrait.icon >= 80, "icons on a portrait display stay about as big as on a landscape one (\(portrait.icon))")
            let landscape = LaunchpadGrid.layout(for: CGSize(width: 1710, height: 1107))
            expect(landscape.columns == 7 && landscape.rows == 5, "landscape is unchanged")
        }

        print("PASS: launchpad model — pinyin search and ranking, grid layout and slots, paging settle and rubber band, "
          + "drop zones, initial layout and the 其他 folder, reconcile, drop and folders, take out and reorder, rename, "
          + "remove/add home, JSON round trip, App Library grouping, suggestions/recent, folder names and sections")
  }
}
