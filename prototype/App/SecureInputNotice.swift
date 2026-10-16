// R17 安全输入的可见说明，和 R8 别的窗口管理工具的提醒。两件事都只在“真的影响到用户”时在刘海上说一句。
//
// 安全输入：别的 App（密码框、开了“安全键盘输入”的终端）把它打开后，系统不再把按键交给全局快捷键，
// 用户按了没反应，也没有任何提示。按键本身读不到，所以不等“按了没反应”：用户刚用过我们的快捷键
// （说明在用），之后一小段时间里每秒看一眼，从关变开就说一次（判定见 Core/SecureInputNoticeGate.swift）。
// 没用过快捷键的人，开安全输入不会看到任何东西；一直开着的不再说；同一个 App 这次运行里只说一次。

import Cocoa
import Carbon.HIToolbox

@MainActor
final class SecureInputWatch {
    static let shared = SecureInputWatch()

    private var gate = SecureInputNoticeGate()
    private var timer: Timer?
    /// 这次运行里已经说过的开启者（读不到名字的算同一个）：同一个 App 只说一次，免得每进一次密码框都说。
    private var toldOwners: Set<String> = []

    /// 用户用了一次全局快捷键（EventTap.swift 的 handleHotKey 调用）：开始（或续上）盯 2 分钟。
    func shortcutUsed() {
        let now = ProcessInfo.processInfo.systemUptime
        gate.shortcutUsed(at: now, secureNow: IsSecureEventInputEnabled())
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { SecureInputWatch.shared.tick() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        guard gate.isArmed(at: now) else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard gate.sample(secure: IsSecureEventInputEnabled(), at: now) else { return }
        let owner = Self.secureInputOwnerName()
        guard toldOwners.insert(owner ?? "").inserted else { return }
        let message = owner.map { WSL10n.text("notice.secureInput.named", zh: "%@ 正在保护键盘输入，快捷键暂时用不了", $0) }
            ?? WSL10n.text("notice.secureInput.unnamed", zh: "有 App 正在保护键盘输入，快捷键暂时用不了")
        appDelegate?.quietNotice(message, kind: .info, log: "secure-input: shortcuts paused owner=\(owner ?? "unknown")")
    }

    /// 谁开的安全输入：会话字典里记着它的进程号，读不到就不点名。
    private static func secureInputOwnerName() -> String? {
        let state = CGSessionCopyCurrentDictionary() as? [String: Any]
        guard let pid = state?["kCGSSessionSecureInputPID"] as? Int, pid > 0 else { return nil }
        let name = NSRunningApplication(processIdentifier: pid_t(pid))?.localizedName
        return (name?.isEmpty ?? true) ? nil : name
    }
}

extension AppDelegate {
    /// R8：有全局快捷键被其他应用占用时，看看正在跑的是不是已知的窗口管理工具；是、而且没提醒过，说一次。
    /// 只提醒，不关别人的功能；同一个工具永远只提醒一次。晚几秒说，让“被占用”那句先读完。
    func remindAboutWindowToolIfNeeded(takenShortcutCount: Int) {
        guard takenShortcutCount > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            let defaults = UserDefaults.standard
            let reminded = Set(defaults.stringArray(forKey: WindowToolConflict.defaultsKey) ?? [])
            let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
            guard let tool = WindowToolConflict.toRemind(runningBundleIDs: running,
                                                         takenShortcutCount: takenShortcutCount,
                                                         alreadyReminded: reminded) else { return }
            defaults.set(Array(reminded.union([tool.bundleID])).sorted(), forKey: WindowToolConflict.defaultsKey)
            let message = WSL10n.text("notice.windowTool.conflict", zh: "%@ 也在管窗口，快捷键可能互相抢；在它或 WindowShade 的设置里关掉重复的即可", tool.name)
            self?.quietNotice(message, kind: .info, log: "window-tool: reminded once about \(tool.bundleID)")
        }
    }
}
