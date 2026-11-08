// WindowShade 2 审查包：原创边界骨架，非完整功能。
import GameController
@available(macOS 14.0, *)
func setPreviewResistance(on controller: GCController, enabled: Bool) {
    guard let pad = controller.physicalInputProfile as? GCDualSenseGamepad else { return }
    if enabled {
        pad.rightTrigger.setModeFeedbackWithStartPosition(0.6, resistiveStrength: 0.25)
    } else {
        pad.leftTrigger.setModeOff()
        pad.rightTrigger.setModeOff()
    }
}
