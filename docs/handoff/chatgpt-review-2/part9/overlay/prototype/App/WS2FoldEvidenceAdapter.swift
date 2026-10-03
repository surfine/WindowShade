import Cocoa
import ApplicationServices

extension AppDelegate {
    /// Actual caller is Notch.finishTuck. This does not grant timer restoration ownership.
    @discardableResult
    func shadeWithEvidence(_ win:AXUIElement,id:CGWindowID,pid:pid_t,recordedPosition:CGPoint?,
                           mayCommit:@escaping()->Bool,
                           completion:@escaping(WS2FoldEvidence.Event)->Void)->WS2FoldEvidence.Ticket? {
        guard shaded[id]==nil,!shadeOperationIDs.contains(id),windowID(of:win)==id,mayCommit(),
              AuthorizationService.shared.lockState() == .unlocked else{return nil}
        var actual:pid_t=0
        guard AXUIElementGetPid(win,&actual) == .success,actual==pid,
              let ticket=foldEvidence.begin(request:UUID(),window:id,pid:pid,at:ProcessInfo.processInfo.systemUptime) else{return nil}
        foldEvidenceCallbacks[ticket.request]=completion
        foldEvidenceMayCommit[ticket.request]=mayCommit
        DispatchQueue.main.asyncAfter(deadline:.now()+30){[weak self] in
            guard let self else{return};self.deliverFoldEvidence(self.foldEvidence.expire(ticket,at:ProcessInfo.processInfo.systemUptime))
        }
        // Late observations are bounded notifications. Journal/recovery state is never cleared here.
        DispatchQueue.main.asyncAfter(deadline:.now()+60){[weak self] in
            self?.foldEvidence.forget(ticket);self?.foldEvidenceCallbacks[ticket.request]=nil;self?.foldEvidenceMayCommit[ticket.request]=nil
        }
        shade(win,id,options:nil,bypassDuo:true,trustElement:true,recordedPosition:recordedPosition,evidence:ticket)
        return ticket
    }
    func deliverFoldEvidence(_ event:WS2FoldEvidence.Event?){
        guard let event else{return}
        let callback=foldEvidenceCallbacks[event.ticket.request]
        if !foldEvidence.contains(event.ticket){foldEvidenceCallbacks[event.ticket.request]=nil;foldEvidenceMayCommit[event.ticket.request]=nil}
        DispatchQueue.main.async { callback?(event) }
    }
    func mayCommitObservedFold(_ ticket:WS2FoldEvidence.Ticket)->Bool {
        foldEvidence.mayStart(ticket,at:ProcessInfo.processInfo.systemUptime) &&
        foldEvidenceMayCommit[ticket.request]?() == true && AuthorizationService.shared.lockState() == .unlocked
    }
    func finishFoldEvidence(_ ticket:WS2FoldEvidence.Ticket?,success:Bool){
        guard let ticket else{return}
        if success,let state=shaded[ticket.window],state.pid==ticket.pid,
           foldEvidence.ticket(window:ticket.window,transaction:state.foldTransactionID)==ticket {
            publishFoldObservation(id:ticket.window,state:state)
        } else {deliverFoldEvidence(foldEvidence.failed(ticket))}
    }
    func publishFoldObservation(id:CGWindowID,state:ShadeState){
        guard shaded[id]?.foldTransactionID==state.foldTransactionID,
              let ticket=foldEvidence.ticket(window:id,transaction:state.foldTransactionID) else{return}
        let result=strictFoldObservation(id:id,state:state)
        deliverFoldEvidence(foldEvidence.observe(ticket,transaction:state.foldTransactionID,observation:result))
        // Observation only: these retries cannot hide, minimize, restore or modify the recovery journal.
        let transactionID = state.foldTransactionID // Do not retain ShadeState's image/overlay in retry closures.
        for delay in [0.15,0.6,1.2] {
            DispatchQueue.main.asyncAfter(deadline:.now()+delay){[weak self] in
                guard let self,self.foldEvidence.contains(ticket),
                      let live=self.shaded[id],live.foldTransactionID==transactionID else{return}
                self.deliverFoldEvidence(self.foldEvidence.observe(ticket,transaction:transactionID,
                                      observation:self.strictFoldObservation(id:id,state:live)))
            }
        }
    }
    /// Native resizing/intentional close never become timer restoration ownership.
    func strictFoldObservation(id: CGWindowID, state: ShadeState) -> WS2FoldEvidence.Observation {
        guard shaded[id]?.foldTransactionID == state.foldTransactionID,
              state.hide != .none, state.hide != .ownWindowOrderedOut, state.hide != .quickLookClosed else { return .unknown }
        switch observeFoldHide(state.hide, win: state.element, pid: state.pid, id: id) {
        case .hidden: return .verifiedHidden
        case .visible: return .stillVisible
        case .unknown: return .unknown
        }
    }
    func cancelFoldEvidence(id:CGWindowID,transaction:UUID){
        guard let t=foldEvidence.ticket(window:id,transaction:transaction) else{return}
        deliverFoldEvidence(foldEvidence.failed(t))
        foldEvidence.forget(t);foldEvidenceCallbacks[t.request]=nil;foldEvidenceMayCommit[t.request]=nil
    }
}
