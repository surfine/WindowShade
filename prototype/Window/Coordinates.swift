// AX（左上原点）与 Cocoa（左下原点）坐标换算、屏幕归属。

import Cocoa

// AX / CGEvent 坐标以主屏左上为原点、y 向下；NSWindow 坐标以主屏左下为原点、y 向上。
// 多显示器时副屏可以有负 y，但两套坐标仍共享同一个主屏高度作为翻转基线。
func coordinateBaselineY() -> CGFloat {
    (NSScreen.screens.first { $0.frame.origin == .zero }?.frame.maxY)
        ?? NSScreen.main?.frame.maxY ?? 0
}

func cocoaFrame(fromAXPosition p: CGPoint, size: CGSize) -> NSRect {
    NSRect(x: p.x, y: coordinateBaselineY() - p.y - size.height,
           width: size.width, height: size.height)
}

func axPosition(fromCocoaFrame frame: NSRect) -> CGPoint {
    CGPoint(x: frame.minX, y: coordinateBaselineY() - frame.maxY)
}

func screenForAXWindow(pos: CGPoint, size: CGSize) -> NSScreen? {
    let rect = cocoaFrame(fromAXPosition: pos, size: size)
    return screenForCocoaFrame(rect)
}

func screenForCocoaFrame(_ rect: NSRect) -> NSScreen? {
    func intersectionArea(_ screen: NSScreen) -> CGFloat {
        let hit = screen.frame.intersection(rect)
        return hit.isNull ? 0 : hit.width * hit.height
    }
    if let best = NSScreen.screens.max(by: { intersectionArea($0) < intersectionArea($1) }),
       intersectionArea(best) > 0 {
        return best
    }
    let center = CGPoint(x: rect.midX, y: rect.midY)
    return NSScreen.screens.min {
        let a = $0.frame
        let b = $1.frame
        let da = hypot(center.x - a.midX, center.y - a.midY)
        let db = hypot(center.x - b.midX, center.y - b.midY)
        return da < db
    } ?? NSScreen.main
}

func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
    screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        .flatMap { ($0 as? NSNumber)?.uint32Value }
}

func screenForDisplayID(_ displayID: CGDirectDisplayID?) -> NSScreen? {
    guard let displayID else { return nil }
    return NSScreen.screens.first {
        (($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value) == displayID
    }
}

func backingScaleForAXWindow(pos: CGPoint, size: CGSize) -> CGFloat {
    screenForAXWindow(pos: pos, size: size)?.backingScaleFactor
        ?? NSScreen.main?.backingScaleFactor ?? 2
}
