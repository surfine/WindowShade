import Cocoa
import ScreenCaptureKit

/// Opt-in UI for the real window entry points against explicitly selected test windows.
/// No hotkeys, event tap, startup rescue, login items or persistent effect preferences.
final class EffectInspector: NSObject, NSWindowDelegate {
  private let owner = AppDelegate()
  private var window: NSWindow?
  private let targets = NSPopUpButton()
  private let status = NSTextField(wrappingLabelWithString: "选择临时测试窗口")
  private let clock = EffectDisplayClock()
  func run() {
    owner.ownsGlobalInput = false
    owner.recoveryJournalOverride = DurableShadeJournal(
      url: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
        ".build/duo-tests/inspector-journal.plist"))
    owner.setupStatusItem()
    owner.statusItem.isVisible = false
    owner.duoController.persistsSettings = false
    owner.duoController.settings.desktopEnabled = false
    owner.duoController.settings.windowsEnabled = true
    owner.duoController.start(owner: owner)
    let panel = NSPanel(
      contentRect: NSRect(x: 30, y: 30, width: 540, height: 175),
      styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.title = "WindowShade Duo · 隔离测试控制台"
    panel.level = .floating
    panel.isReleasedWhenClosed = false
    panel.delegate = self
    window = panel
    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .leading
    root.spacing = 12
    root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    panel.contentView = root
    root.addArrangedSubview(targets)
    targets.widthAnchor.constraint(equalToConstant: 508).isActive = true
    let buttons = NSStackView(views: [
      NSButton(title: "刷新窗口", target: self, action: #selector(refresh)),
      NSButton(title: "折叠", target: self, action: #selector(fold)),
      NSButton(title: "展开", target: self, action: #selector(unfold)),
      NSButton(title: "直接恢复全部", target: self, action: #selector(restore)),
      NSButton(title: "效果设置", target: self, action: #selector(settings)),
    ])
    root.addArrangedSubview(buttons)
    root.addArrangedSubview(status)
    clock.tick = { [weak self] _ in
      guard let self else { return }
      status.stringValue =
        "已折叠 \(owner.shaded.count) · 过渡 \(owner.duoController.windowEffects.activeCount) · 已呈现完成 \(owner.duoController.windowEffects.completedTransitions)"
    }
    panel.orderFrontRegardless()
    clock.start(window: panel)
    refresh()
  }
  @objc private func refresh() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: true)
        targets.removeAllItems()
        for item in content.windows
        where item.windowLayer == 0 && item.owningApplication?.processID != getpid()
          && item.frame.width > 200 && item.frame.height > 100
        {
          targets.addItem(
            withTitle:
              "\(item.owningApplication?.applicationName ?? "App") · \(item.title ?? "Window")")
          targets.lastItem?.representedObject = NSNumber(value: item.windowID)
        }
      } catch { status.stringValue = error.localizedDescription }
    }
  }
  private var selected: CGWindowID? {
    (targets.selectedItem?.representedObject as? NSNumber)?.uint32Value
  }
  @objc private func fold() {
    guard let id = selected, let info = cgWindowInfo(id),
      let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
      let element = appWindows(pid: pid).first(where: { windowID(of: $0) == id })
    else { return }
    owner.shade(element, id)
  }
  @objc private func unfold() { if let id = selected { _ = owner.unshade(id) } }
  @objc private func restore() { owner.restoreAll() }
  @objc private func settings() { owner.showDuoSettings() }
  func windowWillClose(_ notification: Notification) {
    clock.stop()
    clock.tick = nil
    owner.duoController.stop()
    owner.restoreAll()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { NSApp.terminate(nil) }
  }
}
