// 规格 R7 的真实核对：App 被冻住（kill -STOP）时 AX 读不到外框，窗口服务器那层仍给出同一个外框。
import ApplicationServices
import Cocoa

@_silgen_name("_AXUIElementGetWindow") func _AXUIElementGetWindow(_ e: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

let pid = pid_t(CommandLine.arguments[1])!
let frozen = CommandLine.arguments.count > 2
guard AXIsProcessTrusted() else { print("SKIP window-frame: 没有辅助功能权限"); exit(0) }
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 0.5)

func ax(_ e: AXUIElement, _ attr: String) -> AXValue? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success, let v,
          CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    return (v as! AXValue)
}
func listed(_ id: CGWindowID) -> CGRect? {
    guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first,
          let dict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
    var r = CGRect.zero
    return CGRectMakeWithDictionaryRepresentation(dict, &r) ? r : nil
}

// 窗口号要在冻住之前拿：调用方第一遍不带 frozen 参数，打印窗口号；第二遍带上。
if !frozen {
    var ref: CFTypeRef?
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref)
    for w in (ref as? [AXUIElement]) ?? [] {
        var id: CGWindowID = 0; _ = _AXUIElementGetWindow(w, &id)
        var p = CGPoint.zero, s = CGSize.zero
        if let v = ax(w, kAXPositionAttribute) { AXValueGetValue(v, .cgPoint, &p) }
        if let v = ax(w, kAXSizeAttribute) { AXValueGetValue(v, .cgSize, &s) }
        print("\(id) \(Int(p.x)) \(Int(p.y)) \(Int(s.width)) \(Int(s.height))")
    }
    exit(0)
}
let id = CGWindowID(CommandLine.arguments[2])!
let expected = CGRect(x: Double(CommandLine.arguments[3])!, y: Double(CommandLine.arguments[4])!,
                      width: Double(CommandLine.arguments[5])!, height: Double(CommandLine.arguments[6])!)
var ref: CFTypeRef?
let started = Date()
let err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref)
let axTook = Date().timeIntervalSince(started)
let resolved = WindowFrameResolver.resolve(axPosition: nil, axSize: nil, windowList: listed(id))
print("frozen: AXWindows err=\(err.rawValue) took=\(String(format: "%.2f", axTook))s  resolved=\(resolved.map { "\($0.frame) via \($0.source.rawValue)" } ?? "nil")")
if err == .success { print("SKIP window-frame: 冻住后 AX 仍然应答，这次没测到回退"); exit(0) }
if resolved?.frame == expected && resolved?.source == .windowList {
    print("PASS window-frame: App 冻住时 AX 读不到，窗口服务器那层给出同一个外框")
} else {
    print("FAIL window-frame: 期望 \(expected)"); exit(1)
}
