// Experiment probe: passive BLE scan, decode Apple (0x004C) Continuity TLVs, esp. Nearby Info (0x10).
// Read-only. No connections, no pairing. Identifiers are redacted to a salted 2-hex-char token;
// device names are never printed. Usage: ContinuityProbe [--seconds N] [--self-test]
import Foundation
import CoreBluetooth
import CryptoKit

struct NearbyInfo: Equatable {
    var statusFlags: UInt8      // high nibble of byte0
    var actionCode: UInt8       // low nibble of byte0
    var dataFlags: UInt8?       // byte1
    var authTagPresent: Bool { (dataFlags ?? 0) & 0x10 != 0 }
    var wifiOn: Bool { (dataFlags ?? 0) & 0x04 != 0 }
    var primaryDevice: Bool { statusFlags & 0x1 != 0 }
    var airdropReceiving: Bool { statusFlags & 0x4 != 0 }
    static let actionNames: [UInt8: String] = [
        0x00: "unknown", 0x01: "reporting_disabled", 0x03: "idle(screen_off_or_locked)",
        0x05: "audio_playing_locked", 0x07: "active_screen_on", 0x09: "screen_on_video",
        0x0A: "watch_on_wrist_unlocked", 0x0B: "recent_interaction", 0x0D: "driving", 0x0E: "call"]
    var actionName: String { Self.actionNames[actionCode] ?? "other_\(actionCode)" }
}

/// Parse the TLV list inside manufacturer data (after the 2-byte company id).
func parseApple(_ mfg: Data) -> [(type: UInt8, value: Data)]? {
    guard mfg.count >= 4, mfg[mfg.startIndex] == 0x4C, mfg[mfg.startIndex + 1] == 0x00 else { return nil }
    var i = mfg.startIndex + 2
    var out: [(UInt8, Data)] = []
    while i + 1 < mfg.endIndex {
        let t = mfg[i]; let l = Int(mfg[i + 1]); i += 2
        guard i + l <= mfg.endIndex else { break }
        out.append((t, mfg.subdata(in: i..<(i + l)))); i += l
    }
    return out
}
func decodeNearbyInfo(_ v: Data) -> NearbyInfo? {
    guard v.count >= 1 else { return nil }
    let b0 = v[v.startIndex]
    return NearbyInfo(statusFlags: b0 >> 4, actionCode: b0 & 0x0F, dataFlags: v.count >= 2 ? v[v.startIndex + 1] : nil)
}
let typeNames: [UInt8: String] = [0x05: "airdrop", 0x07: "airpods", 0x09: "airplay_target", 0x0A: "airplay_src", 0x0B: "magic_switch",
    0x0C: "handoff", 0x0D: "tethering_target", 0x0E: "tethering_src", 0x0F: "nearby_action", 0x10: "nearby_info", 0x12: "findmy", 0x06: "homekit"]

func selfTest() -> Int32 {
    // synthetic: 0x4C00 | 10 05 | 0x73 0x1c a1 b2 c3  -> status 7, action 3 (idle)
    let d = Data([0x4C, 0x00, 0x10, 0x05, 0x73, 0x1C, 0xA1, 0xB2, 0xC3])
    guard let tlv = parseApple(d), tlv.count == 1, tlv[0].type == 0x10, let n = decodeNearbyInfo(tlv[0].value) else { print("FAIL parse"); return 1 }
    guard n.actionCode == 3, n.statusFlags == 7, n.authTagPresent, n.wifiOn else { print("FAIL decode \(n)"); return 1 }
    let e = Data([0x4C, 0x00, 0x10, 0x05, 0x17, 0x04, 0, 0, 0, 0x0F, 0x03, 0x01, 0x02, 0x03])
    guard let t2 = parseApple(e), t2.count == 2, decodeNearbyInfo(t2[0].value)?.actionCode == 7 else { print("FAIL decode2"); return 1 }
    print("self-test ok"); return 0
}

final class Scanner: NSObject, CBCentralManagerDelegate {
    var cm: CBCentralManager!
    let salt = UUID().uuidString
    let t0 = Date()
    struct Seen { var first = Date(); var last = Date(); var n = 0; var types = Set<UInt8>(); var lastNI: NearbyInfo?; var actions: [UInt8: Int] = [:]; var rssi: [Int] = [] ; var nameless = true }
    var seen: [String: Seen] = [:]
    var totalAdv = 0, appleAdv = 0, appleNI = 0, otherMfg = 0, noMfg = 0
    var otherCompanies: [UInt16: Int] = [:]
    func tok(_ id: UUID) -> String { SHA256.hash(data: Data((salt + id.uuidString).utf8)).prefix(1).map { String(format: "%02x", $0) }.joined() }
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        print("state=\(c.state.rawValue) auth=\(CBCentralManager.authorization.rawValue)  (5=poweredOn; auth 3=allowed)")
        if c.state == .poweredOn { c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]) }
        else if c.state == .unauthorized || c.state == .unsupported { print("BLOCKED: Bluetooth not authorized for this process"); fflush(stdout); exit(3) }
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        totalAdv += 1
        let id = tok(p.identifier)
        var s = seen[id] ?? Seen(); s.n += 1; s.last = Date(); s.rssi.append(rssi.intValue)
        guard let m = ad[CBAdvertisementDataManufacturerDataKey] as? Data, m.count >= 2 else { noMfg += 1; seen[id] = s; return }
        if let tlv = parseApple(m) {
            appleAdv += 1
            for (t, v) in tlv {
                s.types.insert(t)
                if t == 0x10, let ni = decodeNearbyInfo(v) {
                    appleNI += 1; s.actions[ni.actionCode, default: 0] += 1
                    if ni != s.lastNI {
                        let ts = String(format: "%5.1f", Date().timeIntervalSince(t0))
                        print("t=\(ts)s id=\(id) NearbyInfo action=0x\(String(ni.actionCode, radix: 16)) (\(ni.actionName)) status=0x\(String(ni.statusFlags, radix: 16)) primary=\(ni.primaryDevice) data=0x\(String(ni.dataFlags ?? 0, radix: 16)) authTag=\(ni.authTagPresent) rssi=\(rssi)")
                        s.lastNI = ni
                    }
                }
            }
        } else { otherMfg += 1; let cid = UInt16(m[m.startIndex]) | UInt16(m[m.startIndex + 1]) << 8; otherCompanies[cid, default: 0] += 1 }
        seen[id] = s; fflush(stdout)
    }
    func summary() {
        print("---- summary ----")
        print("adv_total=\(totalAdv) advertisers=\(seen.count) apple_0x004c_adv=\(appleAdv) nearby_info_msgs=\(appleNI) other_company_mfg=\(otherMfg) no_mfg_data=\(noMfg)")
        print("other_company_ids(top)=\(otherCompanies.sorted { $0.value > $1.value }.prefix(5).map { String(format: "0x%04x:%d", $0.key, $0.value) })")
        for (id, s) in seen.sorted(by: { $0.value.n > $1.value.n }).prefix(25) where !s.types.isEmpty {
            let r = s.rssi.sorted(); let med = r[r.count / 2]
            print("id=\(id) adv=\(s.n) span=\(Int(s.last.timeIntervalSince(s.first)))s rssi_med=\(med) tlv=\(s.types.sorted().map { typeNames[$0] ?? String(format: "0x%02x", $0) }) actions=\(s.actions.map { "0x\(String($0.key, radix: 16)):\($0.value)" })")
        }
    }
}

let args = CommandLine.arguments
if args.contains("--self-test") { exit(selfTest()) }
let secs = args.firstIndex(of: "--seconds").flatMap { Int(args[$0 + 1]) } ?? 60
print("authorization_at_start=\(CBCentralManager.authorization.rawValue) (0=notDetermined 1=restricted 2=denied 3=allowed)"); fflush(stdout)
let sc = Scanner()
sc.cm = CBCentralManager(delegate: sc, queue: .main)
DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(secs)) { sc.cm.stopScan(); sc.summary(); exit(0) }
RunLoop.main.run()
