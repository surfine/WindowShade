import Foundation

/// 输入设置。缺键就是关，不把没写过的键读成「已经开过」。
enum WS2InputPreferences {
    static let smoothKey = "WindowShade.Input.SmoothScroll"
    static let mouseDirectionKey = "WindowShade.Input.MouseScrollInverted"
    static let trackpadDirectionKey = "WindowShade.Input.TrackpadScrollInverted"
    static let fineKey = "WindowShade.Input.OptionFine"
    static let sideKey = "WindowShade.Input.SideButtons"
    static let middleKey = "WindowShade.Input.MiddleFold"
    static let threeKey = "WindowShade.Input.ThreeFingerTap"
    static let fourKey = "WindowShade.Input.FourFingerTap"
    static let exceptionsKey = "WindowShade.Input.ExceptionApps"
    static let remoteKey = "WindowShade.Input.RemoteMode"

    struct Value: Equatable {
        var smooth: SmoothScroll.Preset?
        var mouseInvert: Bool
        var trackpadInvert: Bool
        var fine: Bool
        var sideButtons: Bool
        var middleFold: Bool
        var threeFinger: Bool
        var fourFinger: Bool
        var exceptions: [String]
        var remoteMode: Bool

        static let off = Value(smooth: nil, mouseInvert: false, trackpadInvert: false, fine: false, sideButtons: false,
                                middleFold: false, threeFinger: false, fourFinger: false, exceptions: [], remoteMode: false)
    }

    static func load(from store: UserDefaults) -> Value {
        Value(smooth: preset(store.string(forKey: smoothKey)),
              mouseInvert: store.bool(forKey: mouseDirectionKey),
              trackpadInvert: store.bool(forKey: trackpadDirectionKey),
              fine: store.bool(forKey: fineKey),
              sideButtons: store.bool(forKey: sideKey),
              middleFold: store.bool(forKey: middleKey),
              threeFinger: store.bool(forKey: threeKey),
              fourFinger: store.bool(forKey: fourKey),
              exceptions: store.stringArray(forKey: exceptionsKey) ?? [],
              remoteMode: store.bool(forKey: remoteKey))
    }

    static func save(_ value: Value, to store: UserDefaults) {
        if let smooth = value.smooth { store.set(code(smooth), forKey: smoothKey) }
        else { store.removeObject(forKey: smoothKey) }
        write(value.mouseInvert, key: mouseDirectionKey, store: store)
        write(value.trackpadInvert, key: trackpadDirectionKey, store: store)
        write(value.fine, key: fineKey, store: store)
        write(value.sideButtons, key: sideKey, store: store)
        write(value.middleFold, key: middleKey, store: store)
        write(value.threeFinger, key: threeKey, store: store)
        write(value.fourFinger, key: fourKey, store: store)
        if value.exceptions.isEmpty { store.removeObject(forKey: exceptionsKey) }
        else { store.set(value.exceptions, forKey: exceptionsKey) }
        write(value.remoteMode, key: remoteKey, store: store)
    }

    private static func write(_ on: Bool, key: String, store: UserDefaults) {
        if on { store.set(true, forKey: key) } else { store.removeObject(forKey: key) }
    }

    private static func preset(_ raw: String?) -> SmoothScroll.Preset? {
        switch raw {
        case "light": return .light
        case "medium": return .medium
        case "trackpad": return .trackpadLike
        default: return nil
        }
    }

    private static func code(_ preset: SmoothScroll.Preset) -> String {
        switch preset {
        case .light: return "light"
        case .medium: return "medium"
        case .trackpadLike: return "trackpad"
        }
    }
}
