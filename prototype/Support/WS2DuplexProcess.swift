// One owner, one native reaper, one pipe reader/writer; no Foundation.Process reaper races.
import Foundation
import Dispatch
import WS2ProcessNative
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@MainActor final class WS2DuplexProcess {
    enum Failure: Error { case invalid, io(Int32), notRunning }
    enum End: Equatable { case localStop, eof, processExit, io(Int32), framing, timeout, revoked }
    struct Termination: Equatable, Sendable { let status: Int32; let wasSignalled: Bool }
    private(set) var termination: Termination?
    private(set) var diagnostics: WS2DiagnosticTail?
    private(set) var leaderReaped = false
    private(set) var supervisionError: Int32?
    private(set) var groupTerminationRequested = false
    private(set) var groupKillRequested = false
    private var child: OpaquePointer?
    private var childTimer: (any DispatchSourceTimer)?
    private var inputHandle: FileHandle?, outputHandle: FileHandle?, errorHandle: FileHandle?
    private var reader: (any DispatchSourceRead)?, writer: (any DispatchSourceWrite)?, errorReader: (any DispatchSourceRead)?
    private var writeArmed = false
    private var deadlineTask: Task<Void,Never>?
    private var buffer = Data()
    private var outbox: WS2BoundedOutbox
    private var bindings: [UInt64: @MainActor () -> Bool] = [:]
    private var started = false
    private(set) var stopped = false
    let connection: UUID
    private let clock: () -> Double
    private let mayWrite: () -> Bool
    private let executable: URL, workingDirectory: URL
    private let arguments: [String], environment: [String:String]
    var onLine: ((Data) -> Void)?
    var onEnd: ((End) -> Void)?
    var onLocallyWritten: ((UInt64) -> Void)?
    // Separate fact from closing the protocol. Never means all descendants (including escaped groups) exited.
    var onReaped: ((Termination) -> Void)?
    static let maximumLine = 1_048_576
    init(connection: UUID = UUID(), executable: URL, arguments: [String], workingDirectory: URL,
         environment: [String:String], clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         diagnosticByteLimit: Int? = nil, mayWrite: @escaping () -> Bool) throws {
        guard executable.isFileURL, executable.path.hasPrefix("/"), workingDirectory.isFileURL,
              workingDirectory.path.hasPrefix("/"), !executable.path.utf8.contains(0), !workingDirectory.path.utf8.contains(0),
              arguments.count <= 256, !arguments.contains(where: { $0.utf8.contains(0) || $0.utf8.count > 65_536 }),
              environment.count <= 256, !environment.contains(where: { $0.key.isEmpty || $0.key.contains("=") || $0.key.utf8.contains(0) || $0.value.utf8.contains(0) }),
              FileManager.default.isExecutableFile(atPath: executable.path) else { throw Failure.invalid }
        if let n = diagnosticByteLimit, !(1...65_536).contains(n) { throw Failure.invalid }
        diagnostics = diagnosticByteLimit.map { WS2DiagnosticTail(capacity:$0) }
        self.connection=connection; self.clock=clock; self.mayWrite=mayWrite
        self.executable=executable; self.arguments=arguments; self.workingDirectory=workingDirectory; self.environment=environment
        outbox = WS2BoundedOutbox(connection:connection)
    }
    func start() throws {
        guard !started, !stopped else { throw Failure.invalid }
        var argv = ([executable.path] + arguments).map { strdup($0) }
        var envp = environment.keys.sorted().map { strdup($0 + "=" + environment[$0]!) }
        guard argv.allSatisfy({$0 != nil}), envp.allSatisfy({$0 != nil}) else {
            argv.forEach { free($0) }; envp.forEach { free($0) }; throw Failure.io(ENOMEM)
        }
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        argv.append(nil); envp.append(nil)
        var input: Int32 = -1, output: Int32 = -1, error: Int32 = -1
        let code = executable.path.withCString { exe in workingDirectory.path.withCString { cwd in
            argv.withUnsafeMutableBufferPointer { a in envp.withUnsafeMutableBufferPointer { e in
                ws2_child_spawn(exe,a.baseAddress,e.baseAddress,cwd,diagnostics == nil ? 0 : 1,&child,&input,&output,&error)
            } }
        } }
        guard code == 0, child != nil else { stopped=true; throw Failure.io(code) }
        started=true
        inputHandle=FileHandle(fileDescriptor:input,closeOnDealloc:true)
        outputHandle=FileHandle(fileDescriptor:output,closeOnDealloc:true)
        if error >= 0 { errorHandle=FileHandle(fileDescriptor:error,closeOnDealloc:true) }
        let r=DispatchSource.makeReadSource(fileDescriptor:output,queue:.main)
        let w=DispatchSource.makeWriteSource(fileDescriptor:input,queue:.main)
        r.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readReady() } }
        w.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.writeReady() } }
        let rh=outputHandle!, wh=inputHandle!
        r.setCancelHandler { try? rh.close() }; w.setCancelHandler { try? wh.close() }
        reader=r; writer=w; r.resume()
        if let eh=errorHandle {
            let e=DispatchSource.makeReadSource(fileDescriptor:eh.fileDescriptor,queue:.main)
            e.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readDiagnosticReady() } }
            e.setCancelHandler { try? eh.close() }; errorReader=e; e.resume()
        }
        // Only active while this explicit CLI session owns a child. No idle-app polling.
        let timer=DispatchSource.makeTimerSource(queue:.main)
        timer.schedule(deadline:.now(),repeating:.milliseconds(20),leeway:.milliseconds(5))
        // Deliberate temporary self-retention until reaping. Runtime may release the closed session earlier.
        timer.setEventHandler { [self] in MainActor.assumeIsolated { self.pollChild() } }
        childTimer=timer; timer.resume()
    }
    private func pollChild() {
        guard let child else { return }
        var state=WS2ChildState()
        let error=ws2_child_poll(child,&state)
        groupTerminationRequested=state.term_sent != 0; groupKillRequested=state.kill_sent != 0
        if state.direct_exited != 0, termination == nil {
            termination = .init(status:state.exit_status,wasSignalled:state.was_signalled != 0)
            // One final bounded snapshot; never wait for descendants to close inherited descriptors.
            if !stopped { readReady(checkChild:false); readDiagnosticReady(); if !stopped { stop(.processExit) } }
        }
        if error != 0 {
            supervisionError=error
            stop(.io(error)); childTimer?.setEventHandler {}; childTimer?.cancel(); childTimer=nil
            // Lost ownership must not lead to a signal against a potentially reused PID.
            _=ws2_child_destroy(child);self.child=nil
            return
        }
        if state.reaped != 0 {
            leaderReaped=true; _=ws2_child_destroy(child); self.child=nil
            childTimer?.setEventHandler {}; childTimer?.cancel(); childTimer=nil
            if let termination { let cb=onReaped; onReaped=nil; cb?(termination) }
        }
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
        pollChild()
        guard !stopped else { return }
        guard mayWrite() else { stop(.revoked); return }
        var budget = 65_536
        do {
            while budget > 0, !stopped,
                  let slice = try outbox.peek(connection: connection, now: clock(), limit: budget) {
                // Recheck at the final write boundary. Bytes already written cannot be retracted.
                guard mayWrite(), bindings[slice.ticket]?() ?? true, clock() < slice.deadline else { stop(.revoked); return }
                let result = Self.writeWithoutSIGPIPE(inputHandle!.fileDescriptor, slice.bytes)
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
    private func readReady(checkChild: Bool = true) {
        if checkChild { pollChild() }
        guard !stopped else { return }
        var budget = 65_536
        while budget > 0, !stopped {
            var bytes = [UInt8](repeating: 0, count: min(8192, budget))
            let size = read(outputHandle!.fileDescriptor, &bytes, bytes.count)
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
    private func readDiagnosticReady() {
        guard let pipe=errorHandle, errorReader != nil, !stopped else { return }
        var budget=65_536
        while budget > 0 {
            var chunk=[UInt8](repeating:0,count:min(8192,budget))
            let count=read(pipe.fileDescriptor,&chunk,chunk.count)
            if count < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                errorReader?.cancel(); errorReader=nil; return
            }
            if count == 0 { errorReader?.cancel(); errorReader=nil; return }
            budget -= count; diagnostics?.append(Data(chunk.prefix(count)))
        }
    }
    func clearDiagnostics() { diagnostics?.clear() }
    private static func writeWithoutSIGPIPE(_ fd: Int32, _ bytes: Data) -> Int {
        // 真机发现：只在本线程屏蔽 SIGPIPE 在多线程进程里挡不住它——内核会把信号投给别的线程，
        // 默认动作直接杀掉 App（第五份 IO04 第一次在 Mac 上跑就复现）。这里进程级忽略一次，
        // 写失败仍然如实返回 EPIPE；下面的线程级屏蔽与 sigwait 只作第二层。
        Self.ignoreSIGPIPEOnce
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
    private static let ignoreSIGPIPEOnce: Void = { _ = signal(SIGPIPE, SIG_IGN) }()
    func stop(_ reason: End = .localStop) {
        guard !stopped else { return }
        readDiagnosticReady(); stopped=true
        deadlineTask?.cancel(); deadlineTask=nil; outbox.close(); bindings.removeAll(); buffer.removeAll()
        reader?.cancel(); reader=nil
        if writer != nil, !writeArmed { writer?.resume() }
        writer?.cancel(); writer=nil; writeArmed=false
        errorReader?.cancel(); errorReader=nil
        if let child { let error=ws2_child_stop(child); if error != 0 { supervisionError=error } }
        let cb=onEnd; onEnd=nil; onLine=nil; onLocallyWritten=nil; cb?(reason)
        // The reaper timer survives protocol closure. A stopped pipe is not reaping evidence.
    }
}
