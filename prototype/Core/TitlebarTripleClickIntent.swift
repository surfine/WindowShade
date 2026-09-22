/// Joins two independently arriving events without retaining UI callbacks.
/// Returns true exactly once, when both the third click and verified fold exist.
final class TitlebarTripleClickIntent {
    private enum State { case waiting, requested, folded, finished }
    private var state: State = .waiting

    func request() -> Bool {
        switch state {
        case .waiting: state = .requested; return false
        case .folded: state = .finished; return true
        case .requested, .finished: return false
        }
    }

    func completeFold(success: Bool) -> Bool {
        guard success else { cancel(); return false }
        switch state {
        case .waiting: state = .folded; return false
        case .requested: state = .finished; return true
        case .folded, .finished: return false
        }
    }

    func cancel() { state = .finished }
}
