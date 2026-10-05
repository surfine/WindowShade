// 真实 AppKit 视图的停留、取消和动画交错；不扫描应用、不写用户排列。
import Cocoa

func wlog(_ message: String) { print(message) }

@main
struct LaunchpadViewTests {
    @MainActor static func wait(_ seconds: Double) async {
        CATransaction.flush()
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let apps = (0..<90).map { LaunchpadApp(path: "/fixture/\($0).app", name: "App \($0)", bundleID: nil) }
            @MainActor func view(_ layout: LaunchpadLayout) -> LaunchpadView {
                let result = LaunchpadView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
                result.setContent(apps: apps, layout: layout)
                result.layoutSubtreeIfNeeded()
                return result
            }
            let plain = LaunchpadLayout(items: apps.map { .app($0.path) })
            let navigation = view(plain)
            navigation.pager.reduced = true
            navigation.settle(to: -1)
            precondition(navigation.tileIndex(at: navigation.grid.slot(0).center) == nil)
            precondition(navigation.badgeIndex(at: navigation.grid.slot(0).center) == nil)
            precondition(!navigation.today.root.isHidden && !navigation.today.items.isEmpty)
            navigation.goBack()
            precondition(navigation.pager.page == 0)
            navigation.pager.begin(at: 1); navigation.pager.drag(by: -1100, at: 1.1)
            navigation.pager.cancel(animated: false)
            precondition(navigation.pager.page == 0 && navigation.pager.position == 0)
            navigation.pager.begin(at: 2); navigation.pager.drag(by: -1100, at: 2.1); navigation.pager.end()
            precondition(navigation.pager.page == -1)
            navigation.pager.begin(at: 3); navigation.pager.drag(by: -2000, at: 3.1); navigation.pager.end()
            precondition(navigation.pager.page == -1)
            navigation.settle(to: 0)
            let dot = CGPoint(x: navigation.dots.frame.minX + 3.5, y: navigation.dots.frame.midY)
            guard case .page(0) = navigation.target(at: dot) else { preconditionFailure("page dot must remain clickable") }
            navigation.settle(to: navigation.homePages)
            precondition(navigation.pillAtTop && !navigation.pill.flat)
            navigation.settle(to: 0)
            // iPad 的排法：主屏幕这枚搜索是底部正中的玻璃胶囊（程序坞上面），页码点压在它上面。
            precondition(!navigation.pillAtTop && !navigation.pill.flat && navigation.field.superview === navigation.pill.content)
            let usable = navigation.usableArea()
            precondition(abs(navigation.pill.frame.midX - navigation.bounds.midX) < 1,
                         "and it is centred")
            precondition(navigation.pill.frame.midY > navigation.bounds.midY,
                         "the Home Screen search sits in the lower half, above the dock, like iPad")
            precondition(navigation.pill.frame.minY > 160,
                         "the notch grows down from the top; the search must stay clear of it")
            precondition(navigation.pill.frame.maxY <= usable.maxY - 6 && navigation.pill.frame.minY > usable.maxY - 62,
                         "right above the dock, inside the usable area")
            precondition(navigation.dots.frame.midY < navigation.pill.frame.minY,
                         "page dots sit above the search")
            navigation.beginPlacing(apps[0], at: CGPoint(x: 200, y: 200), source: nil)
            precondition(navigation.dots.opacity == 0)
            navigation.cancelPlacing()
            precondition(navigation.dots.opacity == 1)
            let merge = view(plain)
            await wait(0.1)
            merge.beginReorder(0, at: merge.screenCenter(of: 0))
            merge.moveReorder(to: merge.screenCenter(of: 1))
            await wait(0.45) // 此后不再发任何鼠标移动。
            precondition(merge.reorder?.merging == 1, "stationary drag must arm folder merge")
            merge.endReorder()
            precondition(merge.home.items.contains { Set($0.paths) == Set([apps[0].path, apps[1].path]) }, "release must create folder")
            precondition(merge.editDragTimer == nil)
            merge.closeFolder(animated: false)

            let edge = view(plain)
            edge.beginReorder(0, at: edge.screenCenter(of: 0))
            edge.moveReorder(to: CGPoint(x: 1430, y: 450))
            await wait(0.8)
            precondition(edge.pager.page == 1, "stationary edge drag must turn page")
            edge.endReorder()
            await wait(0.8)
            precondition(edge.pager.page == 1 && edge.editDragTimer == nil, "release must stop paging")

            let folders = LaunchpadLayout(items: [
                .folder(LaunchpadFolder(id: "a", name: "A", apps: apps.prefix(40).map(\.path))),
                .folder(LaunchpadFolder(id: "b", name: "B", apps: apps.suffix(40).map(\.path)))
            ])
            let nested = view(folders)
            nested.openFolder("a")
            await wait(0.6)
            let overlay = nested.folder!
            nested.beginFolderDrag(0, at: overlay.screenCenter(0))
            nested.moveFolderDrag(to: CGPoint(x: overlay.frame.maxX - 8, y: overlay.frame.midY))
            await wait(0.8)
            precondition(overlay.pager.page == 1, "stationary folder edge must turn page")
            nested.endFolderDrag(at: nil)
            precondition(nested.editDragTimer == nil)
            nested.closeFolder()
            nested.openFolder("b")
            await wait(0.8)
            precondition(nested.cells["folder:a"]?.root.opacity == 1, "old folder icon must reappear when another opens")
            precondition(nested.cells["folder:b"]?.root.opacity == 0, "new folder icon stays hidden while open")
            nested.closeFolder(animated: false)

            let cancelled = view(plain)
            var writes = 0
            cancelled.onLayoutChange = { _ in writes += 1 }
            cancelled.beginReorder(0, at: cancelled.screenCenter(of: 0))
            cancelled.moveReorder(to: cancelled.screenCenter(of: 1))
            _ = cancelled.animateOut(launching: false)
            await wait(0.8)
            precondition(cancelled.home == plain && writes == 0, "hide must not commit an unfinished drag")
            precondition(cancelled.reorder == nil && cancelled.editDragTimer == nil)
            // 扫描在拖动中返回，放下后不能把刚写好的顺序或文件夹覆盖。
            let refreshed = view(plain)
            var saved: LaunchpadLayout?
            refreshed.onLayoutChange = { saved = $0 }
            refreshed.beginReorder(0, at: refreshed.screenCenter(of: 0))
            refreshed.moveReorder(to: refreshed.screenCenter(of: 1))
            refreshed.setContent(apps: apps, layout: plain)
            await wait(0.4)
            refreshed.endReorder()
            precondition(refreshed.home.items.contains { Set($0.paths) == Set([apps[0].path, apps[1].path]) })
            precondition(refreshed.home == saved && refreshed.pendingContent == nil,
                         "late scan must preserve the committed folder and persisted layout")
            refreshed.closeFolder(animated: false)

            // 从文件夹拖出来、还没松手就 Esc：存储和内存都回到拿起之前。
            let extract = view(folders)
            var extractionWrites = 0
            extract.onLayoutChange = { _ in extractionWrites += 1 }
            extract.openFolder("a")
            await wait(0.55)
            let opened = extract.folder!
            extract.beginFolderDrag(0, at: opened.screenCenter(0))
            extract.moveFolderDrag(to: CGPoint(x: 20, y: 450))
            precondition(extract.reorder != nil && extract.home != folders,
                         "fixture must really pull an app out before cancellation")
            precondition(extractionWrites == 0, "a drag preview must not persist")
            extract.cancelEditDrag()
            precondition(extract.home == folders && extractionWrites == 0)
            precondition(extract.reorder == nil && extract.editDragTimer == nil)

            let outside = view(plain)
            var accidentalLaunch = false
            outside.onLaunch = { _, _ in accidentalLaunch = true }
            outside.beginPlacing(apps[0], at: CGPoint(x: 200, y: 200), source: nil)
            outside.endPlacing(at: CGPoint(x: -20, y: 200))
            precondition(!accidentalLaunch && outside.placing == nil, "releasing outside the launchpad must cancel, not launch")

            let pageLayer = CALayer()
            let paging = LaunchpadPager(strip: pageLayer)
            paging.width = 1440; paging.count = 4; paging.reduced = true
            paging.begin(at: 1); paging.drag(by: 1050, at: 1.1)
            paging.cancel()
            precondition(paging.page == 0 && !paging.tracking && paging.position == 0,
                         "cancelled gesture must not commit its velocity or displacement")
            paging.begin(at: 2); paging.drag(by: 1050, at: 2.1); paging.end()
            precondition(paging.page == 1, "ordinary release must still turn the page")
            precondition(pageLayer.animation(forKey: "page") == nil, "reduced motion has no sliding spring")

            let keyboard = view(plain)
            keyboard.libraryForProbe()
            keyboard.moveLibrarySelection(#selector(NSResponder.moveRight(_:)))
            var launched: LaunchpadApp?
            keyboard.onLaunch = { app, _ in launched = app }
            keyboard.activateLibrarySelection()
            precondition(launched != nil, "library categories must be operable with keyboard")
            keyboard.openListForProbe()
            precondition(keyboard.accessibilityChildren()?.contains { ($0 as? NSView) === keyboard.list } == true,
                         "VoiceOver must reach the actual search results table")

            // 资料库 ⇄ 第一页会给搜索框换底板（挪父视图）：键盘得留在搜索框里。Esc 从资料库回第一页，再 Esc 关掉。
            // 窗口只在内存里当键盘的家，不摆到屏幕上；Esc 走搜索框的 cancelOperation，和真按键同一条路。
            let focusWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                       styleMask: [.borderless], backing: .buffered, defer: true)
            let focus = view(plain)
            focus.pager.reduced = true
            focusWindow.contentView = focus
            var closes = 0
            focus.onClose = { closes += 1 }
            @MainActor func searchHasKeyboard() -> Bool { focus.field.currentEditor().map { focusWindow.firstResponder === $0 } == true }
            @MainActor func escape() {
                guard let editor = focus.field.currentEditor() as? NSTextView else {
                    preconditionFailure("Esc has nobody to take it: the search field lost the keyboard (responder=\(String(describing: focusWindow.firstResponder)))")
                }
                editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
            }
            focus.focusSearch()
            precondition(searchHasKeyboard(), "fixture: the search field must start with the keyboard")
            focus.settle(to: focus.homePages)
            precondition(focus.onLibrary && !focus.pill.flat && searchHasKeyboard(),
                         "turning to the App Library must keep the keyboard in the search field")
            escape()
            precondition(focus.pageForProbe == 0 && !focus.pillAtTop && closes == 0,
                         "Esc in the App Library must come back to the first page")
            precondition(searchHasKeyboard(), "after Esc from the App Library the search field must still have the keyboard")
            escape()
            precondition(closes == 1, "a second Esc on the first page must close Launchpad")
            focusWindow.contentView = nil

            let frost = LaunchpadFrostLayer()
            frost.refresh(opaque: true, contrast: false)
            precondition(frost.backgroundFilters == nil && frost.backgroundColor?.alpha == 1)
            frost.refresh(opaque: false, contrast: true)
            precondition(frost.backgroundFilters == nil && frost.borderWidth >= 1)
            frost.refresh(opaque: false, contrast: false)
            precondition(frost.backgroundFilters?.isEmpty == false)

            // 旧1x结果晚于新2x任务：旧完成不能清除新任务或把新图换回去。
            var completions: [([LaunchpadArtwork.Drawing]) -> Void] = []
            let artwork = LaunchpadArtwork(renderer: { _, _, _, done in completions.append(done) })
            var arrivals = 0
            artwork.request([apps[0]], width: 100, scale: 1) { _ in arrivals += 1 }
            artwork.request([apps[0]], width: 140, scale: 2) { _ in arrivals += 1 }
            precondition(completions.count == 2)
            completions[0]([.init(path: apps[0].path, icon: nil, label: nil)])
            await wait(0.02)
            artwork.request([apps[0]], width: 140, scale: 2) { _ in arrivals += 1 }
            precondition(completions.count == 2 && arrivals == 0,
                         "old completion must not clear the current in-flight reservation")
            completions[1]([.init(path: apps[0].path, icon: nil, label: nil)])
            await wait(0.02)
            artwork.request([apps[0]], width: 140, scale: 2) { _ in arrivals += 1 }
            precondition(arrivals == 1 && completions.count == 2,
                         "failed artwork is cached for this generation instead of retrying every frame")
            print("PASS: scan/edit ordering, folder pull-out rollback, pager cancellation, library keyboard/VoiceOver, Esc from the App Library keeps the keyboard, material fallback, stale artwork generations")
            print("PASS: Launchpad view — stationary merge, home/folder edge paging, release, rapid folder switch, hide cancellation")
            exit(0)
        }
        app.run()
    }
}
