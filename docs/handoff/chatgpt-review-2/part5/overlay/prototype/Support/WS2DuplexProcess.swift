// Owns one child. All state and source callbacks run on MainActor / DispatchQueue.main.
// Nonblocking readiness avoids a readLine call preventing an approval write.
import Foundation
import Dispatch
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@MainActor final class WS2DuplexProcess {
    enum Failure: Error { case invalid, io(Int32), notRunning }
    enum End: Equatable { case localStop, eof, processExit, io(Int32), framing, timeout, revoked }
    let connection: UUID
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private var reader: (any DispatchSourceRead)?
    private var writer: (any DispatchSourceWrite)?
    private var writeArmed = false
    private var deadlineTask: Task<Void, Never>?
    private var buffer = Data()
    private var outbox: WS2BoundedOutbox
    private var bindings: [UInt64: @MainActor () -> Bool] = [:]
    private var started = false
    private(set) var stopped = false
    private let clock: () -> Double
    private let mayWrite: () -> Bool
    var onLine: ((Data) -> Void)?
    var onEnd: ((End) -> Void)?
    // Called only when all bytes have been handed to the local pipe, NOT when acted upon.
    var onLocallyWritten: ((UInt64) -> Void)?
    static let maximumLine = 1_048_576
    init(connection: UUID = UUID(), executable: URL, arguments: [String], workingDirectory: URL,
         environment: [String: String], clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         mayWrite: @escaping () -> Bool) throws {
        guard executable.isFileURL, executable.path.hasPrefix("/"), workingDirectory.isFileURL,
              !arguments.contains(where: { $0.utf8.contains(0) }),
              !environment.contains(where: { $0.key.contains("=") || $0.key.utf8.contains(0) || $0.value.utf8.contains(0) }),
              FileManager.default.isExecutableFile(atPath: executable.path) else { throw Failure.invalid }
        self.connection = connection; self.clock = clock; self.mayWrite = mayWrite
        outbox = WS2BoundedOutbox(connection: connection)
        process.executableURL = executable; process.arguments = arguments
        process.currentDirectoryURL = workingDirectory; process.environment = environment
        process.standardInput = input; process.standardOutput = output
        // No unsolicited prompt/command logging. A bounded diagnostic channel is a separate feature.
        process.standardError = FileHandle.nullDevice
    }
    func start() throws {
        guard !started, !stopped else { throw Failure.invalid }
        do {
            try process.run(); started = true
            try input.fileHandleForReading.close(); try output.fileHandleForWriting.close()
            for handle in [input.fileHandleForWriting, output.fileHandleForReading] {
                let fd = handle.fileDescriptor, flags = fcntl(fd, F_GETFL)
                guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { throw Failure.io(errno) }
            }
            let r = DispatchSource.makeReadSource(fileDescriptor: output.fileHandleForReading.fileDescriptor, queue: .main)
            let w = DispatchSource.makeWriteSource(fileDescriptor: input.fileHandleForWriting.fileDescriptor, queue: .main)
            r.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readReady() } }
            w.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.writeReady() } }
            // File descriptors are closed only after all callbacks on that source have returned.
            let readHandle = output.fileHandleForReading, writeHandle = input.fileHandleForWriting
            r.setCancelHandler { try? readHandle.close() }
            w.setCancelHandler { try? writeHandle.close() }
            reader = r; writer = w; r.resume()
        } catch { stop(.io(errno)); throw error }
    }
    // Boolean means only "retained by this connection's bounded queue". Never retry false/ambiguous approval.
    @discardableResult func admit(_ lines: [Data], connection: UUID, deadline: Double,
                                  binding: (@MainActor () -> Bool)? = nil) -> Bool {
        guard started, !stopped, connection == self.connection, mayWrite(),
              !lines.isEmpty, !lines.contains(where: { $0.count > Self.maximumLine || $0.contains(10) || $0.isEmpty }) else { return false }
        do {
            let tickets = try outbox.admit(lines.map { $0 + Data([10]) }, connection: connection, now: clock(), deadline: deadline)
            if let binding { for ticket in tickets { bindings[ticket] = binding } }
            armWrite(); scheduleDeadline(); return true
        } catch { stop(.timeout); return false }
    }
    // Existing CodexWire.drain() returns newline-terminated frames. Normalize exactly one final LF.
    @discardableResult func admitWireFrames(_ frames: [Data], connection: UUID, deadline: Double,
                                            binding: (@MainActor () -> Bool)? = nil) -> Bool {
        var lines: [Data] = []
        guard !frames.isEmpty else { return false }
        for frame in frames {
            guard frame.last == 10, frame.count > 1 else { return false }
            let line = Data(frame.dropLast())
            guard !line.contains(10) else { return false }
            lines.append(line)
        }
        return admit(lines, connection: connection, deadline: deadline, binding: binding)
    }
    private func armWrite() { if !writeArmed, !stopped { writeArmed = true; writer?.resume() } }
    private func disarmWrite() { if writeArmed { writeArmed = false; writer?.suspend() } }
    private func scheduleDeadline() {
        deadlineTask?.cancel(); deadlineTask = nil
        guard let deadline = outbox.nextDeadline, !stopped else { return }
        let delay = max(0, deadline - clock())
        guard delay.isFinite, delay < 86_400 else { stop(.timeout); return }
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard let self, !self.stopped else { return }
            if let d = self.outbox.nextDeadline, self.clock() >= d { self.stop(.timeout) }
            else { self.scheduleDeadline() }
        }
    }
    private func writeReady() {
        guard !stopped else { return }
        guard mayWrite() else { stop(.revoked); return }
        var budget = 65_536
        do {
            while budget > 0, !stopped,
                  let slice = try outbox.peek(connection: connection, now: clock(), limit: budget) {
                // Recheck at the final write boundary. Bytes already written cannot be retracted.
                guard mayWrite(), bindings[slice.ticket]?() ?? true, clock() < slice.deadline else { stop(.revoked); return }
                let result = Self.writeWithoutSIGPIPE(input.fileHandleForWriting.fileDescriptor, slice.bytes)
                if result < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK { break }
                    if errno == EINTR { continue }
                    stop(.io(errno)); return
                }
                guard result > 0 else { stop(.io(EIO)); return }
                budget -= result
                let complete = try outbox.advance(ticket: slice.ticket, bytesWritten: result,
                                                  connection: connection, now: clock())
                if complete { bindings[slice.ticket] = nil; onLocallyWritten?(slice.ticket) }
            }
            if outbox.count == 0 { disarmWrite() }
            scheduleDeadline()
        } catch { stop(.timeout) }
    }
    private func readReady() {
        guard !stopped else { return }
        var budget = 65_536
        while budget > 0, !stopped {
            var bytes = [UInt8](repeating: 0, count: min(8192, budget))
            let size = read(output.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
            if size < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                if errno == EINTR { continue }
                stop(.io(errno)); return
            }
            if size == 0 { stop(buffer.isEmpty ? .eof : .framing); return }
            budget -= size; buffer.append(contentsOf: bytes.prefix(size))
            while let newline = buffer.firstIndex(of: 10), !stopped {
                let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                guard !line.isEmpty, line.count <= Self.maximumLine else { stop(.framing); return }
                onLine?(line) // synchronous bounded dispatch; owner must not log or await here
            }
            guard buffer.count <= Self.maximumLine else { stop(.framing); return }
        }
    }
    private static func writeWithoutSIGPIPE(_ fd: Int32, _ bytes: Data) -> Int {
        var signals = sigset_t(), original = sigset_t(), prior = sigset_t()
        sigemptyset(&signals); sigaddset(&signals, SIGPIPE)
        let error = pthread_sigmask(SIG_BLOCK, &signals, &original)
        guard error == 0 else { errno = error; return -1 }
        sigpending(&prior); let wasPending = sigismember(&prior, SIGPIPE) == 1
        let result = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        let saved = errno
        if result < 0, saved == EPIPE, !wasPending {
            var pending = sigset_t(); sigpending(&pending)
            if sigismember(&pending, SIGPIPE) == 1 { var signal: Int32 = 0; _ = sigwait(&signals, &signal) }
        }
        _ = pthread_sigmask(SIG_SETMASK, &original, nil); errno = saved
        return result
    }
    func stop(_ reason: End = .localStop) {
        guard !stopped else { return }
        stopped = true; deadlineTask?.cancel(); deadlineTask = nil
        outbox.close(); bindings.removeAll(); buffer.removeAll()
        if reader == nil { try? output.fileHandleForReading.close() }
        if writer == nil { try? input.fileHandleForWriting.close() }
        reader?.cancel(); reader = nil
        if !writeArmed { writer?.resume() }
        writer?.cancel(); writer = nil; writeArmed = false
        // The unregistered handles also need closing when start failed before source creation.
        if !started { try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close() }
        try? input.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
        if started, process.isRunning { process.terminate() }
        let callback = onEnd; onEnd = nil; onLine = nil; onLocallyWritten = nil
        callback?(reason)
    }
    // Runtime must call stop before releasing its sole strong reference. No remote process groups are killed.
}
