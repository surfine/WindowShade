// 指针离开内屏就遮住的判定（App/BuiltInCurtain.swift），纯逻辑，不碰屏幕。
import CoreGraphics

enum BuiltInCurtainPolicy {
    /// 开着、有内屏、不止一块屏、内屏没在镜像，并且指针不在内屏上：遮。
    static func shouldCover(enabled: Bool, builtIn: CGRect?, screenCount: Int, mirrored: Bool, pointer: CGPoint) -> Bool {
        guard enabled, let builtIn, screenCount > 1, !mirrored else { return false }
        return !builtIn.contains(pointer)
    }
}
