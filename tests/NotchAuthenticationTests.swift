import Cocoa
import LocalAuthentication

@main enum NotchAuthenticationTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        NotchAuthenticationController.checkCancelledAndStaleTransactions()
        print("PASS authentication cancellation exactly once, stale success rejection, host removal; no biometric evaluation")
    }
}

// This test is appended to the production file by the AppKit harness, so no test hooks ship.
extension NotchAuthenticationController {
    @MainActor fileprivate static func checkCancelledAndStaleTransactions() {
        let application = AppDelegate()
        let owner = NotchController(owner: application)
        let controller = NotchAuthenticationController(owner: owner)
        let screen = NSScreen.main!
        let host = NotchPanel(notch: NSRect(x: screen.frame.midX - 95, y: screen.frame.maxY - 24, width: 190, height: 24), virtual: true)
        var replies = 0
        func stage(_ transaction: Int) -> LAContext {
            let context = LAContext()
            controller.epoch = transaction; controller.context = context; controller.panel = host
            controller.evaluating = true
            controller.deadline = ProcessInfo.processInfo.systemUptime + 30
            controller.presentation = NotchAuthenticationView(context: context, reason: "取消边界检查（测试数据）")
            controller.completion = { passed in precondition(!passed); replies += 1 }
            return context
        }
        _ = stage(1)
        controller.cancel(animated: false, restoreFocus: false)
        controller.cancel(animated: false, restoreFocus: false)
        controller.finish(true, transaction: 1)
        precondition(replies == 1 && controller.context == nil && !controller.isPresenting,
                     "Cancelled transaction reports failure once and never accepts late success")
        let newer = stage(3)
        let view = controller.presentation
        controller.finish(true, transaction: 1)
        precondition(controller.context === newer && controller.presentation === view && replies == 1,
                     "Old callback can't authorize or clear the new request")
        controller.reconcile(panels: [])
        controller.finish(true, transaction: 3)
        precondition(replies == 2 && controller.context == nil && !controller.isPresenting,
                     "Removing the display cancels and invalidates pending authentication")
        _ = stage(5)
        let expired = controller.presentation!
        host.setAuthentication(expired, animated: false)
        controller.deadline = ProcessInfo.processInfo.systemUptime - 1
        controller.finish(true, transaction: 5)
        precondition(replies == 3 && !expired.isConfirmed && !controller.isPresenting,
                     "Expired success is rejected even if the timeout task has not run yet")
        host.orderOut(nil)
        withExtendedLifetime((application, owner)) {}
    }
}
