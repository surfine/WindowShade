import Cocoa

/// 测生产测量入口使用的遮挡集合。真实面板留在屏幕外；不启动产品，不读用户菜单或窗口。
@main enum MenuBarObstructionTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var failures = 0
        func expect(_ value: Bool, _ message: String) {
            print("\(value ? "ok" : "FAIL") \(message)")
            if !value { failures += 1 }
        }
        let below = NotchPanel(notch: NSRect(x: -8000, y: -24, width: 190, height: 24), virtual: true)
        let above = NotchPanel(notch: NSRect(x: -8500, y: 1800, width: 190, height: 24), virtual: true)
        below.isReleasedWhenClosed = false
        above.isReleasedWhenClosed = false
        defer { below.close(); above.close() }
        expect(!below.isVisible && !above.isVisible, "夹具为实际隐藏的顶部胶囊面板")
        expect(MenuBarRoom.obstructionFrames(in: [below, above]).isEmpty,
               "隐藏胶囊不把菜单栏测量打成 covered，无论顶部坐标正负")
        below.orderFrontRegardless()
        expect(below.isVisible, "本次自有面板可以进入可见状态")
        expect(MenuBarRoom.obstructionFrames(in: [below, above]) == [below.frame],
               "可见的不透明面板仍挡测量，隐藏的另一块屏不挡")
        below.alphaValue = 0
        expect(MenuBarRoom.obstructionFrames(in: [below]).isEmpty, "透明的自有面板不挡测量")
        below.alphaValue = 1
        below.orderOut(nil)
        expect(MenuBarRoom.obstructionFrames(in: [below]).isEmpty, "收回之后不留下幽灵遮挡")
        let unrelated = NSWindow(contentRect: NSRect(x: -9000, y: -24, width: 300, height: 80),
                                 styleMask: .borderless, backing: .buffered, defer: false)
        unrelated.isReleasedWhenClosed = false
        expect(MenuBarRoom.obstructionFrames(in: [unrelated]).isEmpty, "其他窗口不进入自有刘海遮挡集合")
        unrelated.close()
        print("\(failures == 0 ? "PASS" : "FAIL") MenuBarObstructionTests: 7 checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
