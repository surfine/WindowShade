import Cocoa

// 启动台「卸载 App」：右键菜单 → 扫描计划 → 勾选式确认浮层 → 逐条移废纸篓（可找回）。
// 目录清单与"共用数据保护"思路参考 Mole（GPL-3.0，只借思路）；实现原创 Swift。
//
// 规矩：
// - 开关默认关（Launchpad.uninstall.enabled，ReleaseDefaults 总账）；没真机验过不放开。
// - 系统域、WindowShade 自己，菜单里就不出现；确认浮层再核一遍（计划层拦截）。
// - App 在运行：先走系统退出（系统自己问没保存的内容），退干净才让勾文件。
// - 删除唯一出口是废纸篓；逐条执行，失败如实回报，不中断。

enum LaunchpadUninstallAvailability {

    static let defaultsKey = "Launchpad.uninstall.enabled"

    static var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: defaultsKey) as? Bool) ?? ReleaseDefaults.value(defaultsKey)
    }

    /// 菜单项是否出现：功能开着、不是系统域、不是 WindowShade 自己。
    static func menuItemEnabled(appPath: String) -> Bool {
        guard isEnabled else { return false }
        let plan = WS2AppUninstallPlan.isBlocked(appPath: appPath, selfBundlePath: Bundle.main.bundlePath)
        return plan == .none
    }
}

/// 确认浮层：图标 + 名字 + 总大小，勾选式文件清单，确认后逐条移废纸篓。
@MainActor
final class LaunchpadUninstallOverlay: NSView {

    enum State: Equatable {
        case quittingApp                       // App 在运行：等它退干净
        case reviewing([WS2AppUninstallItem])  // 勾选式复核
        case trashing                          // 执行中
        case done(trashed: Int, failures: [WS2AppUninstallItem])
    }

    private var state: State = .quittingApp
    private let plan: WS2AppUninstallPlan.Result
    private let app: LaunchpadApp
    private let runningApp: NSRunningApplication?
    private var checked = Set<String>()
    private let onDismiss: () -> Void
    private let onFinished: (_ trashed: Int, _ displayName: String) -> Void
    private var quitWatch: Task<Void, Never>?

    // 界面件
    private let iconView = NSImageView()
    private var appIcon: NSImage?
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let listScrollView = NSScrollView()
    private let listTable = NSTableView()
    private let trashButton = NSButton(title: "移到废纸篓", target: nil, action: nil)
    private let cancelButton = NSButton(title: "先不删", target: nil, action: nil)
    private let quitButton = NSButton(title: "退出 App", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private var toggleAllButton: NSButton?
    private var rows: [WS2AppUninstallItem] = []

    var onCancel: (() -> Void)?  // Esc / 先不删

    init(app: LaunchpadApp, plan: WS2AppUninstallPlan.Result, runningApp: NSRunningApplication?,
         onDismiss: @escaping () -> Void, onFinished: @escaping (Int, String) -> Void) {
        self.app = app
        self.plan = plan
        self.runningApp = runningApp
        self.onDismiss = onDismiss
        self.onFinished = onFinished

        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous

        appIcon = NSWorkspace.shared.icon(forFile: app.path)
        iconView.image = appIcon
        iconView.setAccessibilityElement(true)
        iconView.setAccessibilityLabel("\(app.name) 的图标")
        iconView.frame = NSRect(x: 20, y: 20, width: 48, height: 48)
        addSubview(iconView)

        titleLabel.stringValue = app.name
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.frame = NSRect(x: 80, y: 48, width: 340, height: 22)
        addSubview(titleLabel)

        let sizeText = ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file)
        statusLabel.stringValue = "卸载后可从废纸篓找回 · 共 \(sizeText)"
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 80, y: 26, width: 340, height: 18)
        addSubview(statusLabel)

        listScrollView.hasVerticalScroller = true
        listScrollView.frame = NSRect(x: 20, y: 120, width: 400, height: 260)
        listScrollView.borderType = .bezelBorder
        addSubview(listScrollView)

        // 全选 / 全不选（清单长时逐条点太累）；App 本体始终保留勾选。
        let toggleAll = NSButton(title: "全不选", target: nil, action: nil)
        toggleAll.bezelStyle = .rounded
        toggleAll.controlSize = .small
        toggleAll.frame = NSRect(x: 20, y: 92, width: 80, height: 22)
        toggleAll.target = self
        toggleAll.action = #selector(toggleAllPressed(_:))
        addSubview(toggleAll)
        toggleAllButton = toggleAll

        listTable.headerView = nil
        let column = NSTableColumn(identifier: .init("item"))
        column.width = 380
        listTable.addTableColumn(column)
        listTable.dataSource = self
        listTable.delegate = self
        listTable.rowHeight = 26
        listTable.selectionHighlightStyle = .none
        listScrollView.documentView = listTable

        trashButton.bezelStyle = .rounded
        trashButton.setAccessibilityLabel("把勾选的文件移到废纸篓")
        trashButton.keyEquivalent = "\r"
        trashButton.frame = NSRect(x: 268, y: 66, width: 152, height: 32)
        trashButton.target = self
        trashButton.action = #selector(trashPressed)
        addSubview(trashButton)

        cancelButton.bezelStyle = .rounded
        cancelButton.setAccessibilityLabel("先不删，回到启动台")
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.frame = NSRect(x: 20, y: 66, width: 90, height: 32)
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        addSubview(cancelButton)

        quitButton.bezelStyle = .rounded
        quitButton.frame = NSRect(x: 20, y: 120, width: 400, height: 260)
        quitButton.target = self
        quitButton.action = #selector(quitPressed)
        addSubview(quitButton)

        if runningApp == nil {
            quitButton.removeFromSuperview()
            enterReview()
        } else {
            showQuitting()
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool {
        get { true }
    }

    // MARK: 状态机

    private func showQuitting() {
        state = .quittingApp
        statusLabel.stringValue = "App 正在运行——先退出它（系统会问没保存的内容）"
        listScrollView.isHidden = true
        trashButton.isEnabled = false
        quitButton.isHidden = false
    }

    @objc private func quitPressed() {
        guard let runningApp else { enterReview(); return }
        runningApp.terminate()
        statusLabel.stringValue = "正在退出…"
        trashButton.isEnabled = false
        quitWatch?.cancel()
        quitWatch = Task { [weak self] in
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                if runningApp.isTerminated { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            await MainActor.run { [weak self] in
                self?.enterReview()
            }
        }
    }

    private func enterReview() {
        quitWatch?.cancel()
        guard window != nil else { return } // 浮层已被取消拆掉：不重建状态
        quitButton.removeFromSuperview()
        listScrollView.isHidden = false
        rows = plan.items
        checked = Set(rows.map(\.path))
        state = .reviewing(rows)
        statusLabel.stringValue = "勾选要一并移到废纸篓的关联文件（可找回）"
        listTable.reloadData()
        refreshButtons()
    }

    private func refreshButtons() {
        let selected = rows.filter { checked.contains($0.path) }
        trashButton.isEnabled = selected.contains { $0.isAppBundle } && state == .reviewing(rows)
        // 全不选之后按钮变「全选」；App 本体那一条永远勾着，不算进全不选。
        if let toggleAllButton, case .reviewing = state {
            let optional = rows.filter { !$0.isAppBundle }
            let allOn = !optional.isEmpty && optional.allSatisfy { checked.contains($0.path) }
            toggleAllButton.title = allOn ? "全不选" : "全选"
        }
    }

    @objc private func toggleAllPressed(_ sender: NSButton) {
        guard case .reviewing = state else { return }
        let optional = rows.filter { !$0.isAppBundle }
        let allOn = !optional.isEmpty && optional.allSatisfy { checked.contains($0.path) }
        if allOn {
            for row in optional { checked.remove(row.path) }
        } else {
            for row in optional { checked.insert(row.path) }
        }
        listTable.reloadData()
        refreshButtons()
    }

    @objc private func trashPressed() {
        guard case .reviewing = state else { return }
        let selected = rows.filter { checked.contains($0.path) }
        guard selected.contains(where: \.isAppBundle) else { return }
        state = .trashing
        trashButton.isEnabled = false
        statusLabel.stringValue = "正在移到废纸篓…"
        spinner.isIndeterminate = true
        spinner.controlSize = .small
        spinner.frame = NSRect(x: 20, y: 92, width: 16, height: 16)
        spinner.startAnimation(nil)
        addSubview(spinner)
        let paths = selected.map(\.path)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = WS2AppUninstallTrash.trash(paths)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.spinner.stopAnimation(nil)
                    self.spinner.removeFromSuperview()
                    let failures = self.rows.filter { outcome.failures.contains($0.path) }
                    self.state = .done(trashed: outcome.trashed.count, failures: failures)
                    if failures.isEmpty {
                        self.statusLabel.stringValue = "已移到废纸篓 \(outcome.trashed.count) 项"
                        self.trashButton.title = "完成"
                        self.trashButton.setAccessibilityLabel("关闭卸载面板")
                        self.trashButton.keyEquivalent = "\r"
                        self.trashButton.action = #selector(self.finishPressed)
                    } else {
                        self.statusLabel.stringValue = "移到废纸篓 \(outcome.trashed.count) 项，\(failures.count) 项没成功（可能被占用）"
                        // 失败项留在清单里，可改勾后重试。
                        self.rows = failures + self.rows.filter { $0.isAppBundle && self.checked.contains($0.path) && !outcome.failures.contains($0.path) }
                        self.checked = Set(self.rows.map(\.path))
                        self.listTable.reloadData()
                        self.trashButton.title = "重试失败项"
                        self.trashButton.setAccessibilityLabel("重试没成功的文件")
                        self.trashButton.isEnabled = true
                        self.trashButton.action = #selector(self.retryPressed)
                    }
                }
            }
        }
    }

    @objc private func retryPressed() {
        guard case .done(_, let failures) = state else { return }
        let retryPaths = Set(failures.map(\.path))
        let stillChecked = rows.filter { checked.contains($0.path) && retryPaths.contains($0.path) }
        guard !stillChecked.isEmpty else { finishPressed(); return }
        state = .trashing
        trashButton.isEnabled = false
        trashButton.title = "移到废纸篓"
        statusLabel.stringValue = "正在移到废纸篓…"
        spinner.isIndeterminate = true
        spinner.frame = NSRect(x: 20, y: 92, width: 16, height: 16)
        spinner.startAnimation(nil)
        addSubview(spinner)
        let paths = stillChecked.map(\.path)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = WS2AppUninstallTrash.trash(paths)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self else { return }
                    self.spinner.stopAnimation(nil)
                    self.spinner.removeFromSuperview()
                    let left = self.rows.filter { outcome.failures.contains($0.path) }
                    self.state = .done(trashed: outcome.trashed.count, failures: left)
                    if left.isEmpty {
                        self.statusLabel.stringValue = "已移到废纸篓"
                        self.trashButton.title = "完成"
                        self.trashButton.setAccessibilityLabel("关闭卸载面板")
                        self.trashButton.keyEquivalent = "\r"
                        self.trashButton.action = #selector(self.finishPressed)
                    } else {
                        self.statusLabel.stringValue = "还有 \(left.count) 项没成功"
                    }
                    self.trashButton.isEnabled = true
                }
            }
        }
    }

    @objc private func finishPressed() {
        let displayName = app.name
        let count: Int
        if case .done(let trashed, _) = state { count = trashed } else { count = 0 }
        onFinished(count, displayName)
    }

    @objc private func cancelPressed() { abandon() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { abandon() } else { super.keyDown(with: event) }
    }

    /// 取消：停掉等退出的轮询，再交回宿主拆浮层。
    private func abandon() {
        quitWatch?.cancel()
        onCancel?()
    }
}

extension LaunchpadUninstallOverlay: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }
        let item = rows[row]
        let cell = tableView.makeView(withIdentifier: .init("check"), owner: nil) as? NSButton
            ?? NSButton(checkboxWithTitle: "", target: nil, action: nil)
        cell.identifier = .init("check")
        cell.title = groupLabel(item) + "  ·  " + shortPath(item.path)
        cell.font = .systemFont(ofSize: 11)
        cell.state = checked.contains(item.path) ? .on : .off
        cell.target = self
        cell.action = #selector(checkToggled(_:))
        return cell
    }

    @objc private func checkToggled(_ sender: NSButton) {
        let row = listTable.row(for: sender)
        guard row < rows.count else { return }
        let path = rows[row].path
        if sender.state == .on { checked.insert(path) } else { checked.remove(path) }
        // App 本体必须勾着才能删（没本体就没意义）；本体取消勾选时清掉其余勾选。
        if rows[row].isAppBundle, sender.state != .on { checked = [path].isEmpty ? checked : checked.filter { $0 == path } }
        refreshButtons()
        listTable.reloadData()
    }

    private func groupLabel(_ item: WS2AppUninstallItem) -> String {
        let size = ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)
        let name: String
        switch item.group {
        case .app: name = "App 本体"
        case .preferences: name = "偏好设置"
        case .appSupport: name = "应用支持"
        case .caches: name = "缓存"
        case .savedState: name = "窗口状态"
        case .webKit: name = "网页数据"
        case .cookies: name = "Cookie"
        case .logs: name = "日志"
        case .appScripts: name = "应用脚本"
        case .httpStorage: name = "网络存储"
        case .container: name = "容器"
        case .groupContainer: name = "共享容器"
        case .launchAgent: name = "启动代理"
        }
        return "\(name) · \(size)"
    }

    private func shortPath(_ path: String) -> String {
        guard let range = path.range(of: "/Library/") else { return (path as NSString).lastPathComponent }
        return "~/" + path[range.upperBound...]
    }
}
