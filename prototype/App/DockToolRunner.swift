import Foundation

/// Dock 偏好相关的小工具调用（defaults / killall）。带时限：超时先 SIGTERM，
/// 1 秒内不退就 SIGKILL 并回收，所以退出路径不会被卡死的子进程无限挂住。
struct DockToolRunner: Sendable {
    struct Result: Sendable {
        var status: Int32?      // nil：没起来或超时被终止
        var output: String
        var timedOut: Bool
    }

    static let defaultTimeout: TimeInterval = 3
    static let killGrace: TimeInterval = 1

    var execute: @Sendable (_ path: String, _ args: [String], _ timeout: TimeInterval, _ capture: Bool) -> Result

    static let live = DockToolRunner(execute: DockToolRunner.spawn)

    /// 只关心退出码。超时或没起来返回 nil。
    @discardableResult
    func run(_ path: String, _ args: [String], timeout: TimeInterval = DockToolRunner.defaultTimeout) -> Int32? {
        let r = execute(path, args, timeout, false)
        if r.timedOut { wlog("tool: timed out after \(timeout)s \(path)"); return nil }
        guard let status = r.status else {
            wlog("tool: failed to run \(path)")
            return nil
        }
        if status != 0 { wlog("tool: nonzero status=\(status) \(path) \(args.joined(separator: " "))") }
        return status
    }

    /// 读标准输出。非零退出、超时或空输出返回 nil。
    func read(_ path: String, _ args: [String], timeout: TimeInterval = DockToolRunner.defaultTimeout) -> String? {
        let r = execute(path, args, timeout, true)
        if r.timedOut { wlog("tool: read timed out after \(timeout)s \(path)"); return nil }
        guard r.status == 0 else { return nil }
        let text = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// 在串行队列上排一件活并最多等 timeout 秒。超时返回 false（活仍会在队列里跑完）。
    static func runBounded(on queue: DispatchQueue, timeout: TimeInterval,
                           _ work: @escaping @Sendable () -> Void) -> Bool {
        let group = DispatchGroup()
        queue.async(group: group, execute: work)
        return group.wait(timeout: .now() + timeout) == .success
    }

    private final class Buffer: @unchecked Sendable {
        private var data = Data()
        private let lock = NSLock()
        func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
        var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    }

    @Sendable
    private static func spawn(_ path: String, _ args: [String], _ timeout: TimeInterval, _ capture: Bool) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        let collected = Buffer()
        process.standardOutput = capture ? pipe : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if capture {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { collected.append(data) }
            }
        }
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return Result(status: nil, output: "", timedOut: false)
        }
        var timedOut = false
        if done.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if done.wait(timeout: .now() + killGrace) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        if capture, let rest = try? pipe.fileHandleForReading.readToEnd() { collected.append(rest) }
        return Result(status: timedOut ? nil : process.terminationStatus,
                      output: collected.text, timedOut: timedOut)
    }
}
