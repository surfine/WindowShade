// 专用串行线程上的有界进程通道。Process 不经过 shell；错误流丢弃，不记录提示词。
// 进程白名单/路径准入和 A4 授权由宿主完成。本文件不寻找或启动 Codex。
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
final class WS2ProcessChannel {
    enum Failure: Error { case invalid, closed, timeout, tooLarge, io(Int32) }
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private var pending = Data()
    private var started = false
    private(set) var stopped = false
    // FileHandle 关第二次会抛 ObjC 异常直接把进程打掉；每个口只关一次。
    private var closedInputRead = false, closedInputWrite = false
    private var closedOutputRead = false, closedOutputWrite = false
    static let maximumFrame = 1_048_576
    init(executable: URL, arguments: [String], workingDirectory: URL, environment: [String:String]) throws {
        guard executable.isFileURL,executable.path.hasPrefix("/"),workingDirectory.isFileURL,
              !arguments.contains(where:{$0.utf8.contains(0)}),FileManager.default.isExecutableFile(atPath:executable.path) else { throw Failure.invalid }
        process.executableURL = executable; process.arguments = arguments
        process.currentDirectoryURL = workingDirectory; process.environment = environment
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
    }
    func start() throws {
        guard !started,!stopped else { throw Failure.invalid }
        do { try process.run(); started = true } catch { stop(); throw error }
        do { try input.fileHandleForReading.close() } catch { stop(); throw error }
        closedInputRead = true
        do { try output.fileHandleForWriting.close() } catch { stop(); throw error }
        closedOutputWrite = true
        // 非阻塞写保证 poll 后管道容量改变时仍能尊重期限。
        let fd = input.fileHandleForWriting.fileDescriptor
        guard fcntl(fd,F_SETFL,O_NONBLOCK) == 0 else { stop(); throw Failure.io(errno) }
    }
    private func ready(_ fd:Int32,_ events:Int16,deadline:Double) throws {
        guard started,!stopped else { throw Failure.closed }
        while true {
            let remaining = deadline-ProcessInfo.processInfo.systemUptime
            guard remaining.isFinite,remaining > 0 else { throw Failure.timeout }
            var item = pollfd(fd:fd,events:events,revents:0)
            let n = poll(&item,1,Int32(min(120_000,max(1,ceil(remaining*1000)))))
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw Failure.timeout }
            if item.revents & events != 0 { return }
            throw Failure.closed
        }
    }
    func send(_ data:Data, deadline:Double) throws {
        // 关掉的 FileHandle 连问 fileDescriptor 都会抛 ObjC 异常；先按状态拒绝。
        guard started,!stopped else { throw Failure.closed }
        guard data.count <= Self.maximumFrame,!data.contains(10) else { throw Failure.tooLarge }
        let fd = input.fileHandleForWriting.fileDescriptor, bytes = data+Data([10])
        // 管道写端 SIGPIPE 必须在线程局部屏蔽；不能为整个 App 改全局信号处理。
        var signals = sigset_t(), original = sigset_t(); sigemptyset(&signals); sigaddset(&signals,SIGPIPE)
        guard pthread_sigmask(SIG_BLOCK,&signals,&original) == 0 else { throw Failure.invalid }
        var prior = sigset_t(); sigpending(&prior); let pendingBefore = sigismember(&prior,SIGPIPE) == 1
        defer { _ = pthread_sigmask(SIG_SETMASK,&original,nil) }
        var offset = 0
        while offset < bytes.count {
            try ready(fd,Int16(POLLOUT),deadline:deadline)
            let n = bytes.withUnsafeBytes { write(fd,$0.baseAddress!.advanced(by:offset),bytes.count-offset) }
            if n < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            if n < 0 && errno == EPIPE && !pendingBefore {
                // 本线程同步写产生 SIGPIPE 后，屏蔽状态下 sigwait 只消费该待决信号。
                var check = sigset_t(); sigpending(&check)
                if sigismember(&check,SIGPIPE) == 1 { var number:Int32 = 0; _ = sigwait(&signals,&number) }
            }
            guard n > 0 else { throw Failure.closed }; offset += n
        }
    }
    func readLine(deadline:Double) throws -> Data {
        guard started,!stopped else { throw Failure.closed }
        let fd = output.fileHandleForReading.fileDescriptor
        while true {
            if let i = pending.firstIndex(of:10) {
                let line = Data(pending[..<i]); pending.removeSubrange(...i)
                guard line.count <= Self.maximumFrame else { throw Failure.tooLarge }; return line
            }
            guard pending.count <= Self.maximumFrame else { throw Failure.tooLarge }
            try ready(fd,Int16(POLLIN),deadline:deadline)
            var bytes = [UInt8](repeating:0,count:8192); let n = read(fd,&bytes,bytes.count)
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw Failure.closed }; pending.append(contentsOf:bytes.prefix(n))
        }
    }
    func stop() {
        guard !stopped else { return }; stopped = true; pending.removeAll()
        if !closedInputWrite { closedInputWrite = true; try? input.fileHandleForWriting.close() }
        if !closedInputRead { closedInputRead = true; try? input.fileHandleForReading.close() }
        if !closedOutputRead { closedOutputRead = true; try? output.fileHandleForReading.close() }
        if !closedOutputWrite { closedOutputWrite = true; try? output.fileHandleForWriting.close() }
        // 只终止自己持有的 Process。绝不杀外部 CLI、进程组或按名字 pkill。
        if started,process.isRunning { process.terminate() }
    }
    deinit { stop() }
}
