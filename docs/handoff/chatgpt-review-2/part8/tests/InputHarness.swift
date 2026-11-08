import Foundation
/// Explicit test substitute for GameController. Uses the production gate; never claims SDK/device evidence.
@MainActor final class TestBridge: WS2ControllerBridge {
    struct Entry { var gate=WS2DeviceInputGate();var sequence:UInt64=0 }
    let env:()->WS2ControllerEnvironment, emit:(WS2ControllerInput)->Void
    var entries:[UUID:Entry]=[:], started=false, installed=Set<UUID>()
    var devicesChanged:(([WS2ControllerDevice])->Void)?
    init(env:@escaping()->WS2ControllerEnvironment,emit:@escaping(WS2ControllerInput)->Void) {self.env=env;self.emit=emit}
    var devices:[WS2ControllerDevice] { entries.map{.init(attachment:$0.key,label:"Same label",enabled:$0.value.gate.enabled)} }
    func publish(){devicesChanged?(devices)}
    func attach(_ id:UUID){var e=Entry();e.gate.connect(id);entries[id]=e;publish()}
    func detach(_ id:UUID){_=setEnabled(false,attachment:id);entries[id]=nil;publish()}
    func start(){started=true;publish()}
    func stop(){suspendAll();started=false;entries.removeAll();publish()}
    func suspendAll(){for id in Array(entries.keys){_=setEnabled(false,attachment:id)}}
    func environmentChanged(){let e=env();if !e.unlocked || !e.sinkReady || e.gameOrUnknownInFront || e.domain == .review {suspendAll()}}
    func setEnabled(_ enabled:Bool,attachment:UUID)->Bool {
        guard var e=entries[attachment] else{return false}
        if enabled {
            guard started,env().unlocked,env().sinkReady,!env().gameOrUnknownInFront,env().domain != .review else{return false}
            _=e.gate.enable(attachment);_=e.gate.changeDomain(to:env().domain);installed.insert(attachment)
        } else { let presses=e.gate.suspend();entries[attachment]=e;installed.remove(attachment);emit(.cancel(attachment:attachment,presses:presses)) }
        entries[attachment]=e;publish();return true
    }
    func raw(_ id:UUID,_ name:String,_ pressed:Bool){
        guard var e=entries[id] else{return};e.sequence += 1
        let state=env();let result=e.gate.button(attachment:id,name:name,pressed:pressed,sequence:e.sequence,at:.init(nanoseconds:e.sequence),unlocked:state.unlocked,domain:state.domain)
        entries[id]=e;if result != .ignored {emit(.button(attachment:id,name:name,outcome:result))}
    }
    func tap(_ id:UUID,_ name:String){raw(id,name,false);raw(id,name,true);raw(id,name,false)}
}
@MainActor final class TestListSink:WS2DeviceActionSink {
    let input=WS2VisibleListInput()
    var ready:Bool{input.ready};var motionReady:Bool{false}
    func prepare(_ t:WS2SemanticInputRouter.Ticket)->Bool{input.prepare(t)}
    func cancelPrepared(context:WS2SemanticInputRouter.Context,presses:[UInt64]){input.cancel(context:context,presses:presses)}
    func execute(_ t:WS2SemanticInputRouter.Ticket)->Bool{input.execute(t)}
    func move(_ effect:GamepadMapping.Effect,context:WS2SemanticInputRouter.Context)->Bool{false}
}
@MainActor final class InputHarness {
    let sink=TestListSink(), id=UUID();var lease=UUID(),backend=UUID(), unlocked=true,frontBlocked=false
    var domain=WS2DeviceInputGate.Domain.conductor
    var chosen:[String]=[],cancelled=0;var host:WS2DeviceActionHost!,bridge:TestBridge!
    init()throws{
        try sink.input.replace([.init(id:"a",enabled:true),.init(id:"b",enabled:true),.init(id:"c",enabled:true)],selectedID:"a")
        sink.input.ready=true;sink.input.onActivate={[weak self] id in self?.chosen.append(id);return true}
        sink.input.onCancel={[weak self] in self?.cancelled += 1}
        host=WS2DeviceActionHost(sink:sink,liveContext:{[weak self] id in self?.context(id)},frontIsGameOrUnknown:{[weak self] in self?.frontBlocked ?? true},unlocked:{[weak self] in self?.unlocked ?? false},makeBridge:{env,emit in
            let b=TestBridge(env:env,emit:emit);bridge=b;return b
        })
        host.start();bridge.attach(id)
    }
    func context(_ id:UUID)->WS2SemanticInputRouter.Context? { .init(attachment:id,lease:lease,domain:domain,targetRevision:sink.input.selection.revision,backendEpoch:backend) }
    @discardableResult func enable(_ other:UUID?=nil)->Bool {let id=other ?? id;sink.input.bind(context(id));return host.enable(id)}
    func tap(_ name:String){bridge.tap(id,name)}
    var active:Bool{bridge.devices.first(where:{$0.attachment == id})?.enabled == true}
    func holdA(){bridge.raw(id,"a",false);bridge.raw(id,"a",true)}
    func releaseA(){bridge.raw(id,"a",false)}
}
