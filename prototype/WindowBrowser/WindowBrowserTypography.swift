// 面板排版统一跟随系统字号：字体系列、字号和派生出的文本高度都不写死，
// 系统文本尺寸变化时优先让文本保持可读（配合滚动与列数收缩）。

import Cocoa

enum WindowBrowserTypography {
    /// 正文字号：跟随系统“文字大小”偏好（macOS 14+ 可以按 App 单独调大），
    /// 默认仍是 13pt。用 preferredFont 而不是写死 13，调大字号的用户同样能读清。
    static var bodySize: CGFloat {
        NSFont.preferredFont(forTextStyle: .body).pointSize
    }
    /// 次要说明字号，最小 10pt（HIG《Accessibility》：macOS 最小字号 10 pt）。
    static var detailSize: CGFloat { max(10, bodySize - 2) }

    static var body: NSFont { .systemFont(ofSize: bodySize) }
    static var detail: NSFont { .systemFont(ofSize: detailSize) }
    static var title: NSFont { .systemFont(ofSize: bodySize, weight: .medium) }
    static var header: NSFont { .systemFont(ofSize: bodySize, weight: .semibold) }
    static var control: NSFont { .systemFont(ofSize: detailSize) }
    static var monospacedDigits: NSFont {
        .monospacedDigitSystemFont(ofSize: bodySize, weight: .regular)
    }

    /// 指定字号下的行高（测试可以注入更大字号验证布局随之增长）。
    static func lineHeight(forBodySize size: CGFloat) -> CGFloat {
        max(11, ceil(NSFont.systemFont(ofSize: size).ascender
                     - NSFont.systemFont(ofSize: size).descender
                     + NSFont.systemFont(ofSize: size).leading))
    }

    /// 文本行高向上取整，避免 Retina 下半像素被裁掉。
    static func lineHeight(_ font: NSFont) -> CGFloat {
        max(11, ceil(font.ascender - font.descender + font.leading))
    }
}
