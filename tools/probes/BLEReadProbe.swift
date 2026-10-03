// Standalone macOS probe. No characteristic bytes, device names, or keys are logged.
import Foundation
import CoreBluetooth
final class Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var retained: CBPeripheral?
    private let started = ContinuousClock.now
    private let args = CommandLine.arguments
    private var attempted = false
    private var completed = false
    func option(_ name: String) -> String? { guard let i = args.firstIndex(of:name), i+1 < args.count else { return nil }; return args[i+1] }
    func log(_ event:String,_ value:String = "") {
        let seconds = started.duration(to:.now).components.seconds
        print("\(seconds),\(event),\(value),readable_is_not_authenticated")
        fflush(stdout)
    }
    func start() {
        print("elapsed_s,event,value,qualification")
        central = CBCentralManager(delegate:self,queue:.main)
        DispatchQueue.main.asyncAfter(deadline:.now()+45) { [self] in
            central.stopScan(); if let p = retained { central.cancelPeripheralConnection(p) }
            log("finished",completed ? "read_completed" : "inconclusive"); exit(completed ? 0 : 2)
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("central_state",String(central.state.rawValue))
        guard central.state == .poweredOn else { return }
        let filter = option("--service").map { [CBUUID(string:$0)] }
        central.scanForPeripherals(withServices:filter,options:[CBCentralManagerScanOptionAllowDuplicatesKey:false])
    }
    func centralManager(_ central:CBCentralManager,didDiscover peripheral:CBPeripheral,
                        advertisementData:[String:Any],rssi RSSI:NSNumber) {
        log("discovered_local_identifier",peripheral.identifier.uuidString)
        guard !attempted, option("--target")?.lowercased() == peripheral.identifier.uuidString.lowercased() else { return }
        attempted = true; retained = peripheral; peripheral.delegate = self
        central.stopScan(); central.connect(peripheral,options:nil)
    }
    func centralManager(_ central:CBCentralManager,didConnect peripheral:CBPeripheral) {
        log("connected"); peripheral.discoverServices(option("--service").map{[CBUUID(string:$0)]})
    }
    func centralManager(_ central:CBCentralManager,didFailToConnect peripheral:CBPeripheral,error:Error?) { log("connect_failed") }
    func centralManager(_ central:CBCentralManager,didDisconnectPeripheral peripheral:CBPeripheral,error:Error?) { log("disconnected") }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverServices error:Error?) {
        guard error == nil else { log("service_error"); return }
        for s in peripheral.services ?? [] { log("service",s.uuid.uuidString); peripheral.discoverCharacteristics(nil,for:s) }
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverCharacteristicsFor service:CBService,error:Error?) {
        guard error == nil else { log("characteristic_error"); return }
        for c in service.characteristics ?? [] {
            log("characteristic_\(c.properties.contains(.read) ? "read" : "not_read")",c.uuid.uuidString)
            if option("--characteristic")?.lowercased() == c.uuid.uuidString.lowercased(), c.properties.contains(.read) {
                log("read_requested"); peripheral.readValue(for:c)
            }
        }
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateValueFor characteristic:CBCharacteristic,error:Error?) {
        guard option("--characteristic")?.lowercased() == characteristic.uuid.uuidString.lowercased() else { return }
        if error != nil { log("read_failed"); return }
        completed = true; log("read_response_byte_count",String(characteristic.value?.count ?? 0))
    }
}
@main struct Main { static func main() { let p = Probe(); p.start(); withExtendedLifetime(p) { RunLoop.main.run() } } }
