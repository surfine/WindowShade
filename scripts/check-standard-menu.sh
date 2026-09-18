#!/bin/bash
# 代理应用（LSUIElement）的主菜单行为校验：
# 同一份 StandardMenu 构建里对比“无主菜单 / 有主菜单”下 ⌘V 的结果，
# 证明文本框的编辑快捷键确实依赖主菜单的 key equivalent 派发。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/design-review/standard-menu-check.txt"
mkdir -p "$(dirname "$OUT")"

cat > /tmp/standard-menu-check.swift <<'SWIFT'
import Cocoa

func pasteResult(withMenu: Bool) -> String {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.mainMenu = withMenu
        ? StandardMenu.make(appName: "WindowShade", settingsTarget: nil, settingsAction: nil)
        : nil
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 60),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    window.contentView = field
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(field)
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("PASTED", forType: .string)
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                 timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                 characters: "v", charactersIgnoringModifiers: "v",
                                 isARepeat: false, keyCode: 9)!
    let handledByMenu = app.mainMenu?.performKeyEquivalent(with: event) ?? false
    let handledByWindow = window.performKeyEquivalent(with: event)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    let result = "menu=\(withMenu) key=\(window.isKeyWindow) "
        + "menuHandled=\(handledByMenu) windowHandled=\(handledByWindow) "
        + "value=\"\(field.stringValue)\""
    window.close()
    return result
}

@main
enum StandardMenuCheck {
    // 每个进程只验证一种情况：同一进程里第二个窗口不会成为 key window，
    // paste: 会落到前一个窗口的 field editor 上。
    static func main() {
        if CommandLine.arguments.contains("--about") {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            NSApp.orderFrontStandardAboutPanel(options: StandardMenu.aboutPanelOptions(
                version: "1.0.14", build: "14"))
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            let visible = NSApp.windows.filter { $0.isVisible }
            print("about-panel visibleWindows=\(visible.count) "
                  + "classes=\(visible.map(\.className).joined(separator: ","))")
            return
        }
        print(pasteResult(withMenu: CommandLine.arguments.contains("--with-menu")))
    }
}
SWIFT

swiftc -target "$(uname -m)-apple-macosx14.0" \
  "$ROOT/prototype/App/StandardMenu.swift" /tmp/standard-menu-check.swift \
  -framework Cocoa -o /tmp/standard-menu-check
{
  echo "== 关于面板 =="
  /tmp/standard-menu-check --about
  echo "== 进程内：菜单是否认领 ⌘V =="
  /tmp/standard-menu-check
  /tmp/standard-menu-check --with-menu
  if [ -x "$ROOT/.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade" ]; then
    echo "== 真实键盘面板（打包探针）：无主菜单 / 有主菜单 =="
    "$ROOT/.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade" \
      --standard-menu-probe --without-menu 2>&1 | tail -1
    "$ROOT/.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade" \
      --standard-menu-probe 2>&1 | tail -1
  else
    echo "（未找到隔离构建，跳过打包探针；先运行 prototype/build.sh --stage）"
  fi
} | tee "$OUT"
echo "==> 结果写入 $OUT"
