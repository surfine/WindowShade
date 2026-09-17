// 面板排版统一跟随系统字号：字体系列、字号和派生出的文本高度都不写死，
// 系统文本尺寸变化时优先让文本保持可读（配合滚动与列数收缩）。

import Cocoa

enum WindowBrowserTypography {
    /// 正文字号（macOS 默认为 13pt；系统文本尺寸设置会改变它）。
    static var bodySize: CGFloat { NSFont.systemFontSize }
    /// 次要说明字号，最小 9pt，避免在大字号下反而缩得不可读。
    static var detailSize: CGFloat { max(9, bodySize - 2) }

    static var body: NSFont { .systemFont(ofSize: bodySize) }
    static var detail: NSFont { .systemFont(ofSize: detailSize) }
    static var title: NSFont { .systemFont(ofSize: bodySize, weight: .medium) }
    static var header: NSFont { .systemFont(ofSize: bodySize, weight: .semibold) }
    static var control: NSFont { .systemFont(ofSize: detailSize) }
    static var monospacedDigits: NSFont {
        .monospacedDigitSystemFont(ofSize: bodySize, weight: .regular)
    }

    /// 文本行高向上取整，避免 Retina 下半像素被裁掉。
    static func lineHeight(_ font: NSFont) -> CGFloat {
        max(11, ceil(font.ascender - font.descender + font.leading))
    }
}
