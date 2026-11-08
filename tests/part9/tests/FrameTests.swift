import Foundation
final class Frame { let number: Int; init(_ number:Int){self.number=number} }
actor FrameOwner {
    var clock=0.0
    func exercise() async -> Bool {
        let frame=Frame(7)
        let read=await EffectFrameAwaiter<Frame>.first(timeout:1,now:{self.clock},isCurrent:{true},latest:{frame},pause:{self.clock+=0.1})
        return read === frame
    }
}
@main enum FrameTests {
 @MainActor static func main() async throws {
    var cases:[[String:Any]]=[];var failures=0
    func check(_ name:String,_ passed:Bool){cases.append(["id":name,"passed":passed]);if !passed{failures+=1};print(passed ? "PASS":"FAIL",name)}
    let frame=Frame(1)
    let ready=await EffectFrameAwaiter<Frame>.first(timeout:1,now:{0},isCurrent:{true},latest:{frame},pause:{})
    check("FRAME01-main-actor-nonsendable-value",ready === frame)
    check("FRAME02-independent-actor",await FrameOwner().exercise())
    let unisolated=await Task.detached {let box=Frame(3);let value=await EffectFrameAwaiter<Frame>.first(timeout:1,now:{0},isCurrent:{true},latest:{box},pause:{});return value === box}.value
    check("FRAME03-unisolated-caller",unisolated)
    var active=true
    let replaced=await EffectFrameAwaiter<Frame>.first(timeout:1,now:{0},isCurrent:{active},latest:{active=false;return frame},pause:{})
    check("FRAME04-replaced-inside-getter",replaced == nil)
    var now=0.0
    let expired=await EffectFrameAwaiter<Frame>.first(timeout:1,now:{now},isCurrent:{true},latest:{now=1;return frame},pause:{})
    check("FRAME05-deadline-inside-getter",expired == nil)
    now=0;active=true;var reads=0
    let cancelled=await EffectFrameAwaiter<Frame>.first(timeout:1,now:{now},isCurrent:{active},latest:{reads+=1;return nil},pause:{now+=0.1;active=false})
    check("FRAME06-revoked-during-pause",cancelled == nil && reads==1)
    for (label,timeout) in [("zero",0.0),("negative",-1), ("nan",Double.nan),("infinite",.infinity)] {
        var read=false
        let value=await EffectFrameAwaiter<Frame>.first(timeout:timeout,now:{0},isCurrent:{true},latest:{read=true;return frame},pause:{})
        check("FRAME07-timeout-"+label,value == nil && !read)
    }
    let badClock=await EffectFrameAwaiter<Frame>.first(timeout:1,now:{.nan},isCurrent:{true},latest:{frame},pause:{})
    check("FRAME08-nonfinite-clock",badClock == nil)
    var sequence=[0.0,-1.0]
    let reversed=await EffectFrameAwaiter<Frame>.first(timeout:1,now:{sequence.removeFirst()},isCurrent:{true},latest:{frame},pause:{})
    check("FRAME09-clock-goes-backward",reversed == nil)
    let overflow=await EffectFrameAwaiter<Frame>.first(timeout:Double.greatestFiniteMagnitude,now:{Double.greatestFiniteMagnitude},isCurrent:{true},latest:{frame},pause:{})
    check("FRAME10-deadline-overflow",overflow == nil)
    let noProgress=await EffectFrameAwaiter<Frame>.first(timeout:1,now:{Double.greatestFiniteMagnitude},isCurrent:{true},latest:{frame},pause:{})
    check("FRAME11-deadline-does-not-advance",noProgress == nil)
    var taskRead=false
    let task=Task { @MainActor in let result=await EffectFrameAwaiter<Frame>.first(timeout:1,now:{0},isCurrent:{true},latest:{taskRead=true;return frame},pause:{});return result == nil }
    task.cancel();let value=await task.value
    check("FRAME12-task-cancelled",value && !taskRead)
    try JSONSerialization.data(withJSONObject:["suite":"FrameAwaiter","scenarios":cases.count,"assertions":cases.count,"failures":failures,"cases":cases],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
    print("SCENARIOS \(cases.count) ASSERTIONS \(cases.count) FAILURES \(failures)")
    if failures>0 {exit(1)}
 }
}
