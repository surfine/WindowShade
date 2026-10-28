import Cocoa

private func hlog(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

/// F1-B：从 HomePlay 接收器读「那台 iPhone 此刻 pair-verify 通过没有」。
///
/// 信号来自同一用户本机回环的 WebSocket（HomePlay 接收器 8788 端口，自广播
/// {"type":"phone-presence","verified":…,"generation":…}）。它比 IOBluetooth 的
/// isConnected 强一层：pair-verify 通过 = 配对长期密钥参与的加密会话还活着，
/// 即「配对的那台手机」在且可达，不是任何一台手机。
///
/// 边界：只读状态、只连 127.0.0.1、不存设备名/地址、收到的内容里只有布尔与代次；
/// HomePlay 没跑或没配过对时保持沉默（reducer 自己的 unknown 语义兜底）。
/// 作为第二个 PresenceSource 并存：谁先报用谁，IOBluetooth 轮询照旧兜底。
@MainActor
final class WS2HomePlayPresenceSource: NSObject, URLSessionWebSocketDelegate {
    /// HomePlay 接收器的本机 WebSocket 端口（与其 --port 一致，可用环境变量覆盖做实验）。
    static var endpointPort: UInt16 {
        UInt16(ProcessInfo.processInfo.environment["WINDOWSHADE_HOMEPLAY_PORT"] ?? "") ?? 8788
    }
    /// 状态翻转的最小间隔：把 HomePlay 侧 1 秒轮询的抖动再滤一层。测试可调 0。
    static var debounce: TimeInterval = 2

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var emit: (([PresenceLock.Event]) -> Void)?
    private var generation: UInt64 = 0
    private var request: UInt64 = 0
    private var verified: Bool?
    private var lastFlip = Date.distantPast
    private var reconnect: DispatchWorkItem?

    func start(emit: @escaping @MainActor ([PresenceLock.Event]) -> Void) {
        self.emit = emit
        generation &+= 1
        verified = nil
        connect()
    }

    /// 探针/测试用：不经网络直接喂一行。返回「格式合法且已被接受」——
    /// 同值重复也返回 true（吃下了，只是不产生事件）；非法负载返回 false。
    @discardableResult
    func probeFeed(_ text: String) -> Bool {
        guard emit != nil else { return false }
        guard Self.isWellFormed(text) else { return false }
        handle(text)
        return true
    }

    nonisolated static func isWellFormed(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "phone-presence",
              object["verified"] is Bool else { return false }
        return true
    }

    func restart() {
        guard emit != nil else { return }
        generation &+= 1
        verified = nil
        reconnect?.cancel()
        connect()
    }

    func stop() {
        reconnect?.cancel(); reconnect = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.finishTasksAndInvalidate()
        session = nil
        emit = nil
        verified = nil
    }

    private func connect() {
        guard emit != nil else { return }
        let url = URL(string: "ws://127.0.0.1:\(Self.endpointPort)")!
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receive()
        hlog("presence: HomePlay bridge connecting \(url.absoluteString)")
    }

    private func receive() {
        task?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.emit != nil else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.receive()
                case .failure:
                    // 接收器没跑/端口换了：沉默重连，不刷事件。
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard emit != nil else { return }
        reconnect?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.connect() }
        }
        reconnect = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func handle(_ text: String) {
        guard let emit else { return }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "phone-presence",
              let value = object["verified"] as? Bool else { return }
        let now = Date()
        if verified == value { return }
        // 抖动过滤：翻转后两秒内的反向翻转当噪声，不重发（最后状态照记）。
        if verified != nil, now.timeIntervalSince(lastFlip) < Self.debounce, value != verified { return }
        verified = value
        lastFlip = now
        generation &+= 1
        request &+= 1
        // 事件序列照探针协议：connect/disconnect 加一对 read 回执，reducer 的状态立即可用。
        emit(value
             ? [.connected(.phone, generation: generation),
                .readStarted(.phone, generation: generation, request: request),
                .readSucceeded(.phone, generation: generation, request: request)]
             : [.disconnected(.phone, generation: generation),
                .readStarted(.phone, generation: generation, request: request),
                .readSucceeded(.phone, generation: generation, request: request)])
        hlog("presence: HomePlay phone verified=\(value)")
    }

    // MARK: URLSessionWebSocketDelegate（只为了拿 open/failed 做重连节拍）

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                didOpenWithProtocol protocol: String?) {}
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        Task { @MainActor [weak self] in self?.scheduleReconnect() }
    }
}

#if !WS2_HOMEPLAY_PRESENCE_TESTING
extension WS2HomePlayPresenceSource: PresenceSource {
    // start/stop/restart 已在主实现里。
}
#endif
