// 看护的菜单栏图标：和 App/StatusBarIcon.swift 画的是同一个图形，单独一份。
// 看护只编译 Watchdog/ 和几份更新代码，不编 App 里别的文件：App/StatusBarIcon.swift 以后引用 App 里的类型，也不会连累看护。
// 改了 App 的图标就照着改这里。

import AppKit

func makeGuardStatusIcon() -> NSImage {
    let size = NSSize(width: 16, height: 16)
    let image = NSImage(size: size)
    image.lockFocus()
    NSGraphicsContext.current?.shouldAntialias = true
    NSColor.black.setFill()
    let sourceSize: CGFloat = 74
    func sourceRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        let scale = size.width / sourceSize
        return NSRect(x: x * scale, y: size.height - (y + height) * scale, width: width * scale, height: height * scale)
    }
    let path = NSBezierPath(rect: sourceRect(x: 1, y: 1, width: 72, height: 72))
    path.append(NSBezierPath(rect: sourceRect(x: 8, y: 8, width: 58, height: 18)))
    path.append(NSBezierPath(rect: sourceRect(x: 8, y: 33, width: 58, height: 8)))
    path.append(NSBezierPath(rect: sourceRect(x: 8, y: 48, width: 58, height: 18)))
    path.windingRule = .evenOdd
    path.fill()
    image.unlockFocus()
    image.isTemplate = true
    return image
}
