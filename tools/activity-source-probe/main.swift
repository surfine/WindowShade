import Cocoa
_ = NSApplication.shared
MainActor.assumeIsolated {
    UserDefaults.standard.setVolatileDomain([NotchActivitySources.musicKey: false], forName: UserDefaults.argumentDomain)
    let sources = NotchActivitySources()
    var deliveries = 0
    let began = ProcessInfo.processInfo.systemUptime
    sources.onSnapshot = { items in
        deliveries += 1
        precondition(deliveries == 1, "Duplicate or late delivery after stop")
        print("SOURCE CHECK: native snapshot received; kinds=\(items.map { $0.kind.rawValue }); elapsed=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime - began))s; music permissions not requested; audio not captured")
        fflush(nil)
        sources.stop()
    }
    sources.start(); sources.stop(); sources.start()
    let deadline = Date().addingTimeInterval(6)
    while deliveries == 0 && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    precondition(deliveries == 1, "Native snapshot timed out")
    sources.stop()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    precondition(deliveries == 1, "Stopped source delivered late")
    print("PASS source stop/restart and stopped delivery")
    fflush(nil)
}
