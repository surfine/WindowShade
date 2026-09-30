// 实时活动用到的符号图（刘海里的活动卡片、负一屏的活动卡片共用）。
// 单独一个文件：只编译启动台的单测也要能画这些符号，不用把整个活动界面带上。

import Cocoa

@MainActor
enum NotchActivitySymbol {
    private static var white: [String: CGImage] = [:]
    static func image(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name == "airdrop" ? "dot.radiowaves.left.and.right" : name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
    }
    static func whiteImage(_ name: String) -> CGImage? {
        if let cached = white[name] { return cached }
        guard let symbol = image(name) else { return nil }
        let rendered = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.setFill(); rect.fill(using: .sourceIn)
            return true
        }
        guard let cg = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        if white.count < 20 { white[name] = cg }
        return cg
    }
}
