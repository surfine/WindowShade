// 把别的应用的窗口移到另一张桌面。
//
// SLSMoveWindowsToManagedSpace 从 macOS 14.5 起移不了别的应用的窗口；兼容编号的办法
// 从 macOS 15 起要关掉系统完整性保护。SkyLight 里还有一个内部函数
// SLSPerformAsynchronousBridgedWindowManagementOperation，把一个
// SLSBridgedMoveWindowsToManagedSpaceOperation 交给它，SIP 开着也能移
// （yabai 7.1.25 起用这个办法）。
//
// 这个函数是内部链接的，dlsym 找不到，只能遍历已载入的 SkyLight 映像的符号表。
// 任何一步对不上就返回不可用，调用方保持原来的行为。

import Darwin
import Foundation
import MachO

enum BridgedSpaceMove {
    private typealias PerformFunction = @convention(c) (UnsafeRawPointer) -> Int64
    private typealias AllocFunction = @convention(c) (UnsafeRawPointer, Selector) -> UnsafeRawPointer?
    private typealias InitFunction = @convention(c) (UnsafeRawPointer, Selector, UnsafeRawPointer, UInt64) -> UnsafeRawPointer?
    private typealias ReleaseFunction = @convention(c) (UnsafeRawPointer, Selector) -> Void

    private static let skyLightPath =
        "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
    private static let performSymbol =
        "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation"
    private static let initializerName = "initWithWindows:spaceID:"

    /// 第一次用到时查类、初始化方法和函数地址；任一项缺失就是 nil。
    private static let perform: PerformFunction? = {
        guard let cls = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation"),
              canInitialize(cls),
              let address = findLocalSymbol(image: skyLightPath, name: performSymbol) else { return nil }
        return unsafeBitCast(address, to: PerformFunction.self)
    }()

    /// 类是否响应 initWithWindows:spaceID:，且参数个数正好（self、_cmd、两个参数）。
    /// 这里直接用 objc_msgSend 发消息：以后系统删了方法会抛 unrecognized selector，
    /// 参数个数变了会按错的调用约定调用，所以两项都先查。
    static func canInitialize(_ cls: AnyClass) -> Bool {
        guard let method = class_getInstanceMethod(cls, NSSelectorFromString(initializerName)) else { return false }
        return method_getNumberOfArguments(method) == 4
    }

    static var isAvailable: Bool { perform != nil }

    /// 提交移动请求。返回 true 只说明请求交出去了：这个内部函数是异步的，
    /// 返回时窗口不一定已经换了桌面，调用方要自己核对。
    @discardableResult
    static func move(windows: [UInt32], toSpace sid: UInt64) -> Bool {
        guard let perform,
              let cls = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation"),
              let msgSend = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend") else { return false }
        // 初始化方法带 UInt64，用不了 perform(_:with:)，只能把 objc_msgSend 当 C 函数调。
        let alloc = unsafeBitCast(msgSend, to: AllocFunction.self)
        let initialize = unsafeBitCast(msgSend, to: InitFunction.self)
        let release = unsafeBitCast(msgSend, to: ReleaseFunction.self)
        let list = windows.map { NSNumber(value: $0) } as CFArray
        let classPointer = UnsafeRawPointer(Unmanaged.passUnretained(cls as AnyObject).toOpaque())
        guard let allocated = alloc(classPointer, NSSelectorFromString("alloc")),
              let operation = initialize(allocated, NSSelectorFromString(initializerName),
                                         UnsafeRawPointer(Unmanaged.passUnretained(list).toOpaque()), sid)
        else { return false }
        _ = perform(operation)
        release(operation, NSSelectorFromString("release"))
        withExtendedLifetime(list) {}
        return true
    }

    /// 在已载入的映像里按名字找符号（包括不导出的内部符号），加上 slide 后返回地址。
    static func findLocalSymbol(image path: String, name: String) -> UnsafeRawPointer? {
        // 有的系统版本用带 Versions/A 的完整路径，有的用框架目录下的短路径。
        let paths = [path, path.replacingOccurrences(of: "/Versions/A/", with: "/")]
        for index in 0..<_dyld_image_count() {
            guard let imageName = _dyld_get_image_name(index), paths.contains(String(cString: imageName)),
                  let header = _dyld_get_image_header(index) else { continue }
            let slide = _dyld_get_image_vmaddr_slide(index)
            return findSymbol(header: header, slide: slide, name: name)
        }
        return nil
    }

    private static func findSymbol(header: UnsafePointer<mach_header>, slide: Int, name: String) -> UnsafeRawPointer? {
        guard header.pointee.magic == MH_MAGIC_64 else { return nil }
        var linkedit: segment_command_64?
        var symtab: symtab_command?
        var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<header.pointee.ncmds {
            let load = command.load(as: load_command.self)
            if load.cmd == UInt32(LC_SEGMENT_64) {
                let segment = command.load(as: segment_command_64.self)
                let segname = withUnsafeBytes(of: segment.segname) { raw in
                    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                }
                if segname == "__LINKEDIT" { linkedit = segment }
            } else if load.cmd == UInt32(LC_SYMTAB) {
                symtab = command.load(as: symtab_command.self)
            }
            command = command.advanced(by: Int(load.cmdsize))
        }
        guard let linkedit, let symtab else { return nil }
        let base = Int(linkedit.vmaddr) - Int(linkedit.fileoff) + slide
        guard let strings = UnsafePointer<CChar>(bitPattern: base + Int(symtab.stroff)),
              let symbols = UnsafePointer<nlist_64>(bitPattern: base + Int(symtab.symoff)) else { return nil }
        let target = Array(name.utf8CString)
        for i in 0..<Int(symtab.nsyms) {
            let entry = symbols[i]
            guard entry.n_value != 0 else { continue }
            let candidate = strings.advanced(by: Int(entry.n_un.n_strx))
            if strcmp(candidate, target) == 0 {
                return UnsafeRawPointer(bitPattern: Int(entry.n_value) + slide)
            }
        }
        return nil
    }
}
