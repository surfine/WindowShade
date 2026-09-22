// 状态栏图标（模板图，跟随菜单栏浅深色）。

import Cocoa

func makeStatusBarIcon() -> NSImage {
    let size = NSSize(width: 16, height: 16)
    let image = NSImage(size: size)
    image.lockFocus()

    NSGraphicsContext.current?.shouldAntialias = true
    NSColor.black.setFill()

    let sourceSize: CGFloat = 74
    func sourceRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        let scale = size.width / sourceSize
        return NSRect(x: x * scale,
                      y: size.height - (y + height) * scale,
                      width: width * scale,
                      height: height * scale)
    }

    // Monochrome template mask traced from the reference icon, with symmetric strokes.
    // The 72px body is centered in the 74px source grid; inner bands are cut out.
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
