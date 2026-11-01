import Foundation

// 功能目录与首次播种：8 个模块、默认矩阵、升级不重置。

@main
struct FeatureCatalogTests {
    static func main() {
        let all = FeatureCatalog.all
        precondition(all.count == 8, "expected 8 optional modules, got \(all.count)")
        precondition(Set(all.map(\.masterKey)).count == 8, "master keys must be unique")
        precondition(Set(all.map(\.module)).count == 8, "modules must be unique")

        // 新装：稳定 4 个开，其余 4 个关
        let fresh = UserDefaults(suiteName: "FeatureCatalogTests.fresh")!
        fresh.removePersistentDomain(forName: "FeatureCatalogTests.fresh")
        InstallFeatureDefaults.seedIfNeeded(freshInstall: true, in: fresh)
        let expectedOn: Set<FeatureModule> = [.notch, .windowBrowser, .launchpad, .pictureInPicture]
        for definition in all {
            let on = fresh.object(forKey: definition.masterKey) as? Bool ?? false
            precondition(on == expectedOn.contains(definition.module),
                         "fresh default wrong for \(definition.module): \(on)")
        }

        // 升级：按现有子项迁移；启动台/画中画没有子项，保留开
        let upgrade = UserDefaults(suiteName: "FeatureCatalogTests.upgrade")!
        upgrade.removePersistentDomain(forName: "FeatureCatalogTests.upgrade")
        upgrade.set(false, forKey: "WindowBrowserDockEnabled")
        upgrade.set(false, forKey: "WindowBrowserKeyboardPanelEnabled")
        upgrade.set(true, forKey: "Presence.lock.enabled")
        InstallFeatureDefaults.seedIfNeeded(freshInstall: false, in: upgrade)
        precondition((upgrade.object(forKey: "WindowBrowser.enabled") as? Bool) == false)
        precondition((upgrade.object(forKey: "SecurityExtras.enabled") as? Bool) == true)
        precondition((upgrade.object(forKey: "Launchpad.enabled") as? Bool) == true)
        precondition((upgrade.object(forKey: "PictureInPicture.enabled") as? Bool) == true)
        // 画面效果：窗口动画没设过时默认开，所以升级应保留
        precondition((upgrade.object(forKey: "Effects.enabled") as? Bool) == true)

        // 只播种一次：用户改过之后不再覆盖
        upgrade.set(false, forKey: "SecurityExtras.enabled")
        InstallFeatureDefaults.seedIfNeeded(freshInstall: false, in: upgrade)
        precondition((upgrade.object(forKey: "SecurityExtras.enabled") as? Bool) == false)

        // 读总闸的默认分支
        let empty = UserDefaults(suiteName: "FeatureCatalogTests.empty")!
        empty.removePersistentDomain(forName: "FeatureCatalogTests.empty")
        precondition(FeatureCatalog.isEnabled(.notch, in: empty) == true)
        precondition(FeatureCatalog.isEnabled(.effects, in: empty) == false)

        print("FeatureCatalogTests ok")
    }
}
