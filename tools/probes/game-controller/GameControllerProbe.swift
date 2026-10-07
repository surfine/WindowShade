// Isolated capability/input probe. No discovery, pairing, input synthesis or App routing.
import Foundation
@preconcurrency import GameController

@MainActor final class Probe {
    var known: Set<ObjectIdentifier> = []
    var previous: [String: Float] = [:]
    var samples = 0
    let started = Date()
    func emit(_ fields: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        print(line)
    }
    func sample(observe: Bool) {
        let controllers = GCController.controllers()
        let present = Set(controllers.map(ObjectIdentifier.init))
        for removed in known.subtracting(present) {
            emit(["event": "disconnected", "device": String(describing: removed)])
            previous = previous.filter { !$0.key.hasPrefix(String(describing: removed) + ":") }
        }
        for controller in controllers {
            let identity = ObjectIdentifier(controller), key = String(describing: identity)
            let profile = controller.physicalInputProfile
            if !known.contains(identity) {
                emit(["event": "connected", "device": key,
                      "vendor": controller.vendorName ?? "unknown", "productCategory": controller.productCategory,
                      "extendedGamepad": controller.extendedGamepad != nil,
                      "microGamepad": controller.microGamepad != nil,
                      "buttons": profile.buttons.keys.sorted(), "axes": profile.axes.keys.sorted(),
                      "directionPads": profile.dpads.keys.sorted()])
            }
            guard observe else { continue }
            var values: [String: Float] = [:]
            for (name, button) in profile.buttons { values["button:" + name] = button.value }
            for (name, axis) in profile.axes { values["axis:" + name] = axis.value }
            for (name, pad) in profile.dpads {
                values["dpad:" + name + ":x"] = pad.xAxis.value
                values["dpad:" + name + ":y"] = pad.yAxis.value
            }
            for name in values.keys.sorted() {
                let value = values[name]!, index = key + ":" + name
                defer { previous[index] = value }
                guard let prior = previous[index], abs(prior - value) > 0.001, samples < 2000 else { continue }
                samples += 1
                emit(["event": "input", "device": key, "element": name, "value": value,
                      "elapsedSeconds": Date().timeIntervalSince(started)])
            }
        }
        known = present
    }
}
@main struct Main {
    @MainActor static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args == ["--list"] || args == ["--observe", "60"] else {
            print("Usage: GameControllerProbe --list | --observe 60"); exit(64)
        }
        let observing = args.first == "--observe", probe = Probe()
        // Process-local setting, restored before exit; never modifies Bluetooth or other apps.
        let prior = GCController.shouldMonitorBackgroundEvents
        if observing { GCController.shouldMonitorBackgroundEvents = true }
        defer { GCController.shouldMonitorBackgroundEvents = prior }
        let deadline = Date().addingTimeInterval(observing ? 60 : 1)
        probe.emit(["event": "start", "mode": observing ? "observe" : "list", "seconds": observing ? 60 : 1])
        repeat {
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.02)))
            probe.sample(observe: observing)
        } while Date() < deadline
        probe.emit(["event": "finished", "connectedCount": probe.known.count, "inputSamples": probe.samples,
                    "sampling": "20ms polling; brief transitions may be missed", "successMeans": "probe completed, not device acceptance"])
    }
}
