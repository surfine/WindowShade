// 可选功能目录：核心之外用户能整块关掉的都在这里；默认值只在这里定、不在界面文案里解释
//（成熟默认开，没打磨好的默认关）。新装按 defaultOnForFreshInstall；升级由 InstallFeatureDefaults 按现有
// 子功能迁移不重置；master 开只代表模块可用，细项仍按各自开关。核心（卷帘、看一眼、带到每张桌面、跨桌面携带、
// 恢复、更新、菜单栏与事件钩子）不在这里，也不允许关。

import Foundation

enum FeatureModule: String, CaseIterable, Sendable {
    case notch
    case windowBrowser
    case launchpad
    case pictureInPicture
    case inputEnhancements
    case securityExtras
    case companion
    case effects
}

struct FeatureDefinition: Sendable {
    struct Subfeature: Sendable {
        let key: String
        let defaultWhenUnset: Bool
        /// 这一项依赖的平台能力；这个构建不带它时，这一项不列、不参与迁移判断（偏好里存的值不读也不删）。
        var requires: PlatformSupport.Feature? = nil
    }

    let module: FeatureModule
    let masterKey: String
    let title: SettingsText
    let subtitle: SettingsText
    /// 新装默认值。只在内部用，不写进任何用户可见文案。
    let defaultOnForFreshInstall: Bool
    /// 升级迁移时用来判断“这个模块现在是否至少有一项开着”。
    let subfeatures: [Subfeature]
    /// 有子项因平台不带而不列时，模块副标题改用这一句（它不再提那几项）。arm64 上永远不用。
    var subtitleWithoutUnavailable: SettingsText? = nil

    /// 这个构建里真的存在的子项。arm64 上就是 subfeatures 全部。
    func availableSubfeatures(intelBuild: Bool = PlatformSupport.isIntelBuild) -> [Subfeature] {
        subfeatures.filter { sub in sub.requires.map { PlatformSupport.isAvailable($0, intelBuild: intelBuild) } ?? true }
    }

    /// 设置 → 功能里这个模块显示的副标题。
    func shownSubtitle(intelBuild: Bool = PlatformSupport.isIntelBuild) -> SettingsText {
        guard let alternative = subtitleWithoutUnavailable,
              availableSubfeatures(intelBuild: intelBuild).count < subfeatures.count else { return subtitle }
        return alternative
    }
}

enum FeatureCatalog {
    static let all: [FeatureDefinition] = [
        FeatureDefinition(
            module: .notch,
            masterKey: "Notch.enabled",
            title: WSL10n.setting("settings.features.notch.name", zh: "刘海"),
            subtitle: WSL10n.setting("settings.features.notch.sub", zh: "把窗口和正在播放的内容收进刘海。"),
            defaultOnForFreshInstall: true,
            subfeatures: [.init(key: "Notch.enabled", defaultWhenUnset: true)]),
        FeatureDefinition(
            module: .windowBrowser,
            masterKey: "WindowBrowser.enabled",
            title: WSL10n.setting("settings.features.windowBrowser.name", zh: "窗口浏览"),
            subtitle: WSL10n.setting("settings.features.windowBrowser.sub", zh: "停在 Dock 图标上看这个 App 的窗口。"),
            defaultOnForFreshInstall: true,
            subfeatures: [
                .init(key: "WindowBrowserDockEnabled", defaultWhenUnset: true),
                .init(key: "WindowBrowserKeyboardPanelEnabled", defaultWhenUnset: true),
                .init(key: "WindowBrowserLivePreviewEnabled", defaultWhenUnset: false),
            ]),
        FeatureDefinition(
            module: .launchpad,
            masterKey: "Launchpad.enabled",
            title: WSL10n.setting("settings.features.launchpad.name", zh: "启动台"),
            subtitle: WSL10n.setting("settings.features.launchpad.sub", zh: "用启动台找 App、整理图标。"),
            defaultOnForFreshInstall: true,
            subfeatures: []),
        FeatureDefinition(
            module: .pictureInPicture,
            masterKey: "PictureInPicture.enabled",
            title: WSL10n.setting("settings.features.pictureInPicture.name", zh: "画中画"),
            subtitle: WSL10n.setting("settings.features.pictureInPicture.sub", zh: "把一个窗口浮在别的窗口上面。"),
            defaultOnForFreshInstall: true,
            subfeatures: []),
        FeatureDefinition(
            module: .inputEnhancements,
            masterKey: "InputEnhancements.enabled",
            title: WSL10n.setting("settings.features.input.name", zh: "手势与输入"),
            subtitle: WSL10n.setting("settings.features.input.sub", zh: "标题栏手势、触控板、鼠标侧键和滚动手感。"),
            defaultOnForFreshInstall: false,
            subfeatures: [
                .init(key: "TrackpadGesturesEnabled", defaultWhenUnset: true),
                .init(key: "Gestures.dropSplit.enabled", defaultWhenUnset: false),
                .init(key: "WindowShade.Input.SmoothScroll", defaultWhenUnset: false),
                .init(key: "WindowShade.Input.SideButtons", defaultWhenUnset: false),
                .init(key: "WindowShade.Input.MiddleFold", defaultWhenUnset: false),
            ]),
        FeatureDefinition(
            module: .securityExtras,
            masterKey: "SecurityExtras.enabled",
            title: WSL10n.setting("settings.features.security.name", zh: "认你与锁屏"),
            subtitle: WSL10n.setting("settings.features.security.sub", zh: "刷脸、离开就锁、有人在看时收起私人窗口。"),
            defaultOnForFreshInstall: false,
            subfeatures: [
                .init(key: "FaceScan.experiment.enabled", defaultWhenUnset: false, requires: .faceUnlock),
                .init(key: "Presence.lock.enabled", defaultWhenUnset: false),
                .init(key: "Privacy.bystanderCover.enabled", defaultWhenUnset: false),
            ],
            subtitleWithoutUnavailable: WSL10n.setting("settings.features.security.subIntel", zh: "离开就锁、有人在看时收起私人窗口。")),
        FeatureDefinition(
            module: .companion,
            masterKey: "Companion.enabled",
            title: WSL10n.setting("settings.features.companion.name", zh: "遥控与指挥"),
            subtitle: WSL10n.setting("settings.features.companion.sub", zh: "用 iPhone 遥控，或把编程会话和审批放进刘海。"),
            defaultOnForFreshInstall: false,
            subfeatures: [
                .init(key: "WindowShade.Conductor.Enabled", defaultWhenUnset: false),
                .init(key: "WindowShade.Conductor.CodingSessions", defaultWhenUnset: false),
                .init(key: "WindowShade.Input.RemoteMode", defaultWhenUnset: false),
                .init(key: "CarPlay.surface.enabled", defaultWhenUnset: false),
            ]),
        FeatureDefinition(
            module: .effects,
            masterKey: "Effects.enabled",
            title: WSL10n.setting("settings.features.effects.name", zh: "画面效果"),
            subtitle: WSL10n.setting("settings.features.effects.sub", zh: "合盖、收起窗口和锁屏时的动画。"),
            defaultOnForFreshInstall: false,
            subfeatures: [
                .init(key: "duo.v2.desktop", defaultWhenUnset: false, requires: .lidEffect),
                .init(key: "duo.v2.windows", defaultWhenUnset: true),
                .init(key: "lockOverlay.enabled", defaultWhenUnset: false, requires: .lidEffect),
            ],
            subtitleWithoutUnavailable: WSL10n.setting("settings.features.effects.subIntel", zh: "收起和展开窗口时的动画。")),
    ]

    static func definition(_ module: FeatureModule) -> FeatureDefinition {
        all.first { $0.module == module } ?? all[0]
    }

    static func isEnabled(_ module: FeatureModule, in defaults: UserDefaults = .standard) -> Bool {
        let definition = definition(module)
        if let value = defaults.object(forKey: definition.masterKey) as? Bool { return value }
        return definition.defaultOnForFreshInstall
    }

    static func setEnabled(_ module: FeatureModule, _ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: definition(module).masterKey)
    }

    /// 核心功能的一句话清单，设置页和首启共用。核心没有开关。
    @MainActor
    static let coreSummary: [SettingsText] = [
        WSL10n.setting("settings.features.core.fold", zh: "双击标题栏收起、展开窗口"),
        WSL10n.setting("settings.features.core.glance", zh: "停在卷帘条上看一眼"),
        WSL10n.setting("settings.features.core.carry", zh: "把窗口带到每张桌面"),
        WSL10n.setting("settings.features.core.space", zh: "按住卷帘条切桌面时窗口跟过去"),
        WSL10n.setting("settings.features.core.recovery", zh: "崩溃后恢复窗口和更新"),
    ]
}
