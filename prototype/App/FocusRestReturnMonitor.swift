import Cocoa

/// 休息时窗口被收着的这段时间里，按任意键、点屏幕任意处就把窗口放回来（休息照走）。
/// 只在这段时间装一个全局监听（keyDown、leftMouseDown），不读按了什么键，也不读点在哪；结束就卸。
@MainActor final class FocusRestReturnMonitor {
    static let shared = FocusRestReturnMonitor()
    /// 装监听的缝：测试里换成假的，生产里是 NSEvent 全局监听。
    typealias Install = @MainActor (_ fire: @escaping @Sendable () -> Void) -> Any?
    typealias Remove = @MainActor (Any) -> Void
    private let install: Install
    private let remove: Remove
    private var token: Any?
    private var onReturn: (() -> Void)?
    var isInstalled: Bool { token != nil }

    init(install: @escaping Install = { FocusRestReturnMonitor.liveInstall($0) },
         remove: @escaping Remove = { NSEvent.removeMonitor($0) }) {
        self.install = install; self.remove = remove
    }

    /// 已经装着就不重复装。
    func start(onReturn: @escaping () -> Void) {
        self.onReturn = onReturn
        guard token == nil else { return }
        token = install { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.fire() } }
        }
    }

    func stop() {
        if let token { remove(token) }
        token = nil; onReturn = nil
    }

    private func fire() {
        guard token != nil, let callback = onReturn else { return }
        stop()
        callback()
    }

    static func liveInstall(_ fire: @escaping @Sendable () -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { _ in fire() }
    }
}
