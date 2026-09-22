import Foundation

/// Bounded AX work: two background applications plus one interactive Dock target.
/// Dependencies serialize a PID even across queues and controller stop/start cycles.
/// Submission and tail bookkeeping belong to the main queue; work never does.
final class WindowBrowserMetadataQueue {
    private let background: OperationQueue
    private let interactive: OperationQueue
    private var tails: [pid_t: Operation] = [:]

    init() {
        background = OperationQueue()
        background.name = "WindowShade.window-browser-metadata"
        background.qualityOfService = .utility
        background.maxConcurrentOperationCount = 2
        interactive = OperationQueue()
        interactive.name = "WindowShade.window-browser-target-metadata"
        interactive.qualityOfService = .userInitiated
        interactive.maxConcurrentOperationCount = 1
    }

    func submit(pid: pid_t, isInteractive: Bool, work: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        let operation = BlockOperation(block: work)
        if let previous = tails[pid], !previous.isFinished {
            operation.addDependency(previous)
        }
        tails[pid] = operation
        operation.completionBlock = { [weak self, weak operation] in
            DispatchQueue.main.async {
                guard let self, let operation, self.tails[pid] === operation else { return }
                self.tails.removeValue(forKey: pid)
            }
        }
        (isInteractive ? interactive : background).addOperation(operation)
    }
}
