import CoreGraphics
import CoreVideo
import Foundation
@preconcurrency import Vision

/// 一帧里每张脸的框和朝向（多人时也给，旁人一瞥用）。只是几何，不是身份。
struct FaceGeometry: Sendable, Equatable {
    /// 一帧最多交出这么多张脸。
    static let maxPerFrame = 8
    /// Vision 的归一化框，原点在画面左下。
    let boundingBox: CGRect
    let yaw: Double?
    let pitch: Double?
    /// 只在有刷脸实验订阅者时填：两眼中心连线在画面像素里的倾角（弧度，逆时针为正，y 向上）。
    var eyeLineAngle: Double? = nil
    /// 只在有刷脸实验订阅者时填：五个对齐点，画面归一化坐标、原点左下，顺序是
    /// 画面左侧眼睛中心、画面右侧眼睛中心、鼻子中心、画面左侧嘴角、画面右侧嘴角（ArcFace 类对齐用）。
    var alignmentPoints: [CGPoint]? = nil
}

/// 刷脸实验的特征后端。在相机工作队列（或探针自己的队列）上调用；同一帧、同一个人脸框。
/// 实现不得存图像、不得写日志、不得记录向量。返回值应当 L2 归一化；算不出就返回 nil。
protocol FaceEmbedder: Sendable {
    /// 写进模板与帧的版本串；Core 的阈值表（FaceScanModelProfile.table）按它取阈值。
    var modelVersion: String { get }
    func embed(pixelBuffer: CVPixelBuffer, face: FaceGeometry) -> [Float]?
}

/// 从 Vision 的人脸结果算出对齐几何（纯计算，不碰像素）。
enum FaceAlignment {
    static func finite(_ number: NSNumber?) -> Double? {
        guard let value = number?.doubleValue, value.isFinite else { return nil }
        return value
    }

    /// aligned = false 时只给框和朝向，和以前一样；true 时另算两眼倾角和五个对齐点。
    static func geometry(for face: VNFaceObservation, imageSize: CGSize, aligned: Bool) -> FaceGeometry {
        var geometry = FaceGeometry(boundingBox: face.boundingBox, yaw: finite(face.yaw), pitch: finite(face.pitch))
        guard aligned, let landmarks = face.landmarks else { return geometry }
        let box = face.boundingBox
        func toImage(_ p: CGPoint) -> CGPoint { CGPoint(x: box.minX + p.x * box.width, y: box.minY + p.y * box.height) }
        func centre(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let points = region?.normalizedPoints, !points.isEmpty,
                  points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
            let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            return toImage(CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count)))
        }
        if let left = landmarks.leftEye?.normalizedPoints, let right = landmarks.rightEye?.normalizedPoints {
            geometry.eyeLineAngle = eyeLineAngle(leftEye: left, rightEye: right, boundingBox: box, imageSize: imageSize)
        }
        if let a = centre(landmarks.leftEye), let b = centre(landmarks.rightEye), let nose = centre(landmarks.nose),
           let lips = landmarks.outerLips?.normalizedPoints, lips.count >= 2,
           let low = lips.min(by: { $0.x < $1.x }), let high = lips.max(by: { $0.x < $1.x }) {
            let eyes = a.x <= b.x ? [a, b] : [b, a]
            geometry.alignmentPoints = eyes + [nose, toImage(low), toImage(high)]
        }
        return geometry
    }

    /// 眼睛轮廓点（Vision 的脸内归一化坐标）→ 两眼中心连线在画面像素里的倾角。
    /// 按画面左右排，角度落在 (-π/2, π/2]；点缺失、不有限或两眼几乎重合返回 nil。
    static func eyeLineAngle(leftEye: [CGPoint], rightEye: [CGPoint], boundingBox: CGRect, imageSize: CGSize) -> Double? {
        guard !leftEye.isEmpty, !rightEye.isEmpty, imageSize.width > 0, imageSize.height > 0,
              boundingBox.width > 0, boundingBox.height > 0 else { return nil }
        func centre(_ points: [CGPoint]) -> CGPoint? {
            guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
            let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let local = CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
            return CGPoint(x: (boundingBox.minX + local.x * boundingBox.width) * imageSize.width,
                           y: (boundingBox.minY + local.y * boundingBox.height) * imageSize.height)
        }
        guard var a = centre(leftEye), var b = centre(rightEye) else { return nil }
        if a.x > b.x { swap(&a, &b) }
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        guard hypot(dx, dy) >= 4 else { return nil }
        let angle = atan2(dy, dx)
        return angle.isFinite ? angle : nil
    }
}
