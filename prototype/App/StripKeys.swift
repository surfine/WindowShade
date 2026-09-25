// 卷帘条上的 ⌘N / ⌘H / ⌘M / ⌘Q / ⌘W 转给它背后的 App（见 StripKeyForwarding）。
// WindowMizer 在占位条上也这样做；我们原来不转，⌘Q 会退出 WindowShade 自己。

import Cocoa
import Carbon.HIToolbox

extension AppDelegate {
    @MainActor func installStripKeyForwarding() {
        StripKeyForwarding.handler = { [weak self] window, key in
            guard let self,
                  let entry = self.shaded.first(where: { $0.value.overlay === window }) else { return false }
            return self.forwardStripKey(key, id: entry.key, pid: entry.value.pid)
        }
    }

    /// - ⌘N：交给原 App，新建窗口。
    /// - ⌘H：隐藏原 App。
    /// - ⌘W / ⌘M：关掉或最小化这扇窗，和卷帘条上的红灯、黄灯一样。
    /// - ⌘Q：先把窗口放下来再退出原 App——退出时要问“是否保存”，对话框得出现在看得见的窗口上。
    func forwardStripKey(_ key: String, id: CGWindowID, pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
        wlog("strip-key: ⌘\(key) id=\(id) → \(app.localizedName ?? "?")")
        switch key {
        case "n":
            app.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                postCommandKey(UInt16(kVK_ANSI_N), to: pid)
            }
        case "h":
            app.hide()
        case "w":
            handleTrafficLight(.close, id)
        case "m":
            handleTrafficLight(.minimize, id)
        case "q":
            unshade(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { _ = app.terminate() }
        default:
            return false
        }
        return true
    }
}

/// 给某个 App 发一个 ⌘+键（不经过当前前台 App）。
func postCommandKey(_ keyCode: UInt16, to pid: pid_t) {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
        event.flags = .maskCommand
        event.postToPid(pid)
    }
}
