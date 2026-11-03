import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@main struct NativeTests {
    @MainActor static func main() async throws {
        let t=TestLog(),child=CommandLine.arguments[1],python=URL(fileURLWithPath:CommandLine.arguments[2])
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("ws2-native-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        t.begin("NATIVE01 direct child ignores TERM then owned group KILL")
        var ready=false
        let p=try WS2DuplexProcess(executable:python,arguments:["-S",child,"stubborn"],workingDirectory:root,environment:[:],mayWrite:{true})
        p.onLine={_ in ready=true};try p.start()
        let childReady=await until({ready});t.check(childReady,"fixture ready")
        p.stop();t.check(!p.leaderReaped,"transport close isn't wait/reap")
        let reaped=await until({p.leaderReaped});t.check(reaped,"native reaper")
        t.check(p.groupTerminationRequested && p.groupKillRequested,"both stop stages")
        t.check(p.termination?.wasSignalled==true && p.termination?.status==SIGKILL,"KILL status")
        p.stop();t.check(p.supervisionError==nil,"idempotent stop after reap");t.end()
        t.begin("NATIVE02 inherited descriptor descendant cannot delay direct exit")
        let marker=root.appendingPathComponent("late-marker");var lines:[String]=[]
        let q=try WS2DuplexProcess(executable:python,arguments:["-S",child,"grandchild",marker.path],workingDirectory:root,environment:[:],mayWrite:{true})
        q.onLine={lines.append(String(decoding:$0,as:UTF8.self))}
        let began=ProcessInfo.processInfo.systemUptime;try q.start()
        let exited=await until({q.termination != nil},timeout:0.7)
        FileHandle.standardError.write(Data("DIAG exited=\(exited) termination=\(String(describing:q.termination)) stopped=\(q.stopped) supervision=\(String(describing:q.supervisionError)) lines=\(lines) elapsed=\(ProcessInfo.processInfo.systemUptime-began)\n".utf8))
        t.check(exited,"direct exit before descendant's .9 second marker")
        t.check(ProcessInfo.processInfo.systemUptime-began<0.7,"bounded observed probe, not universal latency guarantee")
        let groupReaped=await until({q.leaderReaped});t.check(groupReaped,"anchor eventually reaped")
        try? await Task.sleep(nanoseconds:500_000_000)
        t.check(!FileManager.default.fileExists(atPath:marker.path),"stubborn same-group descendant did not reach late write")
        t.check(lines.count<=1,"no unbounded late stdout");t.end()
        t.begin("NATIVE03 unrelated descriptors do not reach child")
        let descriptor=open("/dev/null",O_RDONLY)
        t.check(descriptor>=3,"owned unrelated fd fixture")
        _=fcntl(descriptor,F_SETFD,0)
        var observed=""
        let z=try WS2DuplexProcess(executable:python,arguments:["-S",child,"fd",String(descriptor)],workingDirectory:root,environment:[:],mayWrite:{true})
        z.onLine={observed=String(decoding:$0,as:UTF8.self)};try z.start()
        let fdReaped=await until({z.leaderReaped});t.check(fdReaped,"reaped")
        t.check(observed=="{\"inherited\":false}","close-on-exec boundary");_=close(descriptor);t.end()
        try t.save(URL(fileURLWithPath:CommandLine.arguments[3]))
    }
}
