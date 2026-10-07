// Isolated opt-in probe. Never logs names, identifiers, characteristic bytes or keys.
// Encrypted access is transport evidence only, never an unlock identity proof.
import Foundation
import CoreBluetooth
import CryptoKit

final class Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, CBPeripheralManagerDelegate {
    private var central: CBCentralManager?
    private var accessory: CBPeripheralManager?
    private var retained: CBPeripheral?
    private let started = ProcessInfo.processInfo.systemUptime
    private let salt = UUID().uuidString
    private var attempted = false
    private var completed = false
    private var active = false
    private var epoch = UUID()
    private var selection: [String: [String: String]] = [:]
    private var seen: Set<UUID> = []
    private let serviceID = CBUUID(string: "7226818A-90D4-4755-AB5D-DC12AFE4C201")
    func option(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    func token(_ id: UUID) -> String {
        SHA256.hash(data: Data((salt + id.uuidString).utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
    func log(_ event: String, _ value: String = "") {
        print("\(Int(ProcessInfo.processInfo.systemUptime - started)),\(event),\(value),transport_only")
        fflush(stdout)
    }
    func start() {
        print("elapsed_s,event,value,qualification")
        guard let role = option("--role"), ["central", "peripheral"].contains(role) else {
            log("usage", "--role central|peripheral [--target UUID --service UUID --characteristic UUID --operation read|notify|rssi]")
            exit(64)
        }
        active = true
        if role == "central" { central = CBCentralManager(delegate: self, queue: .main) }
        else { accessory = CBPeripheralManager(delegate: self, queue: .main) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [self] in
            active = false; epoch = UUID()
            central?.stopScan()
            if let p = retained { central?.cancelPeripheralConnection(p) }
            accessory?.stopAdvertising(); accessory?.removeAllServices()
            if let path = option("--selection-file") {
                do {
                    let bytes = try JSONSerialization.data(withJSONObject: selection, options: [.prettyPrinted, .sortedKeys])
                    let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
                    guard fd >= 0 else { log("selection_export_refused"); exit(2) }
                    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                    try handle.write(contentsOf: bytes); try handle.close()
                    log("selection_exported_private_file", String(selection.count))
                } catch { log("selection_export_failed"); exit(2) }
            }
            log("finished", completed ? "transport_observed_identity_unproven" : "inconclusive")
            exit(completed ? 0 : 2)
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("central_state", String(central.state.rawValue))
        guard active, central.state == .poweredOn else { retained = nil; epoch = UUID(); return }
        if option("--operation") != "passive-rssi", !attempted, let raw = option("--target"), let id = UUID(uuidString: raw),
           let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first {
            attempted = true; retained = peripheral; peripheral.delegate = self
            log("known_candidate_connect_requested", token(id)); central.connect(peripheral, options: nil)
        } else {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: option("--operation") == "passive-rssi"])
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard active else { return }
        if option("--operation") == "passive-rssi" {
            let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
            guard option("--target")?.lowercased() == peripheral.identifier.uuidString.lowercased() ||
                  (option("--match-name") != nil && option("--match-name") == name) else { return }
            if (-127 ... -1).contains(RSSI.intValue) {
                completed = true
                log("advertised_rssi_presence_only", "\(token(peripheral.identifier)):\(RSSI.intValue)")
            }
            return
        }
        if seen.insert(peripheral.identifier).inserted { log("seen_run_token", token(peripheral.identifier)) }
        if option("--selection-file") != nil {
            let name = (peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "")
            if ["phone", "watch", "airpods", "headset", "earbuds", "siri", "remote"].contains(where: { name.lowercased().contains($0) }) {
                selection[token(peripheral.identifier)] = ["name": String(name.prefix(128)), "identifier": peripheral.identifier.uuidString]
            }
        }
        guard !attempted, option("--target")?.lowercased() == peripheral.identifier.uuidString.lowercased() else { return }
        attempted = true; retained = peripheral; peripheral.delegate = self
        central.stopScan(); central.connect(peripheral, options: nil)
    }
    func valid(_ peripheral: CBPeripheral) -> Bool { active && retained === peripheral && peripheral.state == .connected }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard valid(peripheral) else { central.cancelPeripheralConnection(peripheral); return }
        log("connected", token(peripheral.identifier))
        if option("--operation") == "rssi" { peripheral.readRSSI(); return }
        peripheral.discoverServices(option("--service").map { [CBUUID(string: $0)] })
    }
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard valid(peripheral), option("--operation") == "rssi" else { return }
        let value = RSSI.intValue
        if error == nil, (-127 ... -1).contains(value) {
            completed = true; log("connected_rssi_presence_only", String(value))
        } else { log("rssi_unavailable") }
        let generation = epoch
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak peripheral] in
            guard let self, let peripheral, self.epoch == generation, self.valid(peripheral) else { return }
            peripheral.readRSSI()
        }
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard retained === peripheral else { return }; retained = nil; epoch = UUID(); log("connect_failed")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard retained === peripheral else { return }; retained = nil; epoch = UUID(); log("disconnected_evidence_revoked")
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard valid(peripheral) else { return }
        guard error == nil else { log("service_discovery_failed", String((error! as NSError).code)); return }
        log("service_discovery_count", String(peripheral.services?.count ?? 0))
        for s in peripheral.services ?? [] { peripheral.discoverCharacteristics(option("--characteristic").map { [CBUUID(string: $0)] }, for: s) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard valid(peripheral) else { return }
        guard error == nil else { log("characteristic_discovery_failed", String((error! as NSError).code)); return }
        log("characteristic_discovery_count", String(service.characteristics?.count ?? 0))
        for c in service.characteristics ?? [] where option("--characteristic")?.lowercased() == c.uuid.uuidString.lowercased() {
            if option("--operation") == "notify", c.properties.contains(.notify) || c.properties.contains(.indicate) {
                log("subscription_requested"); peripheral.setNotifyValue(true, for: c)
            } else if option("--operation") == "read", c.properties.contains(.read) {
                log("read_requested"); peripheral.readValue(for: c)
            } else { log("operation_not_supported") }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard valid(peripheral) else { return }
        log(error == nil && characteristic.isNotifying ? "subscription_accepted_identity_unproven" : "subscription_failed")
        if error == nil && characteristic.isNotifying { completed = true }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard valid(peripheral), option("--characteristic")?.lowercased() == characteristic.uuid.uuidString.lowercased() else { return }
        guard error == nil else { log("value_failed"); return }
        completed = true; log("value_received_payload_discarded")
    }
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard valid(peripheral) else { return }
        retained = nil; epoch = UUID(); central?.cancelPeripheralConnection(peripheral)
        log("service_removed_evidence_revoked")
    }
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        log("peripheral_state", String(peripheral.state.rawValue))
        guard active, peripheral.state == .poweredOn else { epoch = UUID(); return }
        let c = CBMutableCharacteristic(type: CBUUID(string: "7226818A-90D4-4755-AB5D-DC12AFE4C202"),
            properties: [.read, .notifyEncryptionRequired], value: nil, permissions: [.readEncryptionRequired])
        let s = CBMutableService(type: serviceID, primary: true); s.characteristics = [c]
        peripheral.add(s)
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard active, error == nil else { log("service_add_failed"); return }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceID], CBAdvertisementDataLocalNameKey: "WindowShade Evidence"])
    }
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        log(error == nil ? "protected_test_service_advertised" : "advertising_failed")
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard active, request.offset == 0 else { peripheral.respond(to: request, withResult: .invalidOffset); return }
        request.value = Data([1]); peripheral.respond(to: request, withResult: .success)
        completed = true; log("encrypted_read_access_identity_unproven", token(request.central.identifier))
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard active else { return }; completed = true
        log("encrypted_subscription_identity_unproven", token(central.identifier))
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        log("subscription_ended_evidence_revoked", token(central.identifier))
    }
}
@main struct Main {
    static func main() { let p = Probe(); p.start(); withExtendedLifetime(p) { RunLoop.main.run() } }
}
