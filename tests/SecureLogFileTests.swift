import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@main
struct SecureLogFileTests {
    static func main() throws {
        var t = TestSuite("PRIVACY-LOG")
        // 用本账户 home 的新随机目录，避免 /tmp 自身的公共可写性质干扰测试。
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ws2-log-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        func leaf(_ n:String) throws -> URL { let p=root.appendingPathComponent(n);try FileManager.default.createDirectory(at:p,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);return p }
        func mode(_ p:URL)->mode_t { var st=stat();_ = lstat(p.path,&st); return st.st_mode & 0o777 }
        func fails(_ block:()throws->Void)->Bool {do{try block();return false}catch{return true}}
        t.section("LOG-01", "新日志 → 父目录0700、文件0600，原文字节可读")
        let a=try leaf("a");let ap=a.appendingPathComponent("windowshade.log");let writer=try SecureLogFile(path:ap.path,maximumBytes:32)
        try writer.append(Data("hello\n".utf8))
        t.expect(mode(a)==0o700 && mode(ap)==0o600,"专用目录与文件权限")
        t.expect((try? String(contentsOf:ap,encoding:.utf8))=="hello\n","内容一致")
        t.section("LOG-02", "既有文件权限0644 → 写前收紧为0600")
        let b=try leaf("b");let bp=b.appendingPathComponent("log");try Data("old\n".utf8).write(to:bp);_=chmod(bp.path,0o644)
        let wb=try SecureLogFile(path:bp.path);try wb.append(Data("new\n".utf8));wb.closeFiles()
        t.expect(mode(bp)==0o600 && (try? String(contentsOf:bp,encoding:.utf8))=="old\nnew\n","保留既有日志但收紧权限")
        t.section("LOG-03", "大小超限 → 一个0600备份，不额外复制历史")
        try writer.append(Data(repeating:65,count:30));t.expect(writer.rotationCount==1,"真的发生轮转")
        t.expect(mode(a.appendingPathComponent("windowshade.log.1"))==0o600,"备份保持0600")
        t.expect((try? Data(contentsOf:ap).count)==30,"新文件只含当前记录")
        writer.closeFiles()
        t.section("LOG-04", "日志名为符号链接 → 拒绝，不改链接目标")
        let outside=root.appendingPathComponent("outside");try Data("secret".utf8).write(to:outside)
        let c=try leaf("c");let cp=c.appendingPathComponent("log");try FileManager.default.createSymbolicLink(at:cp,withDestinationURL:outside)
        t.expect(fails { _=try SecureLogFile(path:cp.path) },"拒绝末级链接")
        t.expect((try? String(contentsOf:outside,encoding:.utf8))=="secret","目标未被写入")
        t.section("LOG-05", "父目录为链接 → 拒绝，不沿链接创建日志")
        let parentLink=root.appendingPathComponent("linked");try FileManager.default.createSymbolicLink(at:parentLink,withDestinationURL:a)
        t.expect(fails { _=try SecureLogFile(path:parentLink.appendingPathComponent("new").path) },"拒绝路径中的链接")
        t.expect(!FileManager.default.fileExists(atPath:a.appendingPathComponent("new").path),"不创建目标文件")
        t.section("LOG-06", "日志为硬链接、FIFO或目录 → 立即拒绝，不阻塞")
        let d=try leaf("d");let dp=d.appendingPathComponent("log");_=link(outside.path,dp.path)
        t.expect(fails { _=try SecureLogFile(path:dp.path) },"拒绝多链接文件")
        let fifo=d.appendingPathComponent("fifo");_=mkfifo(fifo.path,0o600)
        t.expect(fails { _=try SecureLogFile(path:fifo.path) },"FIFO非阻塞拒绝")
        t.expect(fails { _=try SecureLogFile(path:d.path) },"拒绝目录作文件")
        t.section("LOG-07", "备份名被置为链接 → 轮转失败，不删除链接及其目标")
        let e=try leaf("e");let ep=e.appendingPathComponent("log");let we=try SecureLogFile(path:ep.path,maximumBytes:16)
        try we.append(Data(repeating:66,count:16));try FileManager.default.createSymbolicLink(at:e.appendingPathComponent("log.1"),withDestinationURL:outside)
        t.expect(fails {try we.append(Data("x".utf8))},"拒绝不安全备份")
        t.expect((try? FileManager.default.destinationOfSymbolicLink(atPath:e.appendingPathComponent("log.1").path))==outside.path,"不删除攻击者放置的未知对象")
        we.closeFiles()
        t.section("LOG-08", "路径含..、相对路径、公共可写祖先、超大记录 → 拒绝")
        t.expect(fails {_=try SecureLogFile(path:"relative/log")},"相对路径拒绝")
        t.expect(fails {_=try SecureLogFile(path:root.path+"/a/../log")},"不规范化遍历路径")
        let publicParent=try leaf("public");_=chmod(publicParent.path,0o777);let privateChild=publicParent.appendingPathComponent("inside");try FileManager.default.createDirectory(at:privateChild,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        t.expect(fails {_=try SecureLogFile(path:privateChild.appendingPathComponent("log").path)},"不可只看最后一级权限")
        let last=try SecureLogFile(path:ap.path)
        t.expect(fails {try last.append(Data(repeating:65,count:16*1024+1))},"超大记录不写")
        last.closeFiles()
        #if canImport(Darwin)
        t.section("LOG-09", "macOS 空ACL已应用 → 文件的extended ACL必须没有条目")
        let fd=open(ap.path,O_RDONLY|O_NOFOLLOW);defer{if fd>=0{_=close(fd)}}
        // macOS：空 ACL 写入后，acl_get_fd 返回 NULL 且 errno == ENOENT，意思是“没有任何 ACL”（2026-10-03 在 macOS 27 实测）。
        errno = 0
        let acl=acl_get_fd(fd);let getErrno=errno;defer{if let acl{_=acl_free(UnsafeMutableRawPointer(acl))}}
        var entry:acl_entry_t?
        errno = 0
        let noACL = acl == nil && getErrno == ENOENT
        let emptyACL = acl.map { acl_valid($0) == 0 && acl_get_entry($0,Int32(ACL_FIRST_ENTRY.rawValue),&entry) == -1 } ?? false
        t.expect(noACL || emptyACL,"不保留具名或继承授权；另需双账户验证")
        #endif
        t.finish()
    }
}
