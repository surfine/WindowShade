// 同目录原子替换、0600 备份、协作式锁和写前复核。不会自行寻找或修改 home。
// 不声称 POSIX rename 能对不遵守锁的第三方写者提供真正的原子 compare-and-swap。
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
enum WS2AtomicConfiguration {
    enum Failure: Error { case unsafeFile, busy, changed, io(Int32) }
    static func validateAncestors(_ path: String) throws {
        guard path.hasPrefix("/"),!path.utf8.contains(0) else { throw Failure.unsafeFile }
        let parent = URL(fileURLWithPath:path).deletingLastPathComponent()
        var current = ""
        for part in parent.pathComponents where part != "/" {
            current += "/"+part; var st = stat()
            guard lstat(current,&st) == 0,st.st_mode & 0o170000 == 0o040000 else { throw Failure.unsafeFile }
            // 根拥有的 sticky 临时目录只供测试；立即父目录仍必须由本用户拥有且不可组/全局写。
            guard st.st_mode & 0o022 == 0 || (st.st_mode & 0o1000 != 0 && st.st_uid == 0) else { throw Failure.unsafeFile }
        }
        var st = stat()
        guard lstat(parent.path,&st) == 0,st.st_uid == geteuid(),st.st_mode & 0o022 == 0 else { throw Failure.unsafeFile }
    }
    static func readRegular(_ path: String) throws -> Data {
        try validateAncestors(path)
        let fd = open(path,O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.io(errno) }; defer { _ = close(fd) }
        var st = stat()
        guard fstat(fd,&st) == 0,st.st_uid == geteuid(),st.st_mode & 0o170000 == 0o100000,st.st_nlink == 1,
              st.st_size >= 0,st.st_size <= 1_048_576 else { throw Failure.unsafeFile }
        var data = Data(), buffer = [UInt8](repeating:0,count:8192)
        while true {
            let n = read(fd,&buffer,buffer.count)
            if n < 0 && errno == EINTR { continue }
            guard n >= 0 else { throw Failure.io(errno) }; if n == 0 { break }
            data.append(contentsOf:buffer.prefix(n)); guard data.count <= 1_048_576 else { throw Failure.unsafeFile }
        }
        return data
    }
    static func commit(_ preview: WS2HookConfiguration.Preview, to url: URL, confirmed: Bool) throws -> URL {
        guard confirmed,url.isFileURL,url.lastPathComponent != "",url.path.hasPrefix("/") else { throw Failure.unsafeFile }
        let path = url.path, parent = url.deletingLastPathComponent()
        try validateAncestors(path)
        // 锁和暂存名称不可预测；锁名称稳定，避免两份 WindowShade 同时写。
        let lock = path+".windowshade.lock"
        let lockFD = open(lock,O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC,0o600)
        guard lockFD >= 0 else { throw Failure.busy }
        defer { _ = close(lockFD); _ = unlink(lock) }
        let current = try readRegular(path); guard current == preview.original else { throw Failure.changed }
        let nonce = UUID().uuidString
        let backup = parent.appendingPathComponent(url.lastPathComponent+".windowshade-"+nonce+".bak")
        let temporary = parent.appendingPathComponent(".windowshade-"+nonce+".tmp")
        try writeNew(current,to:backup.path)
        do {
            try writeNew(preview.replacement,to:temporary.path)
            guard try readRegular(path) == preview.original else { throw Failure.changed }
            guard rename(temporary.path,path) == 0 else { throw Failure.io(errno) }
            let dir = open(parent.path,O_RDONLY | O_CLOEXEC)
            guard dir >= 0 else { throw Failure.io(errno) }; defer { _ = close(dir) }
            guard fsync(dir) == 0 else { throw Failure.io(errno) }
            guard try readRegular(path) == preview.replacement else { throw Failure.changed }
        } catch { _ = unlink(temporary.path); throw error }
        return backup
    }
    // 首次安装：link 的目标必须不存在；不会用 rename 覆盖刚出现的配置。
    static func createNew(_ data: Data, to url: URL, confirmed: Bool) throws {
        guard confirmed,url.isFileURL,data.count <= 1_048_576,
              (try? JSONSerialization.jsonObject(with:data)) is [String:Any] else { throw Failure.unsafeFile }
        try validateAncestors(url.path)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".windowshade-"+UUID().uuidString+".new")
        try writeNew(data,to:temporary.path); defer { _ = unlink(temporary.path) }
        guard link(temporary.path,url.path) == 0 else { throw Failure.changed }
        guard unlink(temporary.path) == 0 else { throw Failure.io(errno) }
        let dir = open(url.deletingLastPathComponent().path,O_RDONLY | O_CLOEXEC)
        guard dir >= 0 else { throw Failure.io(errno) }; defer { _ = close(dir) }
        guard fsync(dir) == 0 else { throw Failure.io(errno) }
    }
    private static func writeNew(_ data: Data, to path: String) throws {
        let fd = open(path,O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC,0o600)
        guard fd >= 0 else { throw Failure.io(errno) }; defer { _ = close(fd) }
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { raw in write(fd,raw.baseAddress!.advanced(by:offset),data.count-offset) }
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw Failure.io(errno) }; offset += n
        }
        guard fsync(fd) == 0 else { throw Failure.io(errno) }
    }
    static func rollback(from backup: URL, expected: Data, destination: URL, confirmed: Bool) throws -> URL {
        let original = try readRegular(backup.path)
        return try commit(.init(original:expected,replacement:original,command:""),to:destination,confirmed:confirmed)
    }
}
