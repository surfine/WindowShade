import Foundation

// 外部接收器的 WebSocket 客户端：连接、收发、按事件回调。不解析媒体内容（那是 Wire 与解码器的事）。
// 接收器是用户自己另起的独立进程；本文件只持有它的地址，不持有任何身份或凭据。

@MainActor
protocol WS2CarPlayReceiverClientDelegate: AnyObject {
    func receiverClosed()
    func receiverReceivedControl(_ message: WS2CarPlayReceiverWire.ControlMessage)
    func receiverReceivedMedia(_ message: WS2CarPlayReceiverWire.MediaMessage)
}

/// 一个客户端对应一条 WebSocket 连接。断了就整体作废，重连建新实例（票据语义与会话模型一致）。
@MainActor
final class WS2CarPlayReceiverClient {

    enum Failure: Error {
        /// 地址必须是 ws:// 或 wss://。
        case invalidEndpoint
    }

    private(set) var url: URL
    private weak var delegate: (any WS2CarPlayReceiverClientDelegate)?
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    /// 发送走这个串行队列；接收回调经过它再跳回主线程。
    private let queue = DispatchQueue(label: "ws2.carplay.receiver")

    init(endpoint: String) throws {
        guard let parsed = URL(string: endpoint),
              let scheme = parsed.scheme?.lowercased(), ["ws", "wss"].contains(scheme),
              parsed.host != nil
        else { throw Failure.invalidEndpoint }
        url = parsed
    }

    func open(delegate: any WS2CarPlayReceiverClientDelegate) {
        self.delegate = delegate
        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: .init())
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveLoop(on: task)
    }

    func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        delegate = nil
    }

    // MARK: 发送（主线程编码，后台线程发）

    func send(text: @autoclosure @escaping () -> String) {
        guard let task else { return }
        queue.async { [task] in
            task.send(.string(text())) { _ in }
        }
    }

    func requestKeyframe() { send(text: WS2CarPlayReceiverWire.keyframeJSON()) }
    func sendSiri() { send(text: WS2CarPlayReceiverWire.siriJSON()) }
    func sendMedia(_ code: Int) { send(text: WS2CarPlayReceiverWire.mediaJSON(code)) }
    func sendKnob(select: Bool = false, home: Bool = false, back: Bool = false, x: Int = 0, y: Int = 0) {
        send(text: WS2CarPlayReceiverWire.knobJSON(select: select, home: home, back: back, x: x, y: y))
    }
    func sendTouch(_ contacts: [WS2CarPlayReceiverWire.TouchContact]) {
        send(text: WS2CarPlayReceiverWire.touchJSON(contacts))
    }

    // MARK: 接收循环

    private enum Delivery {
        case control(WS2CarPlayReceiverWire.ControlMessage)
        case media(WS2CarPlayReceiverWire.MediaMessage)
        /// 未知消息：丢弃但不断开（上游会广播我们还没用到的类型）。
        case drop
        case closed
    }

    private func receiveLoop(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            let delivery = Self.classify(result)
            Task { @MainActor [weak self] in
                guard let self, self.task === task else { return } // 旧连接的迟到回调一律丢弃
                switch delivery {
                case .control(let control):
                    self.delegate?.receiverReceivedControl(control)
                    self.receiveLoop(on: task)
                case .media(let media):
                    self.delegate?.receiverReceivedMedia(media)
                    self.receiveLoop(on: task)
                case .drop:
                    self.receiveLoop(on: task)
                case .closed:
                    self.task = nil
                    self.delegate?.receiverClosed()
                }
            }
        }
    }

    private static func classify(_ result: Result<URLSessionWebSocketTask.Message, Error>) -> Delivery {
        switch result {
        case .failure:
            return .closed
        case .success(.string(let text)):
            if let control = WS2CarPlayReceiverWire.parseControl(text) {
                return .control(control)
            }
            return .drop
        case .success(.data(let data)):
            if let media = WS2CarPlayReceiverWire.parseMedia(data) {
                return .media(media)
            }
            return .drop
        case .success:
            return .drop
        }
    }
}
