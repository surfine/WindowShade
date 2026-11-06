// 平台能力：哪些功能这个构建根本不带。唯一一处判断，各入口都问这里，不各自写 #if。
//
// 从 1.0.21 起 Intel（x86_64）另发一个实验版 zip（和 arm64 分开，见 docs/DEVELOPMENT.md「Intel 实验版」）。
// 三样东西在 Intel 上整块关掉并且不出现：刷脸解锁（含人脸识别、录脸校准、补光圈）、声纹、合盖桌面效果
// （含合盖角度传感器和锁屏开合效果）。关掉的意思是：控制器不启动、设置行与教程不列、菜单不显示；
// 偏好里已存的“开”不读、也不删（同一份偏好以后换到 arm64 版上照旧）。
//
// 判断用编译期的 `#if arch(x86_64)`，不用运行时探测：arm64 的包在 Rosetta 下不会被当成 Intel，
// Intel 的包在 Rosetta 下跑在 Apple Silicon 上时照样按 Intel 关掉。arm64 构建里每个入口的行为和以前逐字节相同。
// 纯逻辑，不读设置；`intelBuild` 参数只给单测用来在 arm64 机器上也能钉住 Intel 那一支。

import Foundation

enum PlatformSupport {
    /// 在 Intel 上整块关掉的功能。
    enum Feature: String, CaseIterable, Sendable {
        /// 刷脸解锁（实验）：人脸识别、录脸与注视校准、补光圈、锁屏上的「认你」指示、代填登录密码。
        case faceUnlock
        /// 声纹（说话人比对）：只作刷脸解锁的辅助。
        case voiceprint
        /// 合盖桌面效果：合盖角度传感器、桌面开合、锁屏开合效果。
        case lidEffect
    }

    /// 这个构建是不是 Intel（x86_64）。编译期常量。
    static var isIntelBuild: Bool {
        #if arch(x86_64)
        return true
        #else
        return false
        #endif
    }

    /// 这个构建带不带这项功能。
    static func isAvailable(_ feature: Feature, intelBuild: Bool = PlatformSupport.isIntelBuild) -> Bool {
        switch feature {
        case .faceUnlock, .voiceprint, .lidEffect: return !intelBuild
        }
    }

    /// 开发探针的命令行开关：这些探针要起的东西在 Intel 上不带，直接拒绝，免得半路把相机或传感器拉起来。
    static func probeFlags(for feature: Feature) -> [String] {
        switch feature {
        case .faceUnlock:
            return ["--face-calibration-import", "--face-enrollment-probe", "--face-calibrate-record",
                    "--face-fill-light-probe", "--face-scan-page-probe"]
        case .voiceprint: return []
        case .lidEffect: return ["--duo-desktop-demo", "--duo-soak-test"]
        }
    }

    /// 命令行里第一个这个构建不带的探针开关；没有就是 nil（arm64 上永远是 nil）。
    static func unsupportedFlag(in arguments: [String], intelBuild: Bool = PlatformSupport.isIntelBuild) -> String? {
        for feature in Feature.allCases where !isAvailable(feature, intelBuild: intelBuild) {
            if let flag = probeFlags(for: feature).first(where: arguments.contains) { return flag }
        }
        return nil
    }

    static var faceUnlock: Bool { isAvailable(.faceUnlock) }
    static var voiceprint: Bool { isAvailable(.voiceprint) }
    static var lidEffect: Bool { isAvailable(.lidEffect) }
}
