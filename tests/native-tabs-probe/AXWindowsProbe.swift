// 规格 R4 的前提核对：窗口浏览按 App 读 AX 的 kAXWindowsAttribute（WindowBrowserDiscovery.discover）。
// 原生标签页的后台标签在 CG 窗口列表里有（不在屏），但不在 AXWindows 里——所以窗口浏览本来就只出一条，
// 不需要 DockDoor 那种按外框合并。系统改了这个行为，这里就失败。
import Cocoa
import ApplicationServices

let pid = pid_t(CommandLine.arguments[1])!
guard AXIsProcessTrusted() else { print("SKIP native-tabs: 没有辅助功能权限，读不到 AX"); exit(0) }
var ref: CFTypeRef?
let err = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &ref)
let titles = ((ref as? [AXUIElement]) ?? []).map { window -> String in
    var t: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &t)
    return t as? String ?? ""
}.sorted()
let cgTitles = ((CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? [])
    .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }
    .compactMap { $0[kCGWindowName as String] as? String }.filter { !$0.isEmpty }.sorted()
print("AXWindows err=\(err.rawValue) \(titles)  CG named=\(cgTitles)")
guard cgTitles.contains("Tab A"), cgTitles.contains("Tab B") else {
    print("SKIP native-tabs: 夹具窗口没起来（CG 里没有后台标签）"); exit(0)
}
if titles == ["Separate", "Tab C"] {
    print("PASS native-tabs: 3 个原生标签只有前台那个在 AXWindows 里，独立窗口照常在")
} else {
    print("FAIL native-tabs: AXWindows 现在是 \(titles)，窗口浏览可能要按外框合并标签页（规格 R4）")
    exit(1)
}
