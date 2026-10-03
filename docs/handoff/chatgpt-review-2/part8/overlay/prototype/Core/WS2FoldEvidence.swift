import Foundation

/// Transient completion evidence for a specific fold invocation, not a restoration or authorization receipt.
/// Existing ShadeState and recovery journal remain authoritative. Time is local monotonic seconds.
struct WS2FoldEvidence: Sendable {
    struct Ticket: Equatable, Sendable { let request:UUID;let window:UInt32;let pid:Int32 }
    enum Observation:String,Sendable,Codable { case verifiedHidden, stillVisible, unknown, notStarted }
    struct Event:Equatable,Sendable { let ticket:Ticket;let transaction:UUID?;let observation:Observation;let late:Bool }
    private struct Entry:Sendable { let ticket:Ticket;let issuedAt:Double;let deadline:Double;var attempted=false;var transaction:UUID?;var last:Observation? }
    private var entries:[UUID:Entry]=[:]
    var count:Int{entries.count}
    func contains(_ ticket:Ticket)->Bool{entries[ticket.request]?.ticket == ticket}
    mutating func begin(request:UUID,window:UInt32,pid:Int32,at now:Double,timeout:Double=30)->Ticket?{
        guard now.isFinite,now>=0,timeout.isFinite,timeout>0,timeout<=30,window>0,pid>0,
              (now+timeout).isFinite,now+timeout>now,
              entries.count<64,entries[request]==nil,!entries.values.contains(where:{$0.ticket.window==window}) else{return nil}
        let t=Ticket(request:request,window:window,pid:pid);entries[request]=Entry(ticket:t,issuedAt:now,deadline:now+timeout);return t
    }
    func mayStart(_ t:Ticket,at now:Double)->Bool {
        guard let e=entries[t.request],e.ticket==t,now.isFinite,now>=e.issuedAt,now<e.deadline else{return false}
        return e.last==nil
    }
    mutating func markMutation(_ t:Ticket,at now:Double)->Bool{
        guard mayStart(t,at:now) else{return false};entries[t.request]?.attempted=true;return true
    }
    mutating func bind(_ t:Ticket,transaction:UUID)->Bool{
        guard let e=entries[t.request],e.ticket==t,e.attempted,e.transaction==nil || e.transaction==transaction else{return false}
        entries[t.request]?.transaction=transaction;return true
    }
    func ticket(window:UInt32,transaction:UUID)->Ticket?{
        entries.values.first(where:{$0.ticket.window==window && $0.transaction==transaction})?.ticket
    }
    mutating func observe(_ t:Ticket,transaction:UUID,observation:Observation)->Event?{
        guard let e=entries[t.request],e.ticket==t,e.attempted,e.transaction==transaction,
              observation != .notStarted else{return nil}
        return emit(t,observation:observation)
    }
    mutating func failed(_ t:Ticket)->Event?{
        guard let e=entries[t.request],e.ticket==t else{return nil}
        return emit(t,observation:e.attempted ? .unknown:.notStarted)
    }
    mutating func expire(_ t:Ticket,at now:Double)->Event?{
        guard let e=entries[t.request],e.ticket==t,now.isFinite,now>=e.deadline else{return nil}
        // A prior concrete observation must not be downgraded by an old timer.
        guard e.last==nil else{return nil}
        return emit(t,observation:e.attempted ? .unknown:.notStarted)
    }
    mutating func forget(_ t:Ticket){if contains(t){entries[t.request]=nil}}
    private mutating func emit(_ t:Ticket,observation:Observation)->Event?{
        guard var e=entries[t.request],e.ticket==t else{return nil}
        guard e.last != observation,!(e.last != nil && observation == .unknown) else{return nil}
        let result=Event(ticket:t,transaction:e.transaction,observation:observation,late:e.last != nil)
        e.last=observation
        if observation == .verifiedHidden || observation == .notStarted {entries[t.request]=nil}
        else {entries[t.request]=e}
        return result
    }
}
