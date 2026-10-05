// 画中画首帧。零帧、迟到、取消和旧代次都不能让原窗口让开。
import Foundation

enum PiPArrival: Equatable, Sendable {
    case ready
    case timedOut
    case cancelled
    case sourceChanged
    case failed
}

struct PiPFrameGate: Equatable, Sendable {
    var expectedGeneration: UInt64
    var windowID: UInt64
    var deadline: TimeInterval
    private(set) var settled: PiPArrival?

    mutating func evaluate(
        now: TimeInterval,
        frameGeneration: UInt64,
        pixelCount: UInt64,
        displayReady: Bool,
        sessionMatches: Bool,
        observedWindow: UInt64
    ) -> PiPArrival? {
        if let settled { return settled }
        if !sessionMatches || observedWindow != windowID {
            settled = .sourceChanged
            return settled
        }
        if now >= deadline {
            settled = .timedOut
            return settled
        }
        guard pixelCount > 0, frameGeneration == expectedGeneration, displayReady else { return nil }
        settled = .ready
        return settled
    }

    mutating func cancel() -> PiPArrival {
        if let settled { return settled }
        settled = .cancelled
        return .cancelled
    }
}
