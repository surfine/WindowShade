import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
enum WS2BoundedInput {
    // stdin 可以分多次到达。只在专用 helper/工作线程读取，超时不等待完整 JSON。
    static func readAll(fd: Int32, maximum: Int = 65_536, deadline: Double) throws -> Data {
        var bytes = Data(), buffer = [UInt8](repeating:0,count:4096)
        guard maximum > 0,maximum <= 1_048_576 else { throw WS2SocketError.tooLarge }
        while true {
            let left = deadline-ProcessInfo.processInfo.systemUptime
            guard left.isFinite,left > 0 else { throw WS2SocketError.timeout }
            var item = pollfd(fd:fd,events:Int16(POLLIN),revents:0)
            let rc = poll(&item,1,Int32(min(120_000,max(1,ceil(left*1000)))))
            if rc < 0 && errno == EINTR { continue }
            guard rc > 0 else { throw WS2SocketError.timeout }
            guard item.revents & Int16(POLLIN | POLLHUP) != 0 else { throw WS2SocketError.disconnected }
            let n = read(fd,&buffer,buffer.count)
            if n < 0 && errno == EINTR { continue }
            guard n >= 0 else { throw WS2SocketError.system(errno) }
            if n == 0 { return bytes }
            guard n <= maximum-bytes.count else { throw WS2SocketError.tooLarge }
            bytes.append(contentsOf:buffer.prefix(n))
        }
    }
}
