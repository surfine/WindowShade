// 缩略图读取顺序的纯决策：权限与排除 → 已有折叠快照 → 正在运行的置顶镜像 →
// 单窗截图 → 应用图标与说明。折叠/最小化窗口不为刷新缩略图而展开或唤醒，
// 没有已保存画面时宁可显示图标。

import Foundation

enum WindowBrowserThumbnailSource: String, Equatable {
    case cachedFoldSnapshot
    case pinnedMirror
    case liveStream
    case singleWindowCapture
    case applicationIcon
}

struct WindowBrowserThumbnailInputs: Equatable {
    var isExcluded = false
    var isFolded = false
    var hasCachedFoldImage = false
    var isMinimized = false
    var pinnedStreamRunning = false
    var pinnedSuspended = false
    var livePreviewEnabled = false
    var isSelected = false
    var canCapture = false
    var hasScreenRecording = false
}

enum WindowBrowserThumbnailPolicy {
    static func source(_ inputs: WindowBrowserThumbnailInputs) -> WindowBrowserThumbnailSource {
        guard !inputs.isExcluded else { return .applicationIcon }
        if inputs.isFolded {
            // 折叠窗口优先使用已保存的最后有效画面；没有就显示图标，不为了缩略图展开它。
            return inputs.hasCachedFoldImage ? .cachedFoldSnapshot : .applicationIcon
        }
        if inputs.isMinimized {
            // 最小化窗口没有可用的保存画面时不唤醒它。
            return .applicationIcon
        }
        if inputs.pinnedSuspended {
            // 暂停中的置顶会话不提供帧，也不为缩略图偷偷恢复/另建流。
            return .applicationIcon
        }
        if inputs.pinnedStreamRunning {
            // 镜像只有一路：仅当前选中项接入；其他项回落到单窗静态截图。
            return inputs.isSelected ? .pinnedMirror : .singleWindowCapture
        }
        guard inputs.hasScreenRecording, inputs.canCapture else { return .applicationIcon }
        if inputs.livePreviewEnabled, inputs.isSelected {
            return .liveStream
        }
        return .singleWindowCapture
    }
}

enum WindowBrowserThumbnailSubscriptionPolicy {
    /// 已有订阅时是否需要替换：档位变化（或档位未知）就必须换，否则复用。
    static func needsReplace(existingPurpose: WindowThumbnailPurpose?,
                             desired: WindowThumbnailPurpose) -> Bool {
        guard let existingPurpose else { return true }
        return existingPurpose != desired
    }
}
