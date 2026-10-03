import Foundation

@main struct CoreTests {
    @MainActor static func main() throws {
        let t=TestLog()
        func valid(_ text:String)->Bool { (try? WS2StrictJSON.validate(Data(text.utf8))) != nil }
        let cases:[(String,String,Bool)]=[
            ("JSON01 empty object","{}",true),("JSON02 nested","{\"id\":1,\"a\":{\"id\":2}}",true),
            ("JSON03 duplicate","{\"id\":1,\"id\":2}",false),("JSON04 escaped duplicate","{\"id\":1,\"\\u0069d\":2}",false),
            ("JSON05 nested duplicate","{\"x\":{\"a\":1,\"a\":2}}",false),("JSON06 surrogate pair","{\"x\":\"\\ud83d\\ude00\"}",true),
            ("JSON07 lone high surrogate","[\"\\ud800\"]",false),("JSON08 lone low surrogate","[\"\\udc00\"]",false),
            ("JSON09 leading zero","[01]",false),("JSON10 fraction exponent","[-1.25e+2,0]",true),
            ("JSON11 trailing data","{}{}",false),("JSON12 trailing comma","{\"a\":1,}",false),
            ("JSON13 invalid escape","\"\\x41\"",false),("JSON14 raw control","\"a\nb\"",false),
            ("JSON15 unicode","[\"中文\",true,false,null]",true),("JSON16 incomplete exponent","1e+",false),
            ("JSON17 deep",""+String(repeating:"[",count:34)+"0"+String(repeating:"]",count:34),false),
            ("JSON18 whitespace"," \t{\"a\":[]}\r\n",true)]
        for (name,value,expected) in cases { t.begin(name);t.check(valid(value)==expected,"grammar result");t.end() }
        t.begin("JSON19 size and node budgets")
        t.check((try? WS2StrictJSON.validate(Data("[]".utf8),maximumBytes:1))==nil,"size")
        t.check((try? WS2StrictJSON.validate(Data("[1,2]".utf8),maximumNodes:2))==nil,"nodes")
        t.check((try? WS2StrictJSON.validate(Data([34,0xFF,34])))==nil,"UTF8");t.end()
        t.begin("URL01 browser scheme and exact host")
        for value in ["file:///tmp/a","https://auth.openai.com.evil/","https://evil@auth.openai.com/a","http://auth.openai.com/","https://chatgpt.com:444/a","https://chatgpt.com/a#fragment"] {
            t.check(WS2OwnedLaunchController.browserLoginURL(value)==nil,"reject \(value)")
        }
        t.check(WS2OwnedLaunchController.browserLoginURL("https://auth.openai.com/authorize?state=x") != nil,"auth host")
        t.check(WS2OwnedLaunchController.browserLoginURL("https://chatgpt.com/a") != nil,"chatgpt host");t.end()
        t.begin("WIRE01 duplicate keys close before RPC interpretation")
        var wire=CodexWire();try wire.initialize(now:.zero);_=wire.drain()
        t.check((try? wire.ingest(Data("{\"id\":1,\"\\u0069d\":2,\"result\":{}}\n".utf8),now:.zero))==nil,"wire rejects duplicate")
        t.check(wire.state == .closed,"closed");t.end()
        t.begin("QUIT01 both owners must settle")
        var quit=WS2QuitBarrier();let token=quit.begin(updaterReady:false,childrenReady:false)!
        t.check(quit.update(token,childrenReady:true)==nil,"child alone cannot release updater")
        t.check(quit.update(token,updaterReply:true)==true,"both ready")
        t.check(quit.update(token,updaterReply:true)==nil,"one reply only");t.end()
        t.begin("QUIT02 updater alone cannot release child")
        let next=quit.begin(updaterReady:true,childrenReady:false)!
        t.check(quit.update(token,childrenReady:true)==nil,"stale generation")
        t.check(quit.update(next,failed:true)==false,"timeout cancels instead of false cleanup")
        t.check(quit.update(next,childrenReady:true)==nil,"late cleanup after cancel ignored");t.end()
        t.begin("WIRE02 ambiguous result/error envelope")
        var ambiguous=CodexWire();try ambiguous.initialize(now:.zero);_=ambiguous.drain()
        t.check((try? ambiguous.ingest(Data("{\"id\":1,\"result\":{},\"error\":{}}\n".utf8),now:.zero))==nil,"not two meanings")
        t.check(ambiguous.state == .closed,"closed");t.end()
        t.begin("QUIT03 veto and double begin")
        let veto=quit.begin(updaterReady:false,childrenReady:true)!
        t.check(quit.begin(updaterReady:true,childrenReady:true)==nil,"single owner")
        t.check(quit.update(veto,updaterReply:false)==false,"updater veto retained")
        t.check(quit.update(veto,updaterReply:true)==nil,"late reply cannot reverse veto");t.end()
        t.begin("PROFILE01 creates private state without overwriting changes")
        let fm=FileManager.default,root=fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("ws2-profile-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer { try? fm.removeItem(at:root) }
        let project=root.appendingPathComponent("project"),state=root.appendingPathComponent("state"),exe=root.appendingPathComponent("fixture")
        try fm.createDirectory(at:project,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try Data("test fixture only".utf8).write(to:exe);try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:exe.path)
        let profile=try WS2LocalLaunchProfile.prepare(projectURL:project,projectID:UUID(),executableURL:exe,root:state)
        t.check(profile.environment["HOME"]==state.appendingPathComponent("home").path,"separate home")
        t.check(profile.environment["CODEX_HOME"]==state.appendingPathComponent("codex").path,"separate credentials root")
        t.check(profile.environment["OPENAI_API_KEY"]==nil,"does not copy ambient keys")
        let config=state.appendingPathComponent("codex/config.toml")
        try Data("external edit".utf8).write(to:config)
        t.check((try? profile.revalidate())==nil,"external change rejected")
        t.check((try? WS2LocalLaunchProfile.prepare(projectURL:project,projectID:UUID(),executableURL:exe,root:state))==nil,"no overwrite on next launch")
        let unchanged=try String(contentsOf:config,encoding:.utf8);t.check(unchanged=="external edit","original edit preserved");t.end()
        t.begin("PROFILE02 project configuration and linked state reject")
        let local=project.appendingPathComponent(".codex")
        try fm.createSymbolicLink(at:local,withDestinationURL:root.appendingPathComponent("missing"))
        t.check((try? WS2LocalLaunchProfile.prepare(projectURL:project,projectID:UUID(),executableURL:exe,root:root.appendingPathComponent("state2")))==nil,"dangling project config rejected")
        try fm.removeItem(at:local)
        let linked=root.appendingPathComponent("linked");try fm.createSymbolicLink(at:linked,withDestinationURL:state)
        t.check((try? WS2LocalLaunchProfile.prepare(projectURL:project,projectID:UUID(),executableURL:exe,root:linked))==nil,"root symlink rejected")
        t.check(!WS2LocalLaunchProfile.admitsEffectiveConfig(.object([:])),"missing projection not treated as defaults");t.end()
        try t.save(URL(fileURLWithPath:CommandLine.arguments[1]))
    }
}
