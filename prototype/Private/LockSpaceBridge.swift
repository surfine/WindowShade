import Cocoa
import Darwin

/// Recipe from jonnyoo/glance (Jonathan Zhou, MIT) and Lakr233/SkyLightWindow
/// (Lakr Aream, MIT). Isolated to our own noninteractive windows. No login operation.
final class LockSpaceBridge {
    private typealias Main = @convention(c) () -> Int32
    private typealias Create = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias Level = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias Spaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias Add = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private typealias Remove = @convention(c) (Int32, CFArray, CFArray) -> Int32
    private let handle: UnsafeMutableRawPointer
    private let main: Main
    private let create: Create
    private let level: Level
    private let show: Spaces
    private let hide: Spaces
    private let add: Add
    private let remove: Remove
    private var space: Int32?
    private var connection: Int32 = 0
    private var windows: Set<Int> = []
    private var unavailable = false

    init?() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW | RTLD_LOCAL) else { return nil }
        let names = ["SLSMainConnectionID", "SLSSpaceCreate", "SLSSpaceSetAbsoluteLevel", "SLSShowSpaces", "SLSHideSpaces", "SLSSpaceAddWindowsAndRemoveFromSpaces", "SLSRemoveWindowsFromSpaces"]
        let symbols = names.compactMap { dlsym(h, $0) }
        guard symbols.count == names.count else { dlclose(h); return nil }
        handle = h
        main = unsafeBitCast(symbols[0], to: Main.self)
        create = unsafeBitCast(symbols[1], to: Create.self)
        level = unsafeBitCast(symbols[2], to: Level.self)
        show = unsafeBitCast(symbols[3], to: Spaces.self)
        hide = unsafeBitCast(symbols[4], to: Spaces.self)
        add = unsafeBitCast(symbols[5], to: Add.self)
        remove = unsafeBitCast(symbols[6], to: Remove.self)
    }

    func attach(_ panel: NSWindow) -> Bool {
        precondition(Thread.isMainThread)
        // Requery immediately before the private mutation, not just on notification receipt.
        guard !unavailable, EffectSecurityBoundary.lockState == .locked, panel.ignoresMouseEvents,
              !panel.canBecomeKey, !panel.canBecomeMain else { return false }
        if space == nil {
            connection = main()
            guard connection != 0 else { return false }
            let candidate = create(connection, 1, 0)
            guard candidate > 0 else { return false }
            space = candidate // Reuse one process-owned space; do not allocate on every wake.
            guard level(connection, candidate, 400) == 0 else { unavailable = true; return false }
        }
        guard let space, show(connection, [space] as CFArray) == 0 else { return false }
        let number = panel.windowNumber
        guard number > 0 else { return false }
        // Record before calling: a failed/partial private operation still gets removal.
        windows.insert(number)
        let result = add(connection, space, [number] as CFArray, 7)
        guard result == 0, EffectSecurityBoundary.lockState == .locked else {
            detach(panel)
            return false
        }
        return true
    }

    func detach(_ panel: NSWindow) {
        panel.orderOut(nil) // Always hide first, even if undelegation fails.
        guard windows.remove(panel.windowNumber) != nil, let space else { return }
        let result = remove(connection, [panel.windowNumber] as CFArray, [space] as CFArray)
        if result != 0 { NSLog("WindowShade: lock-space removal returned %d", result) }
        if windows.isEmpty { _ = hide(connection, [space] as CFArray) }
    }
    deinit { dlclose(handle) }
}
