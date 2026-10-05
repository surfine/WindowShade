// 恢复日志字段专用解析（R01）：坏值拒绝，不截断、不陷阱；负停车坐标保留。
// 纯 Foundation，可供单测与救援后台 nonisolated 路径共用。

import Foundation
import CoreGraphics

enum JournalNumeric {
    /// 布尔 NSNumber 一律拒绝（NSNumber(true) 的 doubleValue 是 1）。
    static func rejectBoolean(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        // Swift `NSNumber(value: true)` 常见为 objCType "c"/"B"，不一定是 CFBoolean 桥。
        let type = String(cString: number.objCType)
        if type == "B" { return nil }
        if type == "c" || type == "C" {
            let bit = number.intValue
            if bit == 0 || bit == 1 { return nil }
        }
        return number
    }

    /// 有限浮点：坐标、时间戳中间态。
    static func finite(_ value: Any?) -> Double? {
        // 先处理 NSNumber：不可用 `is Bool`（NSNumber(1) 会桥成 Bool）。
        // 布尔 NSNumber 拒绝后不得再桥成 Double/Int。
        if value is NSNumber {
            guard let number = rejectBoolean(value) else { return nil }
            let result = number.doubleValue
            return result.isFinite ? result : nil
        }
        if value is Bool { return nil }
        if let d = value as? Double { return d.isFinite ? d : nil }
        if let i = value as? Int { return Double(i) }
        if let i = value as? Int64 { return Double(i) }
        return nil
    }

    /// 精确非零 UInt32（窗口 id / 显示器 id）。
    static func exactUInt32(_ value: Any?) -> UInt32? {
        if value is NSNumber {
            guard let number = rejectBoolean(value) else { return nil }
            let raw = number.doubleValue
            guard raw.isFinite, let id = UInt32(exactly: raw), id != 0 else { return nil }
            return id
        }
        if value is Bool { return nil }
        if let i = value as? Int, let id = UInt32(exactly: i), id != 0 { return id }
        if let u = value as? UInt32, u != 0 { return u }
        if let d = value as? Double, d.isFinite, let id = UInt32(exactly: d), id != 0 { return id }
        return nil
    }

    static func windowID(_ value: Any?) -> CGWindowID? {
        exactUInt32(value).map { CGWindowID($0) }
    }

    static func displayID(_ value: Any?) -> CGDirectDisplayID? {
        exactUInt32(value).map { CGDirectDisplayID($0) }
    }

    /// Space：新格式精确整数；旧 Double 仅当可无损还原为 UInt64。
    static func spaceID(_ value: Any?) -> UInt64? {
        if value is NSNumber {
            guard let number = rejectBoolean(value) else { return nil }
            if let fromDouble = UInt64(exactly: number.doubleValue), number.doubleValue.isFinite {
                return fromDouble
            }
            if let parsed = UInt64(number.stringValue) { return parsed }
            return nil
        }
        if value is Bool { return nil }
        if let u = value as? UInt64 { return u }
        if let i = value as? Int, i >= 0 { return UInt64(i) }
        if let i = value as? Int64, i >= 0 { return UInt64(i) }
        if let d = value as? Double, d.isFinite, let exact = UInt64(exactly: d) { return exact }
        if let s = value as? String, let parsed = UInt64(s) { return parsed }
        return nil
    }

    /// 坐标：有限即可（含负停车点）。
    static func coordinate(_ value: Any?) -> CGFloat? {
        guard let raw = finite(value) else { return nil }
        return CGFloat(raw)
    }

    /// 宽高：有限且为正。
    static func positiveSize(_ value: Any?) -> CGFloat? {
        guard let raw = finite(value), raw > 0 else { return nil }
        return CGFloat(raw)
    }

    /// Alpha：有限且在 0…1。
    static func alpha(_ value: Any?) -> Float? {
        guard let raw = finite(value), raw >= 0, raw <= 1 else { return nil }
        return Float(raw)
    }

    /// 时间戳：有限；异常遥远的未来视为未知（返回 nil，调用方用 now）。
    static func timestamp(_ value: Any?, now: TimeInterval = Date().timeIntervalSince1970) -> TimeInterval? {
        guard let raw = finite(value), raw >= 0, raw <= now + 86_400 * 365 else { return nil }
        return raw
    }

    /// 日志用：有限坐标格式化，避免 Int(NaN) 陷阱。
    static func formatPoint(_ point: CGPoint) -> String {
        let x = point.x.isFinite ? String(Int(point.x.rounded())) : "nan"
        let y = point.y.isFinite ? String(Int(point.y.rounded())) : "nan"
        return "(\(x),\(y))"
    }

    /// 从条目解析救援几何；坏 display/alpha 使整条不可用（由调用方隔离，不删）。
    struct RescueGeometry: Equatable {
        var origin: CGPoint
        var size: CGSize
        var displayID: CGDirectDisplayID?
        var alpha: Float?
    }

    static func rescueGeometry(
        _ entry: [String: Any],
        fallbackOrigin: CGPoint,
        fallbackSize: CGSize
    ) -> RescueGeometry? {
        let x = coordinate(entry["originalX"]) ?? fallbackOrigin.x
        let y = coordinate(entry["originalY"]) ?? fallbackOrigin.y
        guard x.isFinite, y.isFinite else { return nil }
        let width = positiveSize(entry["originalWidth"]) ?? fallbackSize.width
        let height = positiveSize(entry["originalHeight"]) ?? fallbackSize.height
        guard width > 1, height > 1, width.isFinite, height.isFinite else { return nil }
        let display: CGDirectDisplayID?
        if entry["displayID"] == nil {
            display = nil
        } else if let id = displayID(entry["displayID"]) {
            display = id
        } else {
            return nil
        }
        var alphaValue: Float?
        if entry["originalAlpha"] != nil {
            guard let a = alpha(entry["originalAlpha"]) else { return nil }
            alphaValue = a
        }
        return RescueGeometry(
            origin: CGPoint(x: x, y: y),
            size: CGSize(width: width, height: height),
            displayID: display,
            alpha: alphaValue
        )
    }
}
