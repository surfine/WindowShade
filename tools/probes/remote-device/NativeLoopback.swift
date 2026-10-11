import Foundation
import Network

/// Explicit local test entry point. No Bonjour, wildcard bind, discovery or hardware session.
@MainActor enum RemoteNativeLoopback {
    static func run(configuration: RemoteProbeConfiguration = .default) throws {
        let owner = try RemoteOwner(configuration: configuration)
        owner.deadline = owner.clock.now().seconds + 30
        _ = try owner.admission.openByLocalUser(makePIN: { "3939" })
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        defer {
            listener.stateUpdateHandler = nil
            listener.newConnectionHandler = nil
            listener.cancel()
            owner.stop()
        }
        listener.newConnectionHandler = { [weak owner] connection in MainActor.assumeIsolated {
            guard let owner, owner.running else { connection.cancel(); return }
            owner.incoming += 1
            guard owner.accepted == 0 else { owner.denied += 1; connection.cancel(); return }
            owner.accepted = 1
            let entry = RemoteConnection(owner: owner, connection: connection, connectionIndex: 1)
            owner.connections[entry.id] = entry
            entry.start()
        } }
        listener.stateUpdateHandler = { [weak owner, weak listener] state in MainActor.assumeIsolated {
            guard let owner, owner.running else { return }
            switch state {
            case .ready: report("loopback-ready", ["port": listener?.port?.rawValue ?? 0])
            case .failed: report("loopback-failed"); owner.stop()
            default: break
            }
        } }
        listener.start(queue: .main)
        while owner.running, owner.clock.now().seconds < owner.deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            if owner.accepted > 0, owner.connections.isEmpty { break }
        }
    }
}
