import Foundation
import CryptoKit

struct RemoteDiscoveryProfile {
    enum Mode: String { case companion, atvCore = "atv-core" }
    struct Service { let type: String; let txt: [String: String] }
    let serverIdentifier: String
    let deviceID: String
    let name: String
    let mode: Mode
    var uniqueID: String { serverIdentifier.replacingOccurrences(of: "-", with: "").uppercased() }
    var model: String { mode == .atvCore ? "AppleTV14,1" : "AppleTV6,2" }
    init(mode: Mode, name: String = "WindowShade Remote Probe", serverIdentifier: String = UUID().uuidString,
         deviceID: String = "02:" + (0..<5).map { _ in String(format: "%02X", UInt8.random(in: 0...255)) }.joined(separator: ":")) {
        self.mode = mode; self.name = name; self.serverIdentifier = serverIdentifier; self.deviceID = deviceID
    }
    private func tag(_ label: String, bytes: Int, uppercase: Bool = true) -> String {
        let hex = SHA256.hash(data: Data((label + serverIdentifier).utf8)).prefix(bytes).map { String(format: "%02x", $0) }.joined()
        return uppercase ? hex.uppercased() : hex
    }
    var services: [Service] {
        if mode == .companion {
            let randomTag = tag("legacy:", bytes: 6, uppercase: false)
            return [Service(type: "_companion-link._tcp", txt: [
                "rpMd": model, "rpVr": "195.2", "rpFl": "0x36782", "rpMac": "1", "rpHN": randomTag,
                "rpHA": randomTag, "rpAD": randomTag, "rpHI": randomTag, "rpBA": deviceID, "rpMRtID": serverIdentifier])]
        }
        // Exact field names/constants and domain-separated derivation from fixed atv-core server.rs.
        // Its advertised pk is a discovery hash, not our signing key or proof of authentication.
        return [
            Service(type: "_mediaremotetv._tcp", txt: ["Name": name, "UniqueIdentifier": uniqueID,
                "SystemBuildVersion": "22K160", "LocalAirPlayReceiverPairingIdentity": tag("airplay-identity:", bytes: 8),
                "ModelName": "Apple TV", "AllowPairing": "YES"]),
            Service(type: "_companion-link._tcp", txt: ["rpMac": "1", "rpHA": deviceID.replacingOccurrences(of: ":", with: "").uppercased(),
                "rpHN": tag("rpHN:", bytes: 6), "rpVr": "715.2", "rpMd": model, "rpFl": "0x36782",
                "rpAD": tag("rpAD:", bytes: 6), "rpHI": tag("rpHI:", bytes: 6), "rpBA": deviceID]),
            Service(type: "_airplay._tcp", txt: ["deviceid": deviceID, "features": "0x5A7FFFF7,0x1E", "flags": "0x44",
                "model": model, "srcvers": "715.2", "vv": "2", "pi": serverIdentifier,
                "pk": tag("pk:", bytes: 16, uppercase: false), "name": name])
        ]
    }
}

/// The production listener owner and offline cancellation probes use this exact cleanup boundary.
@MainActor final class RemoteServiceLifetime {
    private var cleanups: [() -> Void] = []
    private(set) var closed = false
    var count: Int { cleanups.count }
    func own(_ cleanup: @escaping () -> Void) {
        guard !closed else { cleanup(); return }; cleanups.append(cleanup)
    }
    func close() {
        guard !closed else { return }; closed = true
        let callbacks = cleanups; cleanups.removeAll()
        for callback in callbacks { callback() }
    }
}
