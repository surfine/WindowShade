// 系统岛与 ActivityKit 的边界（Phase 4 骨架，默认关闭）。
//
// 27.3 CampoUIInternal 直接链接 ActivityKit，并有 CampoUILiveActivityController、
// LiveActivityMonitoring、LiveActivityRequestMonitor、LiveActivityPresentationWatcher；
// 系统岛是 ActivityKit 的消费端。macOS SDK 里 `canImport(ActivityKit)` 为 true，
// 但 Activity / ActivityAuthorizationInfo 等 API 全标了 `@available(macOS, unavailable)`，
// 所以 WindowShade 不能在编译期发或收 Live Activity。这里只做现在能做对的两件事：
//   1. 运行时探测系统有没有这个框架（给真机 probe 用）；
//   2. 让位策略：系统岛 + ActivityKit 都在时，不再画我们自己的活动耳朵（Aaron #39）。
//
// 默认 inAppOnly：真机 spike 时把 sourceMode 改成 .yieldToSystem 再签一版，
// 不改发布路径。纯逻辑，可单测（tests/run-activitykit-bridge-tests.sh）。

import Foundation

enum ActivityKitBridge {
    /// 编译期能不能 import ActivityKit（模块存在）。注意：能 import 不等于能用。
    static var sdkCanImportFramework: Bool {
        #if canImport(ActivityKit)
        return true
        #else
        return false
        #endif
    }

    /// 发／收 Live Activity 的 API 在 macOS SDK 里全部标了 `@available(macOS, unavailable)`，
    /// 所以对我们永远是 false；留成常量是为了让文档和 probe 说清楚原因。
    static let apiAvailableOnMac = false

    /// 运行时系统是否带 ActivityKit.framework（macOS 27 有）。
    static let frameworkPresent: Bool = FileManager.default.fileExists(
        atPath: "/System/Library/Frameworks/ActivityKit.framework")

    /// 系统岛是不是在替我们呈现 Live Activity。
    static var systemOwnsLiveActivities: Bool { SystemIsland.present && frameworkPresent }

    enum SourceMode: String, Sendable {
        /// 默认：只用 in-app 来源，不接 ActivityKit。
        case inAppOnly
        /// 真机 spike：系统岛呈现时，抑制自己的重复耳朵。
        case yieldToSystem
    }

    /// 编译期开关：默认 inAppOnly。真机 spike 改成 .yieldToSystem 再签一版。
    static let sourceMode: SourceMode = .inAppOnly

    /// 这条活动该不该在我们自己的岛／耳朵上出现。纯函数，便于测试与以后接来源。
    static func shouldPublishOwnEars(systemIslandPresent: Bool, activityKitAvailable: Bool,
                                     mode: SourceMode) -> Bool {
        switch mode {
        case .inAppOnly: return true
        case .yieldToSystem: return !(systemIslandPresent && activityKitAvailable)
        }
    }
}
