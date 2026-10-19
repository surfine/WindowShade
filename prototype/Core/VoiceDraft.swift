import Foundation

/// 语音草稿的纯状态：按住开始、松手转写、出草稿；最长 60 秒；永远不自动发送。
/// 识别器只报告文字/失败，状态机决定什么时候算一句话、什么时候作废。
struct VoiceDraftSession: Equatable, Sendable {
    static let maximumDuration: Double = 60

    enum Phase: Equatable, Sendable {
        case idle
        case listening
        case transcribing
    }

    enum Failure: Error, Equatable, Sendable {
        /// 这台 Mac 不能在本机识别（不做云端回退）。
        case onDeviceUnavailable
        /// 麦克风或语音识别没有授权。
        case notAuthorized
        /// 松手时没听到任何字。
        case empty
        /// 超过 60 秒。
        case tooLong
        /// 识别器中途停下。
        case interrupted
    }

    private(set) var phase: Phase = .idle
    private(set) var draft: String?
    private(set) var failure: Failure?
    private(set) var startedAt: Double?
    private(set) var partial = ""

    var isActive: Bool { phase != .idle }

    mutating func start(at now: Double) -> Bool {
        guard phase == .idle, now.isFinite else { return false }
        phase = .listening
        startedAt = now
        draft = nil
        failure = nil
        partial = ""
        return true
    }

    mutating func update(_ text: String) {
        guard phase == .listening else { return }
        partial = text
    }

    /// 松手：进入转写。已经超过 60 秒就当场作废，调用方负责停掉识别器。
    @discardableResult
    mutating func stop(at now: Double) -> Bool {
        guard phase == .listening else { return false }
        if let startedAt, now - startedAt > Self.maximumDuration {
            finish(.failure(.tooLong))
            return true
        }
        phase = .transcribing
        return true
    }

    /// 识别器给出最后结果（成功或失败）。只接受还在这句话里的结果。
    mutating func finish(_ result: Result<String, Failure>) {
        guard phase == .listening || phase == .transcribing else { return }
        phase = .idle
        startedAt = nil
        partial = ""
        switch result {
        case .success(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                draft = nil
                failure = .empty
            } else {
                draft = trimmed
                failure = nil
            }
        case .failure(let failure):
            draft = nil
            self.failure = failure
        }
    }

    /// 计时检查：到 60 秒就作废并返回 true，调用方停掉识别器。
    mutating func tick(at now: Double) -> Bool {
        guard phase == .listening, let startedAt, now.isFinite else { return false }
        guard now - startedAt >= Self.maximumDuration else { return false }
        finish(.failure(.tooLong))
        return true
    }

    mutating func cancel() {
        phase = .idle
        startedAt = nil
        partial = ""
        draft = nil
        failure = nil
    }

    /// 把草稿交给输入框后调用：草稿本身由页面负责采用/发送。
    mutating func clearDraft() {
        guard phase == .idle else { return }
        draft = nil
    }
}
