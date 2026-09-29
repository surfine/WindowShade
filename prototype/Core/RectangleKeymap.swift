// Rectangle 的键位：让用惯 Rectangle 的人不用重新记快捷键。
// 这里只做“账本”：记下 Rectangle 默认的两套键位（推荐 / Spectacle），
// 再照着它的偏好设置或导出的 RectangleConfig.json 算出它现在实际用的是哪一套。
// 纯逻辑，不读盘、不碰窗口。

import Foundation

/// Rectangle 的动作名（就是它存在偏好设置里的键名）。
enum RectangleCommand: String, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case maximize, maximizeHeight, larger, smaller, center, restore
    case nextDisplay, previousDisplay

    /// Raycast 里同一件事的命令名（English, used as search aliases).
    var raycastName: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left Quarter"
        case .topRight: return "Top Right Quarter"
        case .bottomLeft: return "Bottom Left Quarter"
        case .bottomRight: return "Bottom Right Quarter"
        case .firstThird: return "First Third"
        case .centerThird: return "Center Third"
        case .lastThird: return "Last Third"
        case .firstTwoThirds: return "First Two Thirds"
        case .lastTwoThirds: return "Last Two Thirds"
        case .maximize: return "Maximize"
        case .maximizeHeight: return "Maximize Height"
        case .larger: return "Make Larger"
        case .smaller: return "Make Smaller"
        case .center: return "Center"
        case .restore: return "Restore"
        case .nextDisplay: return "Next Display"
        case .previousDisplay: return "Previous Display"
        }
    }
}

struct KeyCombo: Equatable, Hashable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
}

enum RectangleKeymap {
    static let domain = "com.knollsoft.Rectangle"

    // Carbon 修饰键位（0x0100 等），照着写下来，不 import Carbon。
    private static let cmdBit: UInt32 = 0x0100
    private static let shiftBit: UInt32 = 0x0200
    private static let optionBit: UInt32 = 0x0800
    private static let controlBit: UInt32 = 0x1000

    // Cocoa NSEvent.ModifierFlags 的原始位；其余位（caps lock、numericPad、function、低 16 位）一概不管。
    private static let cocoaShift: UInt = 0x20000
    private static let cocoaControl: UInt = 0x40000
    private static let cocoaOption: UInt = 0x80000
    private static let cocoaCommand: UInt = 0x100000

    // 虚拟键码。
    private static let keyLeft: UInt32 = 123
    private static let keyRight: UInt32 = 124
    private static let keyDown: UInt32 = 125
    private static let keyUp: UInt32 = 126
    private static let keyReturn: UInt32 = 36
    private static let keyDelete: UInt32 = 51
    private static let keyEqual: UInt32 = 24
    private static let keyMinus: UInt32 = 27
    private static let keyC: UInt32 = 8
    private static let keyD: UInt32 = 2
    private static let keyE: UInt32 = 14
    private static let keyF: UInt32 = 3
    private static let keyG: UInt32 = 5
    private static let keyT: UInt32 = 17
    private static let keyJ: UInt32 = 38
    private static let keyK: UInt32 = 40
    private static let keyU: UInt32 = 32
    private static let keyI: UInt32 = 34

    /// Cocoa 的修饰键位换 Carbon 的；不认识的位置零。
    static func carbonModifiers(fromCocoa flags: UInt) -> UInt32 {
        var out: UInt32 = 0
        if flags & cocoaCommand != 0 { out |= cmdBit }
        if flags & cocoaShift != 0 { out |= shiftBit }
        if flags & cocoaOption != 0 { out |= optionBit }
        if flags & cocoaControl != 0 { out |= controlBit }
        return out
    }

    /// Rectangle 首次打开选“推荐”时的一套（its `alternateDefault`, all ⌃⌥）。
    static func recommended(_ c: RectangleCommand) -> KeyCombo? {
        let both = controlBit | optionBit
        switch c {
        case .leftHalf: return KeyCombo(keyCode: keyLeft, carbonModifiers: both)
        case .rightHalf: return KeyCombo(keyCode: keyRight, carbonModifiers: both)
        case .bottomHalf: return KeyCombo(keyCode: keyDown, carbonModifiers: both)
        case .topHalf: return KeyCombo(keyCode: keyUp, carbonModifiers: both)
        case .bottomLeft: return KeyCombo(keyCode: keyJ, carbonModifiers: both)
        case .bottomRight: return KeyCombo(keyCode: keyK, carbonModifiers: both)
        case .topLeft: return KeyCombo(keyCode: keyU, carbonModifiers: both)
        case .topRight: return KeyCombo(keyCode: keyI, carbonModifiers: both)
        case .maximize: return KeyCombo(keyCode: keyReturn, carbonModifiers: both)
        case .maximizeHeight: return KeyCombo(keyCode: keyUp, carbonModifiers: both | shiftBit)
        case .previousDisplay: return KeyCombo(keyCode: keyLeft, carbonModifiers: both | cmdBit)
        case .nextDisplay: return KeyCombo(keyCode: keyRight, carbonModifiers: both | cmdBit)
        case .larger: return KeyCombo(keyCode: keyEqual, carbonModifiers: both)
        case .smaller: return KeyCombo(keyCode: keyMinus, carbonModifiers: both)
        case .center: return KeyCombo(keyCode: keyC, carbonModifiers: both)
        case .restore: return KeyCombo(keyCode: keyDelete, carbonModifiers: both)
        case .firstThird: return KeyCombo(keyCode: keyD, carbonModifiers: both)
        case .firstTwoThirds: return KeyCombo(keyCode: keyE, carbonModifiers: both)
        case .centerThird: return KeyCombo(keyCode: keyF, carbonModifiers: both)
        case .lastTwoThirds: return KeyCombo(keyCode: keyT, carbonModifiers: both)
        case .lastThird: return KeyCombo(keyCode: keyG, carbonModifiers: both)
        }
    }

    /// 选“Spectacle”时的一套 (its `spectacleDefault`)。
    static func spectacle(_ c: RectangleCommand) -> KeyCombo? {
        let cmdAlt = cmdBit | optionBit
        let ctrlAlt = controlBit | optionBit
        let cmdCtrlShift = cmdBit | controlBit | shiftBit
        let ctrlCmd = controlBit | cmdBit
        switch c {
        case .leftHalf: return KeyCombo(keyCode: keyLeft, carbonModifiers: cmdAlt)
        case .rightHalf: return KeyCombo(keyCode: keyRight, carbonModifiers: cmdAlt)
        case .maximize: return KeyCombo(keyCode: keyF, carbonModifiers: cmdAlt)
        case .maximizeHeight: return KeyCombo(keyCode: keyUp, carbonModifiers: ctrlAlt | shiftBit)
        case .previousDisplay: return KeyCombo(keyCode: keyLeft, carbonModifiers: ctrlAlt | cmdBit)
        case .nextDisplay: return KeyCombo(keyCode: keyRight, carbonModifiers: ctrlAlt | cmdBit)
        case .larger: return KeyCombo(keyCode: keyRight, carbonModifiers: ctrlAlt | shiftBit)
        case .smaller: return KeyCombo(keyCode: keyLeft, carbonModifiers: ctrlAlt | shiftBit)
        case .bottomHalf: return KeyCombo(keyCode: keyDown, carbonModifiers: cmdAlt)
        case .topHalf: return KeyCombo(keyCode: keyUp, carbonModifiers: cmdAlt)
        case .center: return KeyCombo(keyCode: keyC, carbonModifiers: cmdAlt)
        case .bottomLeft: return KeyCombo(keyCode: keyLeft, carbonModifiers: cmdCtrlShift)
        case .bottomRight: return KeyCombo(keyCode: keyRight, carbonModifiers: cmdCtrlShift)
        case .topLeft: return KeyCombo(keyCode: keyLeft, carbonModifiers: ctrlCmd)
        case .topRight: return KeyCombo(keyCode: keyRight, carbonModifiers: ctrlCmd)
        case .restore: return KeyCombo(keyCode: keyDelete, carbonModifiers: ctrlAlt)
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds: return nil
        }
    }

    /// 推荐那一套整张表（有键位的才收）。
    static var recommendedSet: [RectangleCommand: KeyCombo] {
        var out: [RectangleCommand: KeyCombo] = [:]
        for c in RectangleCommand.allCases {
            if let combo = recommended(c) { out[c] = combo }
        }
        return out
    }

    /// 照着 Rectangle 偏好域里的字典算出它现在实际用的是哪套键位
    /// （~/Library/Preferences/com.knollsoft.Rectangle.plist 的内容，读成 [String: Any]）。
    static func resolve(preferences: [String: Any]) -> [RectangleCommand: KeyCombo] {
        let useRecommended = preferences["alternateDefaultShortcuts"] as? Bool == true
        func fallback(_ c: RectangleCommand) -> KeyCombo? {
            useRecommended ? recommended(c) : spectacle(c)
        }
        var out: [RectangleCommand: KeyCombo] = [:]
        for c in RectangleCommand.allCases {
            guard let value = preferences[c.rawValue] else {
                if let combo = fallback(c) { out[c] = combo }
                continue
            }
            guard let dict = value as? [String: Any] else {
                // 存的不是字典，坏了，照默认走。
                if let combo = fallback(c) { out[c] = combo }
                continue
            }
            if dict.isEmpty { continue }  // 空字典：用户自己清掉了，不算。
            guard let code = number(dict["keyCode"]), code >= 0,
                  let flags = flagsValue(dict["modifierFlags"]) else {
                if let combo = fallback(c) { out[c] = combo }
                continue
            }
            out[c] = KeyCombo(keyCode: UInt32(code), carbonModifiers: carbonModifiers(fromCocoa: flags))
        }
        return out
    }

    /// 照着 Rectangle 导出的 RectangleConfig.json 算：顶层对象里有 "shortcuts"：
    /// { "<名字>": {"keyCode": Int, "modifierFlags": UInt} }（bundleId、version、defaults 之类一概不管）。
    /// 只收出现且 keyCode >= 0 的已知动作；数据不是带 shortcuts 的 JSON 对象就返回 nil。
    /// 用 JSONSerialization 而不是 Codable，多出来的怪字段不会把解码弄崩。
    static func resolve(configJSON: Data) -> [RectangleCommand: KeyCombo]? {
        guard let object = try? JSONSerialization.jsonObject(with: configJSON),
              let root = object as? [String: Any],
              let shortcuts = root["shortcuts"] as? [String: Any] else { return nil }
        var out: [RectangleCommand: KeyCombo] = [:]
        for (name, value) in shortcuts {
            guard let c = RectangleCommand(rawValue: name),
                  let dict = value as? [String: Any],
                  let code = number(dict["keyCode"]), code >= 0 else { continue }
            let flags = flagsValue(dict["modifierFlags"]) ?? 0
            out[c] = KeyCombo(keyCode: UInt32(code), carbonModifiers: carbonModifiers(fromCocoa: flags))
        }
        return out
    }

    // 从偏好里的 Any 取整数（Swift Int 和 NSNumber 都认）。
    private static func number(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    // 从偏好里的 Any 取修饰键原始位（UInt / Int / NSNumber 都认）。
    private static func flagsValue(_ value: Any?) -> UInt? {
        if let n = value as? UInt { return n }
        if let n = value as? Int, n >= 0 { return UInt(n) }
        if let n = value as? NSNumber { return n.uintValue }
        return nil
    }
}
