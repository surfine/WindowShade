// 独立 LocalAuthentication 小样：默认只查手表能力；可显式选择生物认证能力或应用认证。
// 每个策略独立评估，不用混合 OR 策略，也不存/输入密码。应用认证不能代替系统会话解锁。
// 退出码 0 = 诊断完成/认证成功，1 = 参数错误/认证失败，2 = 超时。

import AppKit
import Foundation
import LocalAuthentication

// MARK: - 退出码约定

enum ProbeExitCode: Int32 {
    case success = 0   // 成功 / 诊断完成
    case failure = 1   // 失败 / 参数错误
    case timeout = 2   // 超时
}

// MARK: - 输出小工具

func log(_ message: String) {
    // 全部走 stdout，保持与 shell 捕获一致；同时 flush 以免被缓冲吞掉。
    print(message)
    fflush(stdout)
}

// MARK: - 参数解析

enum ProbeMode {
    case capabilities
    case authenticate
    case biometricCapabilities
    case biometricAuthenticate
    case help

    var isBiometric: Bool {
        switch self {
        case .biometricCapabilities, .biometricAuthenticate: return true
        default: return false
        }
    }
}

struct OptionsError: Error {
    let message: String
}

func parseOptions(_ args: [String]) throws -> ProbeMode {
    guard args.count <= 1 else {
        throw OptionsError(message: "一次只选择一种模式")
    }
    var mode: ProbeMode = .capabilities
    for arg in args {
        switch arg {
        case "--capabilities":
            mode = .capabilities
        case "--authenticate":
            mode = .authenticate
        case "--biometric-capabilities":
            mode = .biometricCapabilities
        case "--biometric-authenticate":
            mode = .biometricAuthenticate
        case "--help", "-h":
            mode = .help
        default:
            throw OptionsError(message: "未知参数: \(arg)")
        }
    }
    return mode
}

func printUsage() {
    log("""
    WindowShadeCompanionProbe —— Apple Watch / companion 认证能力探针（独立于主 App）

    用法:
      CompanionProbe [--capabilities]   仅查询 canEvaluatePolicy 能力（默认模式）
      CompanionProbe --authenticate     发起一次 only-companion 的 evaluatePolicy 请求
      CompanionProbe --biometric-capabilities  仅查询系统生物认证能力
      CompanionProbe --biometric-authenticate  发起一次仅生物认证的应用请求
      CompanionProbe --help             显示本帮助

    说明:
      * 默认模式不评估任何策略，只输出 OS 版本、所用 policy、available、
        以及 NSError 的 domain/code，用于诊断当前机器/系统是否支持 companion 认证。
      * --authenticate 是「认证应用请求」，不会解锁 macOS，也不代表完整多因素解锁实现。
      * 本工具不摄像、不扫描蓝牙、不改系统设置、不锁屏、不读 Keychain、不存密码。

    退出码:
      0 成功（capabilities 模式下能输出诊断即为成功，available=false 也算诊断成功）
      1 失败（认证失败/报错，或参数错误）
      2 超时（30 秒未回调）

    若 --authenticate 需要 Apple Watch 双击侧键确认，请留意手表提示。
    """)
}

// MARK: - 策略选择

#if canImport(LocalAuthentication)
// macOS 15.0+ 提供 only-companion 策略；否则回退到旧 watch 策略。
#endif

func companionPolicy() -> LAPolicy {
    if #available(macOS 15.0, *) {
        return .deviceOwnerAuthenticationWithCompanion
    } else {
        return .deviceOwnerAuthenticationWithWatch
    }
}

func policyName(_ policy: LAPolicy) -> String {
    if policy == .deviceOwnerAuthenticationWithBiometrics {
        return ".deviceOwnerAuthenticationWithBiometrics"
    }
    // 旧 Watch 名称与 Companion 是同一 rawValue；不能先按旧名称匹配。
    if #available(macOS 15.0, *) {
        if policy == .deviceOwnerAuthenticationWithCompanion {
            return ".deviceOwnerAuthenticationWithCompanion"
        }
    }
    if policy == .deviceOwnerAuthenticationWithWatch {
        return ".deviceOwnerAuthenticationWithWatch"
    }
    return "LAPolicy(rawValue: \(policy.rawValue))"
}

func describe(_ error: Error?) -> String {
    guard let error = error as NSError? else { return "none" }
    return "domain=\(error.domain) code=\(error.code)"
}

func osVersionString() -> String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
}

// MARK: - MainActor 上的 LAContext 管理

@MainActor
final class CompanionProbeController {
    private let mode: ProbeMode
    private var context: LAContext?
    private var timeoutTask: Task<Void, Never>?
    private var finished = false
    private let timeoutSeconds: TimeInterval = 30

    // 唯一 completion 出口：保证成功/失败/超时只走一次。
    private let completion: (ProbeExitCode) -> Void

    init(mode: ProbeMode, completion: @escaping (ProbeExitCode) -> Void) {
        self.mode = mode
        self.completion = completion
    }

    func start() {
        switch mode {
        case .help:
            printUsage()
            finish(.success)
        case .capabilities, .biometricCapabilities:
            runCapabilities()
        case .authenticate, .biometricAuthenticate:
            runAuthenticate()
        }
    }

    private func makeContext() -> LAContext {
        let ctx = LAContext()
        // 明确不依赖密码回退；only-companion 策略本身即不可退化为 Touch ID/密码。
        ctx.localizedFallbackTitle = ""
        ctx.localizedCancelTitle = "取消"
        ctx.touchIDAuthenticationAllowableReuseDuration = 0
        context = ctx
        return ctx
    }

    // ---- 默认模式：只查询能力，不 evaluate ----
    private func runCapabilities() {
        let policy: LAPolicy = mode.isBiometric ? .deviceOwnerAuthenticationWithBiometrics : companionPolicy()
        let ctx = makeContext()

        log("== WindowShade companion 认证能力探针 ==")
        log("模式: \(mode.isBiometric ? "--biometric-capabilities" : "--capabilities")（仅查询，不评估）")
        log("macOS 版本: \(osVersionString())")
        log("使用 policy: \(policyName(policy))")

        var error: NSError?
        let available = ctx.canEvaluatePolicy(policy, error: &error)
        log("available: \(available)")
        log("NSError: \(describe(error))")
        if mode.isBiometric { log("biometryType: \(ctx.biometryType == .touchID ? "Touch ID" : "other/none")") }
        log("说明: 该结果只反映当前策略的能力诊断，")
        log("      available == false 不代表认证失败，只表示当前不可用。")

        // 查询能力后立即 invalidate，避免残留状态。
        ctx.invalidate()
        context = nil
        finish(.success)
    }

    // ---- 显式模式：发起一次 only-companion 评估 ----
    private func runAuthenticate() {
        let policy: LAPolicy = mode.isBiometric ? .deviceOwnerAuthenticationWithBiometrics : companionPolicy()
        let ctx = makeContext()

        log("== WindowShade companion 认证探针 ==")
        log("模式: \(mode.isBiometric ? "--biometric-authenticate" : "--authenticate")（evaluatePolicy）")
        log("macOS 版本: \(osVersionString())")
        log("使用 policy: \(policyName(policy))")
        log("注意: 这只是向系统发起的『认证应用请求』，不会解锁 macOS，")
        log("      也不等同于完整多因素解锁实现。")
        log(mode.isBiometric ? "请留意系统 Touch ID 提示。" : "如果使用 Apple Watch，可能需要在手表上双击侧键确认。")

        var canError: NSError?
        let available = ctx.canEvaluatePolicy(policy, error: &canError)
        log("available: \(available)")
        log("NSError(canEvaluate): \(describe(canError))")

        if !available {
            log("结果: 失败（当前策略不可用，不做 evaluate）")
            ctx.invalidate()
            context = nil
            finish(.failure)
            return
        }

        // 30 秒超时：取消并 invalidate。
        startTimeout()

        // 回调统一切到 MainActor 处理，避免并发竞态。
        let reason = mode.isBiometric ? "请用 Touch ID 确认这次测试。" : "请在 Apple Watch 上确认这次测试。"
        ctx.evaluatePolicy(policy, localizedReason: reason) { success, error in
            Task { @MainActor in
                self.handleEvaluateResult(success: success, error: error)
            }
        }
    }

    private func startTimeout() {
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(self.timeoutSeconds * 1_000_000_000))
            if Task.isCancelled { return }
            self.handleTimeout()
        }
    }

    private func handleTimeout() {
        guard !finished else { return }
        log("结果: 超时（\(Int(timeoutSeconds)) 秒内未收到回调），取消并 invalidate。")
        context?.invalidate()
        context = nil
        finish(.timeout)
    }

    private func handleEvaluateResult(success: Bool, error: Error?) {
        guard !finished else { return }
        timeoutTask?.cancel()
        timeoutTask = nil

        if success {
            log("结果: 成功（系统应用认证请求通过）")
            log("再次提醒: 认证成功仅代表应用认证请求被通过，未解锁 macOS。")
            context?.invalidate()
            context = nil
            finish(.success)
        } else {
            log("结果: 失败")
            log("NSError: \(describe(error))")
            context?.invalidate()
            context = nil
            finish(.failure)
        }
    }

    // 单一出口。
    private func finish(_ code: ProbeExitCode) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        timeoutTask = nil
        completion(code)
    }
}

// MARK: - AppKit accessory 主循环（在 main actor 管理状态）

@MainActor
final class ProbeAppDelegate: NSObject, NSApplicationDelegate {
    let mode: ProbeMode
    private var controller: CompanionProbeController?

    init(mode: ProbeMode) {
        self.mode = mode
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = CompanionProbeController(mode: mode) { code in
            // 结束主循环并以自定义退出码退出。
            // terminate() 会自行以 0 退出，吞掉失败/超时的退出码。
            exit(code.rawValue)
        }
        self.controller = controller
        controller.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - 入口

// 顶层代码默认不在 MainActor 上；用 assumeIsolated 显式进入主 actor。
// 该变量保持 delegate 存活（app.delegate 是 weak 语义）。
var delegateHolder: ProbeAppDelegate?

let rawArgs = Array(CommandLine.arguments.dropFirst())

let mode: ProbeMode
do {
    mode = try parseOptions(rawArgs)
} catch let error as OptionsError {
    FileHandle.standardError.write(Data("错误: \(error.message)\n".utf8))
    FileHandle.standardError.write(Data("用法: CompanionProbe [--capabilities|--authenticate|--biometric-capabilities|--biometric-authenticate|--help]\n".utf8))
    exit(ProbeExitCode.failure.rawValue)
} catch {
    FileHandle.standardError.write(Data("错误: 参数解析失败\n".utf8))
    exit(ProbeExitCode.failure.rawValue)
}

// AppKit accessory 模式：无 Dock 图标、无菜单栏抢占。
// NSApplication 必须在主线程运行；AppKit 入口本身即运行于主线程。
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = ProbeAppDelegate(mode: mode)
    app.delegate = delegate
    delegateHolder = delegate
    app.run()
}
