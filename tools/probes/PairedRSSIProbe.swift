// Explicit paired-device presence probe. Does not pair, connect, disconnect or route audio/input.
import Foundation
import IOBluetooth

@main struct Main {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 2, ["--device", "--known-address"].contains(args[0]), !args[1].isEmpty else { exit(64) }
        let devices: [IOBluetoothDevice]
        if args[0] == "--known-address" {
            devices = IOBluetoothDevice(addressString: args[1]).map { [$0] } ?? []
        } else {
            devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter { $0.name == args[1] }
        }
        guard devices.count == 1, let device = devices.first else { print("paired_target_not_unique_or_missing"); exit(2) }
        let start = ProcessInfo.processInfo.systemUptime
        var values: [Int] = []
        print("elapsed_s,connected,rssi,qualification"); fflush(stdout)
        while ProcessInfo.processInfo.systemUptime - start < 30 {
            let connected = device.isConnected()
            let value = connected ? Int(device.rawRSSI()) : 127
            let valid = connected && (-127 ... -1).contains(value)
            if valid { values.append(value) }
            print("\(Int(ProcessInfo.processInfo.systemUptime-start)),\(connected),\(valid ? String(value) : "unavailable"),presence_only")
            fflush(stdout)
            RunLoop.current.run(until: Date().addingTimeInterval(2))
        }
        print("finished,samples=\(values.count),identity_unproven")
        exit(values.isEmpty ? 2 : 0)
    }
}
