import Foundation

/// Join the updater's existing termination decision with our owned-child cleanup. This never
/// turns a timeout or a missing reap receipt into permission to quit. It returns at most once.
struct WS2QuitBarrier: Sendable {
    struct Token:Hashable,Sendable { let value:UUID }
    private(set) var token:Token?
    private var updater=false,children=false
    mutating func begin(updaterReady:Bool,childrenReady:Bool) -> Token? {
        guard token==nil else { return nil }
        let next=Token(value:UUID());token=next;updater=updaterReady;children=childrenReady;return next
    }
    mutating func update(_ expected:Token,updaterReply:Bool?=nil,childrenReady:Bool=false,failed:Bool=false) -> Bool? {
        guard token==expected else { return nil }
        if failed || updaterReply==false { token=nil;return false }
        if updaterReply==true { updater=true };if childrenReady { children=true }
        if updater && children { token=nil;return true }
        return nil
    }
}
