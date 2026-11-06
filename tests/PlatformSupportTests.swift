import Foundation

// 平台能力：Intel 版不带刷脸解锁、声纹、合盖效果。谓词、功能目录的过滤、探针开关都在 arm64 机器上用显式参数钉住。

@main
struct PlatformSupportTests {
    static func main() {
        // 谓词：Intel 三样都没有；arm64 三样都有。
        for feature in PlatformSupport.Feature.allCases {
            precondition(!PlatformSupport.isAvailable(feature, intelBuild: true), "\(feature) must be off on Intel")
            precondition(PlatformSupport.isAvailable(feature, intelBuild: false), "\(feature) must be on for arm64")
        }
        precondition(PlatformSupport.Feature.allCases.count == 3, "new platform feature needs a test line here")

        // 本构建的编译期常量：#if arch(x86_64) 与谓词一致。
        #if arch(x86_64)
        precondition(PlatformSupport.isIntelBuild && !PlatformSupport.faceUnlock && !PlatformSupport.voiceprint && !PlatformSupport.lidEffect)
        #else
        precondition(!PlatformSupport.isIntelBuild && PlatformSupport.faceUnlock && PlatformSupport.voiceprint && PlatformSupport.lidEffect)
        #endif

        // 功能目录：arm64 上子项一个不少，副标题不变；Intel 上刷脸、合盖相关子项消失，副标题换成不提它们的那句。
        let security = FeatureCatalog.definition(.securityExtras)
        let effects = FeatureCatalog.definition(.effects)
        precondition(security.availableSubfeatures(intelBuild: false).map(\.key) == security.subfeatures.map(\.key))
        precondition(effects.availableSubfeatures(intelBuild: false).map(\.key) == effects.subfeatures.map(\.key))
        precondition(security.shownSubtitle(intelBuild: false) == security.subtitle)
        precondition(effects.shownSubtitle(intelBuild: false) == effects.subtitle)

        precondition(security.availableSubfeatures(intelBuild: true).map(\.key)
                     == ["Presence.lock.enabled", "Privacy.bystanderCover.enabled"])
        precondition(effects.availableSubfeatures(intelBuild: true).map(\.key) == ["duo.v2.windows"])
        precondition(security.shownSubtitle(intelBuild: true) != security.subtitle)
        precondition(effects.shownSubtitle(intelBuild: true) != effects.subtitle)
        precondition(!security.shownSubtitle(intelBuild: true).zh.contains("刷脸"))
        precondition(!effects.shownSubtitle(intelBuild: true).zh.contains("合盖"))

        // 其余模块不受影响：没有依赖平台的子项，也不换副标题。
        for definition in FeatureCatalog.all where definition.module != .securityExtras && definition.module != .effects {
            precondition(definition.availableSubfeatures(intelBuild: true).count == definition.subfeatures.count)
            precondition(definition.shownSubtitle(intelBuild: true) == definition.subtitle)
        }
        // 受限子项只有这三个键。
        let gated = FeatureCatalog.all.flatMap(\.subfeatures).filter { $0.requires != nil }.map(\.key).sorted()
        precondition(gated == ["FaceScan.experiment.enabled", "duo.v2.desktop", "lockOverlay.enabled"], "gated keys: \(gated)")

        // 升级迁移：Intel 上存着的刷脸、合盖“开”不参与模块总闸的判断；arm64 照旧。
        let suite = "PlatformSupportTests.upgrade"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "FaceScan.experiment.enabled")
        defaults.set(true, forKey: "duo.v2.desktop")
        defaults.set(false, forKey: "duo.v2.windows")
        func anyOn(_ definition: FeatureDefinition, intel: Bool) -> Bool {
            definition.availableSubfeatures(intelBuild: intel).contains { sub in
                (defaults.object(forKey: sub.key) as? Bool) ?? sub.defaultWhenUnset
            }
        }
        precondition(anyOn(security, intel: false) && anyOn(effects, intel: false))
        precondition(!anyOn(security, intel: true) && !anyOn(effects, intel: true))
        // 目录读写不删用户的值。
        precondition(defaults.bool(forKey: "FaceScan.experiment.enabled") && defaults.bool(forKey: "duo.v2.desktop"))
        defaults.removePersistentDomain(forName: suite)

        // 探针开关：Intel 上拒绝刷脸、合盖的探针，其它探针放行；arm64 什么都不拒。
        precondition(PlatformSupport.unsupportedFlag(in: ["--face-enrollment-probe"], intelBuild: true) == "--face-enrollment-probe")
        precondition(PlatformSupport.unsupportedFlag(in: ["--duo-desktop-demo"], intelBuild: true) == "--duo-desktop-demo")
        precondition(PlatformSupport.unsupportedFlag(in: ["--duo-window-test", "--glance-probe"], intelBuild: true) == nil)
        for feature in PlatformSupport.Feature.allCases {
            for flag in PlatformSupport.probeFlags(for: feature) {
                precondition(PlatformSupport.unsupportedFlag(in: [flag], intelBuild: false) == nil)
            }
        }

        print("PlatformSupportTests ok")
    }
}
