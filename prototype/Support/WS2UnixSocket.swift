// 原创本机 socket。同步方法只允许在专用串行工作队列调用。
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
enum WS2SocketError: Error { case system(Int32), invalidPath, insecureParent, foreignPeer, tooLarge, timeout, disconnected, occupied }
final class WS2UnixSocket {
    private(set) var fd: Int32
    private var boundPath: String?
    private var inode: UInt64?
    private var pending = Data()
    static let maximumFrame = 65_536
    private init(fd: Int32) { self.fd = fd }
    private static func address(_ path: String) throws -> sockaddr_un {
        guard !path.utf8.contains(0),path.hasPrefix("/") else { throw WS2SocketError.invalidPath }
        var result = sockaddr_un()
        result.sun_family = sa_family_t(AF_UNIX)
        #if canImport(Darwin)
        result.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        let bytes = Array(path.utf8)+[0]
        guard bytes.count <= MemoryLayout.size(ofValue:result.sun_path) else { throw WS2SocketError.invalidPath }
        withUnsafeMutableBytes(of:&result.sun_path) { raw in raw.initializeMemory(as:UInt8.self,repeating:0); raw.copyBytes(from:bytes) }
        return result
    }
    static func validateParent(_ path: String) throws {
        let path = WS2AtomicConfiguration.canonicalRoot(path)
        let parent = URL(fileURLWithPath:path).deletingLastPathComponent().path
        // 所有目录分量拒绝 symlink；父目录必须本 UID、0700。不会替用户 chmod 现有目录。
        var current = ""
        for component in URL(fileURLWithPath:parent).pathComponents where component != "/" {
            current += "/"+component; var st = stat()
            guard lstat(current,&st) == 0, (st.st_mode & 0o170000) == 0o040000 else { throw WS2SocketError.insecureParent }
        }
        var st = stat()
        guard lstat(parent,&st) == 0,st.st_uid == geteuid(),(st.st_mode & 0o777) == 0o700 else { throw WS2SocketError.insecureParent }
    }
    private static func make() throws -> Int32 {
        #if canImport(Darwin)
        let fd = socket(AF_UNIX,SOCK_STREAM,0)
        #else
        let fd = socket(AF_UNIX,Int32(SOCK_STREAM.rawValue),0)
        #endif
        guard fd >= 0 else { throw WS2SocketError.system(errno) }
        guard fcntl(fd,F_SETFD,FD_CLOEXEC) == 0, fcntl(fd,F_SETFL,O_NONBLOCK) == 0 else { let e = errno; _ = close(fd); throw WS2SocketError.system(e) }
        #if canImport(Darwin)
        var one: Int32 = 1
        guard setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&one,socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            let e = errno; _ = close(fd); throw WS2SocketError.system(e)
        }
        #endif
        return fd
    }
    static func listen(at path: String) throws -> WS2UnixSocket {
        try validateParent(path); var a = try address(path); var st = stat()
        guard lstat(path,&st) != 0,errno == ENOENT else { throw WS2SocketError.occupied }
        let fd = try make(); let result = WS2UnixSocket(fd:fd)
        let bound = withUnsafePointer(to:&a) { p in p.withMemoryRebound(to:sockaddr.self,capacity:1) {
            #if canImport(Darwin)
            Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))
            #else
            Glibc.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))
            #endif
        }}
        guard bound == 0 else { throw WS2SocketError.system(errno) }
        result.boundPath = path
        if lstat(path,&st) == 0 { result.inode = UInt64(st.st_ino) }
        guard chmod(path,0o600) == 0 else { throw WS2SocketError.system(errno) }
        #if canImport(Darwin)
        let status = Darwin.listen(fd,8)
        #else
        let status = Glibc.listen(fd,8)
        #endif
        guard status == 0 else { throw WS2SocketError.system(errno) }; return result
    }
    static func connect(to path: String, deadline: Double = ProcessInfo.processInfo.systemUptime + 1) throws -> WS2UnixSocket {
        try validateParent(path); var a = try address(path); var st = stat()
        guard lstat(path,&st) == 0,st.st_uid == geteuid(),(st.st_mode & 0o170000) == 0o140000,
              st.st_mode & 0o777 == 0o600 else { throw WS2SocketError.insecureParent }
        let fd = try make(); let result = WS2UnixSocket(fd:fd)
        let status = withUnsafePointer(to:&a) { p in p.withMemoryRebound(to:sockaddr.self,capacity:1) {
            #if canImport(Darwin)
            Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))
            #else
            Glibc.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))
            #endif
        }}
        if status != 0 {
            guard errno == EINPROGRESS else { throw WS2SocketError.system(errno) }
            try result.wait(Int16(POLLOUT),deadline:deadline)
            var error: Int32 = 0, length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&length) == 0 else { throw WS2SocketError.system(errno) }
            guard error == 0 else { throw WS2SocketError.system(error) }
        }
        try result.checkPeer(); return result
    }
    private func checkPeer() throws {
        #if canImport(Darwin)
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd,&uid,&gid) == 0,uid == geteuid() else { throw WS2SocketError.foreignPeer }
        #else
        struct Credentials { var pid: pid_t = 0; var uid: uid_t = 0; var gid: gid_t = 0 }
        var peer = Credentials(), size = socklen_t(MemoryLayout<Credentials>.size)
        guard getsockopt(fd,SOL_SOCKET,SO_PEERCRED,&peer,&size) == 0,peer.uid == geteuid() else { throw WS2SocketError.foreignPeer }
        #endif
    }
    func accept(deadline: Double) throws -> WS2UnixSocket {
        try wait(Int16(POLLIN),deadline:deadline)
        #if canImport(Darwin)
        let accepted = Darwin.accept(fd,nil,nil)
        #else
        let accepted = Glibc.accept(fd,nil,nil)
        #endif
        guard accepted >= 0 else { throw WS2SocketError.system(errno) }
        let result = WS2UnixSocket(fd:accepted)
        guard fcntl(accepted,F_SETFD,FD_CLOEXEC) == 0, fcntl(accepted,F_SETFL,O_NONBLOCK) == 0 else { throw WS2SocketError.system(errno) }
        #if canImport(Darwin)
        var one: Int32 = 1
        guard setsockopt(accepted,SOL_SOCKET,SO_NOSIGPIPE,&one,socklen_t(MemoryLayout<Int32>.size)) == 0 else { throw WS2SocketError.system(errno) }
        #endif
        try result.checkPeer(); return result
    }
    private func wait(_ events: Int16, deadline: Double) throws {
        guard fd >= 0 else { throw WS2SocketError.disconnected }
        while true {
            let left = deadline-ProcessInfo.processInfo.systemUptime
            guard left.isFinite,left > 0 else { throw WS2SocketError.timeout }
            var item = pollfd(fd:fd,events:events,revents:0)
            let result = poll(&item,1,Int32(min(120_000,max(1,ceil(left*1000)))))
            if result < 0 && errno == EINTR { continue }
            guard result >= 0 else { throw WS2SocketError.system(errno) }
            if result == 0 { throw WS2SocketError.timeout }
            if item.revents & events != 0 { return }
            throw WS2SocketError.disconnected
        }
    }
    func sendLine(_ value: Data, deadline: Double) throws {
        guard !value.contains(10),value.count <= Self.maximumFrame else { throw WS2SocketError.tooLarge }
        let bytes = value+Data([10]); var offset = 0
        while offset < bytes.count {
            try wait(Int16(POLLOUT),deadline:deadline)
            let count: Int = bytes.withUnsafeBytes { ptr in
                #if canImport(Darwin)
                Darwin.send(fd,ptr.baseAddress!.advanced(by:offset),bytes.count-offset,0)
                #else
                Glibc.send(fd,ptr.baseAddress!.advanced(by:offset),bytes.count-offset,Int32(MSG_NOSIGNAL))
                #endif
            }
            if count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) { continue }
            guard count > 0 else { throw WS2SocketError.disconnected }; offset += count
        }
    }
    func readLine(deadline: Double) throws -> Data {
        while true {
            if let newline = pending.firstIndex(of:10) {
                let line = Data(pending[..<newline]); pending.removeSubrange(...newline)
                guard line.count <= Self.maximumFrame else { throw WS2SocketError.tooLarge }; return line
            }
            guard pending.count <= Self.maximumFrame else { throw WS2SocketError.tooLarge }
            try wait(Int16(POLLIN),deadline:deadline)
            var buffer = [UInt8](repeating:0,count:4096)
            let count = recv(fd,&buffer,buffer.count,0)
            if count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) { continue }
            guard count > 0 else { throw WS2SocketError.disconnected }
            pending.append(contentsOf:buffer.prefix(count))
        }
    }
    func closeSocket() {
        if fd >= 0 { _ = close(fd); fd = -1 }
        if let boundPath,let inode {
            var st = stat()
            if lstat(boundPath,&st) == 0,UInt64(st.st_ino) == inode,st.st_uid == geteuid(),st.st_mode & 0o170000 == 0o140000 { _ = unlink(boundPath) }
        }
        boundPath = nil; inode = nil; pending.removeAll()
    }
    deinit { closeSocket() }
}
