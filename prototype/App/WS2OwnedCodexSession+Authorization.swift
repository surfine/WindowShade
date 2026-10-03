import Cocoa

/// Preserves the original native grant-consuming route, but the new local launch UI deliberately
/// uses the default deny-escalation host until native authorization and CLI tests are accepted.
extension WS2OwnedCodexSession {
    convenience init(executable:URL,workingDirectory:URL,environment:[String:String],clock:any WS2Clock,
         island:NotchLeaseHub,authentication:NotchAuthenticationController,
         currentContext:@escaping()->WS2.Context?,scopeStillValid:@escaping(WS2ApprovalReview)->Bool,
         mayOperate:@escaping()->Bool) throws {
        try self.init(executable:executable,workingDirectory:workingDirectory,environment:environment,clock:clock,
            currentContext:currentContext,mayOperate:{ mayOperate() && AuthorizationService.shared.lockState() == .unlocked },
            hostFactory:{ id,deliver,close in
                WS2CodexApprovalHost(wire:CodexWire(),connectionID:id,clock:clock,island:island,
                    authentication:authentication,currentContext:currentContext,scopeStillValid:scopeStillValid,
                    deliver:deliver,closeTransport:close)
            })
    }
}
