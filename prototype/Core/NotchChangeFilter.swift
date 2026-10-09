import Foundation

/// 收起的窗口标题变了，刘海要不要知道。收成缩略图、还摆在原处的，亮点留在缩略图上，刘海不长下巴也不长耳朵。
enum NotchChangeFilter {
    static func hasVisibleChange<S: Sequence>(_ changedIDs: S, isThumbnail: (S.Element) -> Bool) -> Bool {
        changedIDs.contains { !isThumbnail($0) }
    }
}
