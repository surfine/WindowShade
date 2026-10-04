// 多前置镜头的纯逻辑。不打开相机，不编角度，不写公分。
import Foundation

@main
struct CameraChoiceTests {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func camera(_ value: String, _ placement: WS2CameraPlacement) -> WS2CameraCandidate {
        WS2CameraCandidate(id: WS2CameraID(value: value), placement: placement, isFront: true)
    }

    static func screen(_ value: String) -> WS2ScreenID { WS2ScreenID(value: value) }

    static func main() {
        singleCameraDoesNotAsk()
        notchHostFollowsThatScreen()
        focusedWindowWhenNotchIsAbsent()
        notchHostBeatsFocusedWindow()
        laptopCameraDoesNotMeasureUpperScreen()
        onlyLowerFaceLeavesUpperDistanceUnknown()
        sideBySideSwitchesWithoutAsking()
        uncertainReusesLastSuccess()
        askOnceOnlyWhenUnrecognized()
        alignedAuxiliaryDoesNotUnlock()
        misalignedIsNoNotAScore()
        newCameraDoesNotInterrupt()
        disabledAuxiliaryStaysUnknown()
        missingCameraIsNotNoPersonOrJustRight()
        if failures == 0 { print("PASS camera-choice") }
        else { print("FAIL camera-choice \(failures)") }
        exit(failures == 0 ? 0 : 1)
    }

    static func singleCameraDoesNotAsk() {
        let laptop = camera("laptop", .builtInDisplay)
        let lower = screen("lower")
        let decision = WS2CameraChoice.decide(WS2CameraChoiceInput(
            cameras: [laptop],
            lookedAt: .notchHost(lower),
            arrangement: .single(lower, builtIn: true),
            personRecognized: false,
            sight: [laptop.id: .face],
            actionAlignment: .aligned
        ))
        expect(decision.primary == laptop.id, "one front camera is used")
        expect(!decision.askOnce && !decision.asksForAnotherCamera, "one front camera does not ask")
        expect(decision.auxiliary == .unknown, "one camera auxiliary is unknown")
        expect(decision.auxiliaryScore == nil, "one camera has no auxiliary score")
        expect(!decision.grantsUnlock && !decision.identifiesEnrolledPerson, "one camera does not unlock")
        expect(decision.distance == .seenByCameraOnThisScreen && decision.centimeters == nil,
               "the only on-screen camera can see a face and still writes no centimeters")
    }

    static func notchHostFollowsThatScreen() {
        let upper = screen("upper")
        let lower = screen("lower")
        let laptop = camera("laptop", .builtInDisplay)
        let studio = camera("studio", .externalDisplay(nil))
        let decision = WS2CameraChoice.decide(WS2CameraChoiceInput(
            cameras: [laptop, studio],
            lookedAt: .notchHost(upper),
            arrangement: .laptopBelow(upper: upper, lower: lower),
            sight: [studio.id: .face, laptop.id: .face]
        ))
        expect(decision.primary == studio.id && decision.primaryIsOnLookedAtScreen,
               "the notch on the upper screen uses the camera on that screen")
        expect(decision.mayAttemptFaceUnlockOnThisScreen && !decision.grantsUnlock,
               "the matching camera may be tried and still does not unlock")
        expect(!decision.askOnce, "a matched screen does not ask")
    }

    static func focusedWindowWhenNotchIsAbsent() {
        let upper = screen("upper")
        let lower = screen("lower")
        let laptop = camera("laptop", .builtInDisplay)
        let studio = camera("studio", .externalDisplay(upper))
        let decision = WS2CameraChoice.decide(WS2CameraChoiceInput(
            cameras: [laptop, studio],
            lookedAt: .focusedWindow(lower),
            arrangement: .laptopBelow(upper: upper, lower: lower)
        ))
        expect(decision.primary == laptop.id && decision.primaryIsOnLookedAtScreen,
               "with no notch, the focused window's screen picks its camera")
        expect(!decision.askOnce, "following the focused window does not ask")
    }

    static func notchHostBeatsFocusedWindow() {
        let upper = screen("upper")
        let lower = screen("lower")
        expect(WS2LookedAt.resolve(notchHost: upper, focusedWindow: lower) == .notchHost(upper),
               "the notch screen wins over the focused window")
        expect(WS2LookedAt.resolve(notchHost: nil, focusedWindow: lower) == .focusedWindow(lower),
               "the focused window is used only when the notch names no screen")
    }

    static func laptopCameraDoesNotMeasureUpperScreen() {
        let upper = screen("upper")
        let lower = screen("lower")
        let laptop = camera("laptop", .builtInDisplay)
        let decision = WS2CameraChoice.decide(WS2CameraChoiceInput(
            cameras: [laptop],
            lookedAt: .notchHost(upper),
            arrangement: .laptopBelow(upper: upper, lower: lower),
            sight: [laptop.id: .face]
        ))
        expect(decision.primary == laptop.id, "the only camera is still opened")
        expect(!decision.primaryIsOnLookedAtScreen && !decision.mayAttemptFaceUnlockOnThisScreen,
               "the laptop camera does not face-unlock the upper screen")
        expect(decision.distance == .unknown && decision.centimeters == nil,
               "the laptop camera does not write the upper screen's distance")
        expect(!decision.reportsNoPerson && !decision.reportsDistanceJustRight && !decision.askOnce,
               "an unusable laptop view stays unknown and does not ask")
    }

    static func onlyLowerFaceLeavesUpperDistanceUnknown() {
        let upper = screen("upper")
        let lower = screen("lower")
        let laptop = camera("laptop", .builtInDisplay)
        let studio = camera("studio", .externalDisplay(nil))
        let decision = WS2CameraChoice.decide(WS2CameraChoiceInput(
            cameras: [laptop, studio],
            lookedAt: .notchHost(upper),
            arrangement: .laptopBelow(upper: upper, lower: lower),
            sight: [laptop.id: .face, studio.id: .noFace]
        ))
        expect(decision.primary == studio.id, "the upper screen keeps its own camera")
        expect(decision.distance == .unknown && decision.centimeters == nil,
               "a face on the lower camera does not write the upper screen's distance")
        expect(decision.auxiliary == .unknown && decision.auxiliaryScore == nil,
               "one camera seeing a face leaves auxiliary unknown")
        expect(!decision.grantsUnlock, "a lower-camera face does not unlock the upper screen")
    }

    static func sideBySideSwitchesWithoutAsking() {
        let left = screen("left")
        let right = screen("right")
        let west = camera("west", .externalDisplay(left))
        let east = camera("east", .externalDisplay(right))
        let arrangement = WS2ScreenArrangement.sideBySide([left, right])
        let lookingLeft = WS2CameraChoice.decide(WS2CameraChoiceInput(
            cameras: [west, east], lookedAt: .notchHost(left), arrangement: arrangement
        ))
        let lookingRight = WS2CameraChoice.decide(WS2CameraChoiceInput(
            cameras: [west, east], lookedAt: .notchHost(right), arrangement: arrangement
        ))
        expect(lookingLeft.primary == west.id && lookingRight.primary == east.id,
               "side by side follows the screen being looked at")
        expect(!lookingLeft.askOnce && !lookingRight.askOnce, "changing screens does not ask")
    }

    static func uncertainReusesLastSuccess() {
        let left = screen("left")
        let right = screen("right")
        let west = camera("west", .externalDisplay(nil))
        let east = camera("east", .externalDisplay(nil))
        let decision = WS2CameraChoice.decide(WS2CameraChoiceInput(
            cameras: [west, east],
            lookedAt: .notchHost(left),
            arrangement: .sideBySide([left, right]),
            rememberedPrimary: west.id,
            personRecognized: true
        ))
        expect(decision.primary == west.id && !decision.askOnce,
               "an uncertain pair reuses the last success and does not ask when the person is recognized")
        expect(decision.distance == .unknown && !decision.primaryIsOnLookedAtScreen,
               "a reused camera that is not tied to this screen writes no distance")
    }

    static func askOnceOnlyWhenUnrecognized() {
        let left = screen("left")
        let right = screen("right")
        let west = camera("west", .unknown)
        let east = camera("east", .unknown)
        func input(recognized: Bool, asked: Bool, connected: Bool = false) -> WS2CameraChoiceInput {
            WS2CameraChoiceInput(
                cameras: [west, east],
                lookedAt: .notchHost(left),
                arrangement: .sideBySide([left, right]),
                rememberedPrimary: west.id,
                alreadyAsked: asked,
                personRecognized: recognized,
                cameraJustConnected: connected
            )
        }
        let first = WS2CameraChoice.decide(input(recognized: false, asked: false))
        let again = WS2CameraChoice.decide(input(recognized: false, asked: true))
        let recognized = WS2CameraChoice.decide(input(recognized: true, asked: false))
        expect(first.askOnce && first.primary == west.id, "uncertain and unrecognized asks once while keeping the last camera")
        expect(!again.askOnce && again.primary == west.id, "the same arrangement does not ask a second time")
        expect(!recognized.askOnce, "a recognized person does not get the camera question")

        let upper = screen("upper")
        let lower = screen("lower")
        let laptop = camera("laptop", .builtInDisplay)
        let studio = camera("studio", .externalDisplay(upper))
        let matched = WS2CameraChoice.decide(WS2CameraChoiceInput(
            cameras: [laptop, studio],
            lookedAt: .notchHost(upper),
            arrangement: .laptopBelow(upper: upper, lower: lower),
            personRecognized: false,
            sight: [studio.id: .unknown]
        ))
        expect(!matched.askOnce && matched.distance == .unknown,
               "unknown distance on an already matched camera does not ask")
    }

    static func alignedAuxiliaryDoesNotUnlock() {
        let upper = screen("upper")
        let lower = screen("lower")
        let laptop = camera("laptop", .builtInDisplay)
        let studio = camera("studio", .externalDisplay(nil))
        let decision = WS2CameraChoice.decide(WS2CameraChoiceInput(
            cameras: [laptop, studio],
            lookedAt: .notchHost(upper),
            arrangement: .laptopBelow(upper: upper, lower: lower),
            sight: [laptop.id: .face, studio.id: .face],
            actionAlignment: .aligned
        ))
        expect(decision.auxiliary == .yes && decision.auxiliaryScore == nil,
               "aligned cameras produce auxiliary yes and no score")
        expect(!decision.grantsUnlock && !decision.identifiesEnrolledPerson,
               "auxiliary yes does not identify the person or unlock")
        expect(decision.primary == studio.id && decision.distance == .seenByCameraOnThisScreen
               && decision.centimeters == nil,
               "the upper screen's face still comes only from its own camera, with no centimeters")
    }

    static func misalignedIsNoNotAScore() {
        let left = screen("left")
        let right = screen("right")
        let decision = WS2CameraChoice.decide(WS2CameraChoiceInput(
            cameras: [camera("west", .externalDisplay(left)), camera("east", .externalDisplay(right))],
            lookedAt: .notchHost(left),
            arrangement: .sideBySide([left, right]),
            sight: [WS2CameraID(value: "west"): .face, WS2CameraID(value: "east"): .face],
            actionAlignment: .misaligned
        ))
        expect(decision.auxiliary == .no && decision.auxiliaryScore == nil,
               "a time mismatch is auxiliary no, not a score")
        expect(!decision.grantsUnlock, "a mismatch does not unlock")
    }

    static func newCameraDoesNotInterrupt() {
        let left = screen("left")
        let right = screen("right")
        let west = camera("west", .unknown)
        let east = camera("east", .unknown)
        let connected = WS2CameraChoice.decide(WS2CameraChoiceInput(
            cameras: [west, east],
            lookedAt: .notchHost(left),
            arrangement: .sideBySide([left, right]),
            rememberedPrimary: west.id,
            personRecognized: false,
            cameraJustConnected: true
        ))
        expect(!connected.askOnce && !connected.interrupts && connected.primary == west.id,
               "a camera that just connected does not ask and does not interrupt")

        let upper = screen("upper")
        let lower = screen("lower")
        let quiet = WS2CameraChoice.decide(WS2CameraChoiceInput(
            cameras: [camera("laptop", .builtInDisplay), camera("studio", .externalDisplay(nil))],
            lookedAt: .notchHost(upper),
            arrangement: .laptopBelow(upper: upper, lower: lower),
            cameraJustConnected: true,
            sight: [WS2CameraID(value: "studio"): .face]
        ))
        expect(quiet.primary == WS2CameraID(value: "studio") && !quiet.askOnce && !quiet.interrupts,
               "a newly connected camera that matches the screen is adopted quietly")
    }

    static func disabledAuxiliaryStaysUnknown() {
        let upper = screen("upper")
        let lower = screen("lower")
        let decision = WS2CameraChoice.decide(WS2CameraChoiceInput(
            cameras: [camera("laptop", .builtInDisplay), camera("studio", .externalDisplay(upper))],
            lookedAt: .notchHost(upper),
            arrangement: .laptopBelow(upper: upper, lower: lower),
            auxiliaryDisabled: true,
            sight: [WS2CameraID(value: "laptop"): .face, WS2CameraID(value: "studio"): .face],
            actionAlignment: .aligned
        ))
        expect(decision.auxiliary == .unknown && !decision.askOnce && !decision.asksForAnotherCamera,
               "turning auxiliary off leaves it unknown and does not ask to turn it on")
    }

    static func missingCameraIsNotNoPersonOrJustRight() {
        let decision = WS2CameraChoice.decide(WS2CameraChoiceInput(
            lookedAt: .notchHost(screen("only")),
            arrangement: .single(screen("only"), builtIn: true)
        ))
        expect(decision.primary == nil && decision.distance == .unknown && decision.centimeters == nil,
               "no camera leaves distance unknown")
        expect(!decision.reportsNoPerson && !decision.reportsDistanceJustRight && !decision.grantsUnlock,
               "no camera is not written as nobody there or as a just-right distance")
    }
}
