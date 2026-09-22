import Cocoa

// Shared by window-browser actions and titlebar gestures. Main-thread owned.
extension AppDelegate {
    // MARK: 折叠终态等待

    @discardableResult
    func registerFoldWaiter(id: CGWindowID,
                                         completion: @escaping (Bool) -> Void) -> UUID {
        let token = UUID()
        foldWaiters[id, default: [:]][token] = completion
        // 兜底：折叠事务异常中止且没有走到任何结算点时，避免等待闭包长期驻留。
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.settleFoldWaiter(id: id, token: token, success: false)
        }
        return token
    }

    /// 只结算指定 token，避免同一窗口后来的一次折叠被旧超时误结算。
    func settleFoldWaiter(id: CGWindowID, token: UUID, success: Bool) {
        guard var waiters = foldWaiters[id],
              let completion = waiters.removeValue(forKey: token) else { return }
        if waiters.isEmpty {
            foldWaiters.removeValue(forKey: id)
        } else {
            foldWaiters[id] = waiters
        }
        completion(success)
    }

    /// 折叠事务的终态结算点：立即验证成功、延迟验证成功、回滚失败与中止。
    /// 第一个到达的结算生效；之后的结算不会再次调用回调。
    func settleFoldWaiters(id: CGWindowID, success: Bool) {
        guard let waiters = foldWaiters.removeValue(forKey: id) else { return }
        for (_, completion) in waiters {
            completion(success)
        }
    }

    func cancelFoldWaiters(id: CGWindowID, tokens: [UUID]) {
        settleFoldWaiters(id: id, tokens: tokens, success: false)
    }

    func settleFoldWaiters(id: CGWindowID, tokens: [UUID], success: Bool) {
        for token in tokens { settleFoldWaiter(id: id, token: token, success: success) }
    }

}
