// WindowShade 2 与 2.1 · 多前置镜头。
// 主镜头跟着人正在看的那一块屏幕。第二颗只作辅助：对得上是 yes，对不上是 no，不够是 unknown。
// 辅助不是身份，不解锁，不代填。没有公分，没有角度门槛，没有分数。
// 未知保持未知。没选到镜头不写成距离刚好，也不写成没有人。
import Foundation

struct WS2CameraID: Hashable, Sendable, Equatable {
    var value: String
}

struct WS2ScreenID: Hashable, Sendable, Equatable {
    var value: String
}

/// 镜头落在哪一类地方。调用方从系统读到什么就填什么；读不到就 unknown。
/// 本类型不调用 AVCaptureDevice，也不把名字当成屏幕身份。
enum WS2CameraPlacement: Equatable, Sendable {
    case unknown
    /// 在电脑内建的那块屏幕里。不是某一块外接屏。
    case builtInDisplay
    /// 在外接显示器里。屏幕 ID 为空时，只知道「某一台外接」，不知道是哪一块。
    case externalDisplay(WS2ScreenID?)
}

enum WS2LookedAt: Equatable, Sendable {
    /// 刘海宿主在这块屏上。优先于焦点窗口。
    case notchHost(WS2ScreenID)
    /// 刘海不在任何一块屏上时，才用焦点窗口所在的屏。
    case focusedWindow(WS2ScreenID)
    case unknown

    /// 先刘海所在的那块，没有刘海才跟焦点窗口。没有鼠标参数。
    static func resolve(notchHost: WS2ScreenID?, focusedWindow: WS2ScreenID?) -> WS2LookedAt {
        if let notchHost { return .notchHost(notchHost) }
        if let focusedWindow { return .focusedWindow(focusedWindow) }
        return .unknown
    }

    var screen: WS2ScreenID? {
        switch self {
        case .notchHost(let screen), .focusedWindow(let screen): return screen
        case .unknown: return nil
        }
    }
}

struct WS2ScreenArrangement: Equatable, Sendable {
    var screens: [WS2ScreenID]
    /// 内建屏。台式机器没有内建屏时是 nil。
    var builtIn: WS2ScreenID?

    static func laptopBelow(upper: WS2ScreenID, lower: WS2ScreenID) -> WS2ScreenArrangement {
        WS2ScreenArrangement(screens: [upper, lower], builtIn: lower)
    }

    static func sideBySide(_ screens: [WS2ScreenID], builtIn: WS2ScreenID? = nil) -> WS2ScreenArrangement {
        WS2ScreenArrangement(screens: screens, builtIn: builtIn)
    }

    static func single(_ screen: WS2ScreenID, builtIn: Bool) -> WS2ScreenArrangement {
        WS2ScreenArrangement(screens: [screen], builtIn: builtIn ? screen : nil)
    }
}

struct WS2CameraCandidate: Equatable, Sendable {
    var id: WS2CameraID
    var placement: WS2CameraPlacement
    /// 调用方已经判定这是前置。侧面和后置不进主镜头，也不进辅助。
    var isFront: Bool
}

enum WS2FaceSight: Equatable, Sendable {
    case unknown
    case noFace
    case face
}

/// 两路动作是否对得上。调用方给结论。这里不比较角度，也不编时间门槛。
enum WS2ActionAlignment: Equatable, Sendable {
    case unknown
    /// 两颗都看到同一张脸，点头或张嘴在时间上对得上。
    case aligned
    /// 两路都有动作，时间对不上。
    case misaligned
}

struct WS2CameraChoiceInput: Equatable, Sendable {
    var cameras: [WS2CameraCandidate] = []
    var lookedAt: WS2LookedAt = .unknown
    var arrangement: WS2ScreenArrangement = WS2ScreenArrangement(screens: [], builtIn: nil)
    /// 这组屏幕排列上次成功的主镜头。没有就是 nil。
    var rememberedPrimary: WS2CameraID?
    /// 这一组排列已经问过一次。
    var alreadyAsked = false
    /// 用户关掉了第二颗的辅助。默认开着。不为了打开它发问。
    var auxiliaryDisabled = false
    /// 这一次认得出是登记的人。认不出才可能问镜头。
    var personRecognized = false
    /// 新镜头刚接上。这一下不发问，也不打断当前操作。
    var cameraJustConnected = false
    var sight: [WS2CameraID: WS2FaceSight] = [:]
    var actionAlignment: WS2ActionAlignment = .unknown
}

enum WS2Auxiliary: Equatable, Sendable {
    case unknown
    case yes
    case no
}

enum WS2LookedAtDistance: Equatable, Sendable {
    case unknown
    /// 这块屏上的那颗镜头看到了脸。公分不在这里计算。
    case seenByCameraOnThisScreen
}

struct WS2CameraChoiceDecision: Equatable, Sendable {
    var primary: WS2CameraID?
    /// 主镜头的位置就是人正在看的这块屏。笔电镜头看着上面那块时，这里是 false。
    var primaryIsOnLookedAtScreen: Bool
    var askOnce: Bool
    var interrupts: Bool
    var auxiliary: WS2Auxiliary
    /// 永远没有分数。对不上不是 0.5，未知也不是 0。
    var auxiliaryScore: Double?
    var distance: WS2LookedAtDistance
    /// 永远没有公分。nil 不是 0，也不是刚好。
    var centimeters: Double?
    /// 这块屏允许用主镜头做刷脸尝试。允许尝试仍不解锁。
    var mayAttemptFaceUnlockOnThisScreen: Bool
    var grantsUnlock: Bool
    var identifiesEnrolledPerson: Bool
    /// 不提示再接一颗镜头。
    var asksForAnotherCamera: Bool
    /// 没选到镜头，也不写成没有人。
    var reportsNoPerson: Bool
    /// 没能量到，也不写成距离刚好。
    var reportsDistanceJustRight: Bool
}

enum WS2CameraSimulation {
    struct Preview: Equatable, Sendable {
        var line: String
        var grantsUnlock: Bool
        var reportsNoPerson: Bool
        var centimeters: Double?
    }

    /// 没有镜头。距离保持未知，不写成没有人，也不写成刚好。
    static func noCamera() -> Preview {
        let decision = WS2CameraChoice.decide(WS2CameraChoiceInput())
        let unknown = decision.distance == .unknown && decision.centimeters == nil && decision.primary == nil
        return Preview(
            line: unknown ? "未知" : "这次没有做",
            grantsUnlock: decision.grantsUnlock,
            reportsNoPerson: decision.reportsNoPerson,
            centimeters: decision.centimeters)
    }
}

enum WS2CameraChoice {
    static func decide(_ input: WS2CameraChoiceInput) -> WS2CameraChoiceDecision {
        let fronts = input.cameras.filter(\.isFront)
        let screen = input.lookedAt.screen
        let yes = fronts.filter { match($0, screen: screen, arrangement: input.arrangement) == .yes }
        let remembered = input.rememberedPrimary.flatMap { id in fronts.contains(where: { $0.id == id }) ? id : nil }

        let primary: WS2CameraID?
        let uncertain: Bool
        if yes.count == 1 {
            primary = yes[0].id
            uncertain = false
        } else if let remembered, yes.isEmpty || yes.contains(where: { $0.id == remembered }) {
            primary = remembered
            uncertain = true
        } else if fronts.count == 1, yes.isEmpty {
            primary = fronts[0].id
            uncertain = false
        } else {
            primary = nil
            uncertain = true
        }

        let onScreen = primary.map { id in
            fronts.contains { $0.id == id && match($0, screen: screen, arrangement: input.arrangement) == .yes }
        } ?? false
        let primarySight = primary.flatMap { input.sight[$0] } ?? .unknown
        let distance: WS2LookedAtDistance = onScreen && primarySight == .face ? .seenByCameraOnThisScreen : .unknown
        let faces = fronts.filter { input.sight[$0.id] == .face }.count
        let auxiliary: WS2Auxiliary
        if fronts.count < 2 || input.auxiliaryDisabled {
            auxiliary = .unknown
        } else if input.actionAlignment == .misaligned {
            auxiliary = .no
        } else if input.actionAlignment == .aligned, faces >= 2 {
            auxiliary = .yes
        } else {
            auxiliary = .unknown
        }
        let askOnce = uncertain && !input.personRecognized && fronts.count >= 2
            && !input.alreadyAsked && !input.cameraJustConnected

        return WS2CameraChoiceDecision(
            primary: primary,
            primaryIsOnLookedAtScreen: onScreen,
            askOnce: askOnce,
            interrupts: false,
            auxiliary: auxiliary,
            auxiliaryScore: nil,
            distance: distance,
            centimeters: nil,
            mayAttemptFaceUnlockOnThisScreen: onScreen,
            grantsUnlock: false,
            identifiesEnrolledPerson: false,
            asksForAnotherCamera: false,
            reportsNoPerson: false,
            reportsDistanceJustRight: false
        )
    }

    /// yes：这颗镜头就在这块屏上。no：明确在别的地方。uncertain：对不上具体是哪一块。
    static func match(_ camera: WS2CameraCandidate, screen: WS2ScreenID?, arrangement: WS2ScreenArrangement) -> Match {
        guard let screen else { return .uncertain }
        switch camera.placement {
        case .unknown:
            return .uncertain
        case .builtInDisplay:
            guard let builtIn = arrangement.builtIn else { return .uncertain }
            return builtIn == screen ? .yes : .no
        case .externalDisplay(let bound):
            if let bound { return bound == screen ? .yes : .no }
            if arrangement.builtIn == nil {
                if arrangement.screens.count == 1, arrangement.screens[0] == screen { return .yes }
                return .uncertain
            }
            let externals = arrangement.screens.filter { $0 != arrangement.builtIn }
            if externals.count == 1 { return externals[0] == screen ? .yes : .no }
            return .uncertain
        }
    }

    enum Match: Equatable, Sendable {
        case yes, no, uncertain
    }
}
