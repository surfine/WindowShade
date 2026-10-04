// WindowShade 2.1 · 解锁、代填、口令、配对、CarPlay 的交接。
// 没有真机时只记下还没发生。不合成按键，不保存秘密，不打开配对，不接收 CarPlay。
import Foundation

enum WS2SilentSecurityKind: Equatable, Sendable {
    case unlock, fill, phrase, device, carPlay
}

struct WS2SilentSecurityOutcome: Equatable, Sendable {
    var id: String
    var kind: WS2SilentSecurityKind
    var handedToSystem: Bool
    var unlocks: Bool
    var fillsPassword: Bool
    var holdsSecret: Bool
    var typesSecret: Bool
    var synthesizesKeystroke: Bool
    var callsPrivateUnlockAPI: Bool
    var recordedMicrophone: Bool
    var hardwareVoiceMatched: Bool
    var executesCommand: Bool
    var deviceBound: Bool
    var pairingSessionOpen: Bool
    var talksToRadio: Bool
    var carPlayConnected: Bool
    var carPlaySessionStarted: Bool
    var line: String
}

enum WS2SilentSecurity {
    static let commandIDs: [String] = [
        "auth.settings", "auth.enroll", "auth.deleteEnrollment", "auth.begin", "auth.cancel",
        "auth.useSystem", "auth.authorizeSession", "auth.revokeSession", "auth.lab", "auth.profiles",
        "device.bind", "device.revoke", "device.status", "device.range",
        "credential.chooseAlias", "credential.secretPhraseLab",
        "carplay.enter", "carplay.exit",
        "privacy.reveal", "privacy.panicLock",
        "dictation.enableWhisper",
    ]

    static func outcome(_ id: String) -> WS2SilentSecurityOutcome? {
        switch id {
        case "auth.enroll", "auth.deleteEnrollment", "auth.begin", "auth.profiles",
             "auth.lab", "auth.useSystem", "privacy.reveal", "privacy.panicLock":
            return make(id, kind: .unlock, handedToSystem: true)
        case "auth.settings", "auth.cancel", "auth.revokeSession":
            return make(id, kind: .unlock, handedToSystem: false)
        case "auth.authorizeSession", "credential.chooseAlias":
            return make(id, kind: .fill, handedToSystem: id == "auth.authorizeSession")
        case "credential.secretPhraseLab", "dictation.enableWhisper":
            return make(id, kind: .phrase, handedToSystem: true)
        case "device.bind", "device.revoke", "device.range":
            return make(id, kind: .device, handedToSystem: true)
        case "device.status":
            return make(id, kind: .device, handedToSystem: false, line: "未知")
        case "carplay.enter", "carplay.exit":
            return make(id, kind: .carPlay, handedToSystem: false, line: "还不能接收")
        default:
            return nil
        }
    }

    private static func make(
        _ id: String,
        kind: WS2SilentSecurityKind,
        handedToSystem: Bool,
        line: String? = nil
    ) -> WS2SilentSecurityOutcome {
        let written = line ?? spokenLine(id)
        return WS2SilentSecurityOutcome(
            id: id,
            kind: kind,
            handedToSystem: handedToSystem,
            unlocks: false,
            fillsPassword: false,
            holdsSecret: false,
            typesSecret: false,
            synthesizesKeystroke: false,
            callsPrivateUnlockAPI: false,
            recordedMicrophone: false,
            hardwareVoiceMatched: false,
            executesCommand: false,
            deviceBound: false,
            pairingSessionOpen: false,
            talksToRadio: false,
            carPlayConnected: false,
            carPlaySessionStarted: false,
            line: written
        )
    }

    private static func spokenLine(_ id: String) -> String {
        switch id {
        case "auth.settings", "auth.cancel", "auth.useSystem": return "不解锁"
        case "auth.revokeSession": return "没有许可"
        case "credential.chooseAlias": return "还没选"
        case "credential.secretPhraseLab": return "要用原来的确认"
        case "device.status": return "未知"
        case "carplay.enter", "carplay.exit": return "还不能接收"
        default:
            return WS2SilentCopy.line(id) ?? "要用原来的确认"
        }
    }
}

struct WS2SilentUnlockHandoff: Equatable, Sendable {
    private(set) var unlocks = false
    private(set) var synthesizesKeystroke = false
    private(set) var callsPrivateUnlockAPI = false
    private(set) var handedToSystem = false

    mutating func hand(_ id: String) {
        unlocks = false
        synthesizesKeystroke = false
        callsPrivateUnlockAPI = false
        handedToSystem = WS2SilentSecurity.outcome(id)?.handedToSystem ?? false
    }
}

struct WS2SilentFillHandoff: Equatable, Sendable {
    private(set) var fillsPassword = false
    private(set) var holdsSecret = false
    private(set) var typesSecret = false

    mutating func refuse(_ id: String) {
        _ = id
        fillsPassword = false
        holdsSecret = false
        typesSecret = false
    }
}

struct WS2SilentVoiceEnrollment: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle, lineShown
    }

    private(set) var recordedMicrophone = false
    private(set) var hardwareMatched = false
    private(set) var phase: Phase = .idle

    @discardableResult
    mutating func show(_ match: WS2SilentPhraseMatch) -> Phase {
        recordedMicrophone = false
        hardwareMatched = false
        if case .sameAsTap = match {
            phase = .lineShown
        } else {
            phase = .idle
        }
        return phase
    }

    func executes(_ match: WS2SilentPhraseMatch) -> Bool {
        _ = match
        return false
    }
}

struct WS2SilentDevicePairing: Equatable, Sendable {
    private(set) var bound = false
    private(set) var sessionOpen = false
    private(set) var talksToRadio = false

    mutating func bind() { stayUnknown() }
    mutating func revoke() { stayUnknown() }
    mutating func range() { stayUnknown() }
    mutating func showStatus() { stayUnknown() }

    var statusLine: String { "未知" }

    private mutating func stayUnknown() {
        bound = false
        sessionOpen = false
        talksToRadio = false
    }
}

struct WS2SilentCarPlayReceiver: Equatable, Sendable {
    private(set) var connected = false
    private(set) var sessionStarted = false

    mutating func enter() { stayDisconnected() }
    mutating func exit() { stayDisconnected() }

    var line: String { "还不能接收" }

    private mutating func stayDisconnected() {
        connected = false
        sessionStarted = false
    }
}
