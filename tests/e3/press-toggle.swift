// E3：向前台发 ⌃⌘C（收起或展开当前窗口）N 次，每次之前把夹具窗口拉到最前，并记录按键前后夹具窗口的屏上状态。
// 用法：swift press-toggle.swift <夹具 pid> <次数> <间隔秒> <keycode，默认 8=C>
import AppKit
import CoreGraphics

let a = CommandLine.arguments
let pid = pid_t(a[1])!
let count = Int(a[2])!
let interval = Double(a[3])!
let keyCode = CGKeyCode(a.count > 4 ? Int(a[4])! : 8)

func fixtureState() -> String {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
    return mine.map { w in
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        return "h=\(b["Height"] ?? "?") a=\(w[kCGWindowAlpha as String] ?? "?")"
    }.joined(separator: ";") + " n=\(mine.count)"
}

func post(_ down: Bool) {
    let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: keyCode, keyDown: down)!
    e.flags = [.maskControl, .maskCommand]
    e.post(tap: .cghidEventTap)
}

let app = NSRunningApplication(processIdentifier: pid)
for i in 1...count {
    app?.activate()
    // 等夹具真的在最前；不在最前就不发键，免得 ⌃⌘C 落到别人的窗口上
    var waited = 0.0
    while NSWorkspace.shared.frontmostApplication?.processIdentifier != pid && waited < 1.5 {
        Thread.sleep(forTimeInterval: 0.1); waited += 0.1
    }
    Thread.sleep(forTimeInterval: 0.25)
    let before = fixtureState()
    let t0 = Date()
    if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
        print(String(format: "press %2d t=%.1f before[%@] after[%@] UNCHANGED (fixture not frontmost, key not sent)", i, t0.timeIntervalSince1970.truncatingRemainder(dividingBy: 1000), before, before))
        fflush(stdout)
        Thread.sleep(forTimeInterval: interval)
        continue
    }
    post(true); Thread.sleep(forTimeInterval: 0.03); post(false)
    Thread.sleep(forTimeInterval: 1.0)
    let after = fixtureState()
    print(String(format: "press %2d t=%.1f before[%@] after[%@] %@", i, t0.timeIntervalSince1970.truncatingRemainder(dividingBy: 1000), before, after, before == after ? "UNCHANGED" : "changed"))
    fflush(stdout)
    let rest = interval - Date().timeIntervalSince(t0)
    if rest > 0 { Thread.sleep(forTimeInterval: rest) }
}
