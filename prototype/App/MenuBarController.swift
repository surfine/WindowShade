// 菜单栏控制器：状态栏图标、菜单重建与菜单代理回调。
// 作为 AppDelegate 扩展实现，动作目标仍是主实现的 @objc 方法。

import Cocoa

extension AppDelegate {
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        statusItem.button?.image = makeStatusBarIcon()
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.toolTip = "WindowShade"
        rebuildMenu()
    }
    func rebuildMenu() {
        if suppressMenuRebuilds {
            pendingMenuRebuild = true
            return
        }
        // 这里绝不能解析当前 AX 窗口：菜单重建可能由点击、前台切换、会话变化
        // 高频触发；目标解析在后台完成后仅在目标改变时安排下一次重建。
        menuRebuildWorkItem?.cancel()
        menuRebuildWorkItem = nil
        statusItem.button?.image = makeStatusBarIcon()
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.title = shaded.isEmpty ? "" : " \(shaded.count)"
        statusItem.button?.toolTip = shaded.isEmpty ? "WindowShade" : "WindowShade: \(shaded.count) folded"
        statusMenu.removeAllItems()
        let toggle = NSMenuItem(title: foldToggleMenuTitle(), action: #selector(toggleAction), keyEquivalent: "c")
        toggle.keyEquivalentModifierMask = [.control, .command]
        statusMenu.addItem(toggle)

        if appearanceMode == .proxyTitleBar {
            let focus = NSMenuItem(title: focusMenuTitle(), action: #selector(focusCurrentAppAction), keyEquivalent: "0")
            focus.keyEquivalentModifierMask = [.control, .command]
            focus.isEnabled = AXIsProcessTrusted()
            statusMenu.addItem(focus)
        } else {
            let arrangeTitle = hasArrangedOverlayFrames ? "恢复卷帘条原位" : "整理卷帘条"
            let arrange = NSMenuItem(title: arrangeTitle, action: #selector(arrangeShadedWindows), keyEquivalent: "0")
            arrange.keyEquivalentModifierMask = [.control, .command]
            arrange.isEnabled = shaded.values.contains { $0.overlay != nil }
            statusMenu.addItem(arrange)
        }

        let doubleClick = NSMenuItem(title: "双击标题栏以折叠", action: #selector(toggleTitlebarDoubleClick(_:)), keyEquivalent: "")
        doubleClick.state = titlebarDoubleClickEnabled ? .on : .off
        statusMenu.addItem(doubleClick)

        statusMenu.addItem(.separator())
        let pinnedPreview = NSMenuItem(title: pinnedPreviewMenuTitle(),
                                       action: #selector(togglePinnedPreviewAction),
                                       keyEquivalent: "p")
        pinnedPreview.keyEquivalentModifierMask = [.control, .command]
        pinnedPreview.isEnabled = AXIsProcessTrusted()
            && hasScreenRecordingPermission()
        statusMenu.addItem(pinnedPreview)
        addPinnedPreviewMenuSection()

        if !shaded.isEmpty {
            statusMenu.addItem(.separator())
            let header = NSMenuItem(title: "已折叠窗口（按快捷键展开）", action: nil, keyEquivalent: "")
            header.isEnabled = false
            statusMenu.addItem(header)
            for (index, entry) in sortedShadedEntries().enumerated() {
                let (id, state) = entry
                let title = descriptiveDisplayTitle(appName: state.appName, windowTitle: state.title)
                let key = index < 9 ? "\(index + 1)" : ""
                let itemTitle = key.isEmpty ? title : "\(key)  \(title)"
                let item = NSMenuItem(title: itemTitle, action: #selector(unshadeFromMenu(_:)), keyEquivalent: key)
                item.keyEquivalentModifierMask = key.isEmpty ? [] : [.control, .command]
                item.target = self
                item.representedObject = NSNumber(value: id)
                statusMenu.addItem(item)
            }
            // 与「全部取消置顶」对称：仅在有已折叠窗口时才显示「全部展开」。
            statusMenu.addItem(.separator())
            let restore = NSMenuItem(title: "全部展开", action: #selector(restoreAll), keyEquivalent: "")
            statusMenu.addItem(restore)
        } else {
            statusMenu.addItem(.separator())
            let empty = NSMenuItem(title: "没有已折叠窗口", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            statusMenu.addItem(empty)
        }

        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "欢迎与使用说明...", action: #selector(showWelcomeGuide), keyEquivalent: "")
        statusMenu.addItem(withTitle: "偏好设置...", action: #selector(showPreferences), keyEquivalent: ",")
        statusMenu.addItem(withTitle: "退出 WindowShade", action: #selector(quit), keyEquivalent: "q")
        updateReconcileTimer()
    }
    func addPinnedPreviewMenuSection() {
        statusMenu.addItem(.separator())

        let entries = pinnedPreviewController.menuEntries()
        guard !entries.isEmpty else {
            let empty = NSMenuItem(title: "没有已置顶窗口", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            statusMenu.addItem(empty)
            return
        }

        let header = NSMenuItem(title: "已置顶窗口（点击取消）", action: nil, keyEquivalent: "")
        header.isEnabled = false
        statusMenu.addItem(header)

        for (index, entry) in entries.enumerated() {
            let item = NSMenuItem(title: menuTitleForPinnedPreview(entry, index: index),
                                  action: #selector(cancelPinnedPreviewMenuItem(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: entry.id)
            statusMenu.addItem(item)
        }

        statusMenu.addItem(.separator())
        // 老板键：暂时隐藏/恢复全部置顶预览（连带停止/恢复 capture），与下面
        // 「全部取消置顶」不同——不清空会话，按一次就能原样恢复。
        let suspendAll = NSMenuItem(title: pinnedPreviewController.suspendAllMenuTitle(),
                                    action: #selector(toggleSuspendPinnedPreviewsAction),
                                    keyEquivalent: "")
        suspendAll.target = self
        statusMenu.addItem(suspendAll)

        let stopPinnedPreviews = NSMenuItem(title: "全部取消置顶",
                                            action: #selector(stopAllPinnedPreviewsAction),
                                            keyEquivalent: "")
        stopPinnedPreviews.target = self
        statusMenu.addItem(stopPinnedPreviews)
    }
    func menuTitleForPinnedPreview(_ entry: PinnedPreviewMenuEntry, index: Int) -> String {
        let raw = entry.displayTitle
        let maxCount = 42
        let title = raw.count > maxCount ? String(raw.prefix(maxCount - 1)) + "…" : raw
        return "\(index + 1)  \(title)"
    }
    func scheduleMenuRebuild(delay: TimeInterval = 0.04) {
        if suppressMenuRebuilds {
            pendingMenuRebuild = true
            return
        }
        menuRebuildWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.menuRebuildWorkItem = nil
            self?.rebuildMenu()
        }
        menuRebuildWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    func withMenuRebuildSuppressed(_ body: () -> Void) {
        let wasSuppressed = suppressMenuRebuilds
        suppressMenuRebuilds = true
        body()
        suppressMenuRebuilds = wasSuppressed
        if !suppressMenuRebuilds, pendingMenuRebuild {
            pendingMenuRebuild = false
            rebuildMenu()
        }
    }
    func setAppearanceMode(_ mode: ShadeAppearanceMode) {
        appearanceMode = mode == .proxyTitleBar ? .proxyTitleBar : .nativeScreenshot
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: shadeAppearanceModeDefaultsKey)
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
    }
    func menuDidClose(_ menu: NSMenu) {
        hideMenuHoverPreview()
        menuPreviewHoverID = nil
        menuPreviewAnchor = nil
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu, !isUpdatingMenuFromDelegate else { return }
        isUpdatingMenuFromDelegate = true
        defer { isUpdatingMenuFromDelegate = false }
        // 先用最近一次快照即时展示菜单，再后台校正下一次菜单内容；不能为一个
        // 动态标题把菜单打开和系统鼠标输入阻塞在目标 app 的 AX timeout 上。
        refreshPinnedPreviewTarget(reason: "menu-needs-update")
        rebuildMenu()
    }
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard menu === statusMenu else { return }
        hideMenuHoverPreview()
        menuPreviewHoverID = nil
        menuPreviewAnchor = nil
        guard let item,
              let n = item.representedObject as? NSNumber else { return }
        let mouse = NSEvent.mouseLocation
        let id = CGWindowID(n.uint32Value)
        let anchor = estimatedStatusMenuItemAnchor(near: mouse)
        menuPreviewHoverID = id
        menuPreviewAnchor = anchor
        showMenuHoverPreview(id, anchor: anchor)
    }
    func sortedShadedEntries() -> [(CGWindowID, ShadeState)] {
        shaded.sorted {
            if $0.value.appName != $1.value.appName { return $0.value.appName < $1.value.appName }
            let aTitle = descriptiveDisplayTitle(appName: $0.value.appName, windowTitle: $0.value.title)
            let bTitle = descriptiveDisplayTitle(appName: $1.value.appName, windowTitle: $1.value.title)
            if aTitle != bTitle { return aTitle < bTitle }
            return $0.key < $1.key
        }
    }
    func focusMenuTitle() -> String {
        guard let session = focusSession else { return "专注当前 App" }
        switch session.stage {
        case .arrangedAway:
            return "专注：显示卷帘条原位"
        case .barsRestoredHome:
            return "专注：恢复专注前状态"
        }
    }
    var hasArrangedOverlayFrames: Bool {
        arrangedOverlayFrames.keys.contains { shaded[$0]?.overlay != nil }
    }
    func foldToggleMenuTitle() -> String {
        guard !shaded.isEmpty else { return "折叠当前窗口" }
        if currentShadedOverlayID() != nil { return "展开当前窗口" }
        if let id = pinnedPreviewController.currentTargetWindowID, shaded[id] != nil {
            return "展开当前窗口"
        }
        return "折叠当前窗口"
    }
    func pinnedPreviewMenuTitle() -> String {
        pinnedPreviewController.currentTargetMenuTitle()
    }
}
