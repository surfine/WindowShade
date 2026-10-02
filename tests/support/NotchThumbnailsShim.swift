// 只为 NotchThumbnails.swift 的独立测试提供它引用到的三个 App 符号：权限、WindowSnapshot、FastCapture。
// 测试总是自己注入 capture / captureStill / now / permitted，这里只求让它编过。

import CoreGraphics
import Foundation

func hasScreenRecordingPermission() -> Bool { true }

enum WindowSnapshot {
    enum Quality {
        case thumbnail
        case full
    }

    static func image(_ id: CGWindowID, quality: Quality) -> CGImage? { nil }

    static func downscaled(_ image: CGImage, maxPixel: Int) -> CGImage? { image }
}

enum FastCapture {
    static func window(_ id: CGWindowID) -> CGImage? { nil }
}
