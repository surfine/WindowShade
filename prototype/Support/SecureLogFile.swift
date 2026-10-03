// WindowShade 2 · 原创。队列隔离的文件写入器；不包含日志内容过滤规则。
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// 仅在 WindowShadeLogger 的串行队列内使用，不把文件描述符跨队列传递。
/// 失败后由调用方停用持久日志；不回退到 /tmp、不把原日志写到 stderr。
final class SecureLogFile {
    enum Failure: Error { case invalidPath, untrustedDirectory, unsafeFile, system(Int32), recordTooLarge }
    private var directoryFD: Int32 = -1
    private var fileFD: Int32 = -1
    private let name: String
    private let maximumBytes: Int64
    private(set) var rotationCount = 0

    /// parent 必须已经存在。只有最后一级专用日志目录会被改为 0700。
    /// 所有祖先必须是当前用户或 root 所有，且不可被组或其他用户写入。
    /// 不允许路径中的符号链接；/tmp 形式的开发覆盖值也不会例外。
    init(path: String, maximumBytes: Int64 = 5 * 1024 * 1024) throws {
        guard path.hasPrefix("/"), !path.contains("\0"), !path.hasSuffix("/"), maximumBytes >= 16,
              path.utf8.count <= 4096 else { throw Failure.invalidPath }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }),
              let last = parts.last else { throw Failure.invalidPath }
        name = last; self.maximumBytes = maximumBytes
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure.system(errno) }
        do {
            for (index, component) in parts.dropLast().enumerated() {
                let isLeaf = index == parts.count - 2
                let child = openat(fd, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                guard child >= 0 else { throw Failure.system(errno) }
                do {
                    var st = stat()
                    guard fstat(child, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR,
                          st.st_uid == geteuid() || st.st_uid == 0 else { throw Failure.untrustedDirectory }
                    if isLeaf {
                        guard st.st_uid == geteuid() else { throw Failure.untrustedDirectory }
                        try Self.harden(child, mode: 0o700)
                    } else {
                        guard st.st_mode & 0o022 == 0 else { throw Failure.untrustedDirectory }
                    }
                } catch { _ = close(child); throw error }
                _ = close(fd); fd = child
            }
            directoryFD = fd; fd = -1
            try openCurrent()
        } catch {
            if fd >= 0 { _ = close(fd) }
            if directoryFD >= 0 { _ = close(directoryFD); directoryFD = -1 }
            throw error
        }
    }
    deinit { closeFiles() }
    func closeFiles() {
        if fileFD >= 0 { _ = fsync(fileFD); _ = close(fileFD); fileFD = -1 }
        if directoryFD >= 0 { _ = close(directoryFD); directoryFD = -1 }
    }
    /// 最大 16 KiB 单条；不接受空记录。轮转后当前文件与一个备份各至多 maximumBytes。
    func append(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 16 * 1024, Int64(data.count) <= maximumBytes else { throw Failure.recordTooLarge }
        guard directoryFD >= 0, fileFD >= 0 else { throw Failure.unsafeFile }
        var st = stat()
        guard fstat(fileFD, &st) == 0 else { throw Failure.system(errno) }
        try validateFile(st)
        guard st.st_size >= 0 else { throw Failure.unsafeFile }
        // 用减法避免恶意超大既有文件触发整数溢出。
        if st.st_size > maximumBytes - Int64(data.count) { try rotate() }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { throw Failure.recordTooLarge }
            var written = 0
            while written < raw.count {
                let n = write(fileFD, base.advanced(by: written), raw.count - written)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw Failure.system(errno) }
                written += n
            }
        }
    }
    private func validateFile(_ st: stat) throws {
        guard (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == geteuid(), st.st_nlink == 1 else { throw Failure.unsafeFile }
    }
    private func openCurrent() throws {
        let opened = openat(directoryFD, name, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, mode_t(0o600))
        guard opened >= 0 else { throw Failure.system(errno) }
        do {
            var st = stat(); guard fstat(opened, &st) == 0 else { throw Failure.system(errno) }
            try validateFile(st); try Self.harden(opened, mode: 0o600)
            fileFD = opened
        } catch { _ = close(opened); throw error }
    }
    private func rotate() throws {
        var held = stat(); var named = stat()
        guard fstat(fileFD, &held) == 0,
              fstatat(directoryFD, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              held.st_ino == named.st_ino, held.st_dev == named.st_dev else { throw Failure.unsafeFile }
        try validateFile(named)
        let backup = name + ".1"
        // 不打开后再截断；先检查备份，不跟随符号链接，也不删除未知对象。
        var previous = stat()
        if fstatat(directoryFD, backup, &previous, AT_SYMLINK_NOFOLLOW) == 0 {
            try validateFile(previous)
            guard unlinkat(directoryFD, backup, 0) == 0 else { throw Failure.system(errno) }
        } else if errno != ENOENT { throw Failure.system(errno) }
        guard fsync(fileFD) == 0 else { throw Failure.system(errno) }
        _ = close(fileFD); fileFD = -1
        guard renameat(directoryFD, name, directoryFD, backup) == 0 else { throw Failure.system(errno) }
        try openCurrent(); rotationCount += 1
    }
    private static func harden(_ fd: Int32, mode: mode_t) throws {
        #if canImport(Darwin)
        // 用空的 extended ACL 去掉继承/具名授权；单靠 chmod 不能作出同等承诺。
        // 签名由 Apple Libc/include/sys/acl.h 核对；此分支仍须在 SDK 27 编译和双账户实测。
        guard let acl = acl_init(0) else { throw Failure.system(errno) }
        defer { _ = acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_set_fd(fd, acl) == 0 else { throw Failure.system(errno) }
        #endif
        guard fchmod(fd, mode) == 0 else { throw Failure.system(errno) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_mode & 0o777 == mode else { throw Failure.unsafeFile }
    }
}
