// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Darwin
// 只检查动态库是否存在，不把历史头文件冒充 macOS 27 的安全 ABI。
final class MultitouchLibrary {
    private let handle: UnsafeMutableRawPointer
    init?() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
                             RTLD_NOW | RTLD_LOCAL) else { return nil }
        handle = h
    }
    func hasSymbol(_ name: String) -> Bool { dlsym(handle, name) != nil }
    deinit { dlclose(handle) } // 注册回调的正式桥必须先 stop、unregister、排空。
}
