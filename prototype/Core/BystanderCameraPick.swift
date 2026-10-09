// 旁人一瞥用哪颗镜头：开发者环境变量优先，否则看设置开关，再按镜头选择规则挑。
// 纯逻辑：不碰 AVFoundation，不开相机。
import Foundation

enum BystanderCameraPick {
    static let enabledKey = "Privacy.bystanderCover.enabled"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// 返回要用的镜头 id；nil 表示不开相机。
    /// - 环境变量写了镜头：直接用（开发者覆盖，不看开关）。
    /// - 开关没开：nil。
    /// - 开关开了：只有一颗就用它；有多颗时按镜头选择规则，仍分不出来就用列表里第一颗。
    static func resolve(environmentCamera: String?, settingEnabled: Bool, available: [String]) -> String? {
        if let forced = environmentCamera?.trimmingCharacters(in: .whitespaces), !forced.isEmpty { return forced }
        guard settingEnabled, !available.isEmpty else { return nil }
        let candidates = available.map {
            WS2CameraCandidate(id: WS2CameraID(value: $0), placement: .unknown, isFront: true)
        }
        let decision = WS2CameraChoice.decide(WS2CameraChoiceInput(cameras: candidates))
        return decision.primary?.value ?? available.first
    }
}
