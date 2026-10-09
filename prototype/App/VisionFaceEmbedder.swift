import CoreImage
import CoreVideo
import Foundation
@preconcurrency import Vision

/// 刷脸实验的特征来源：只用 Apple Vision，不带第三方模型。
///
/// Vision 没有公开的人脸身份接口。这里的做法是：沿用相机工作队列上已经做过的人脸检测，
/// 从同一帧里裁出脸（外扩 1.3 倍的正方形），按两眼连线摆正，缩到 224 见方，
/// 再跑 VNGenerateImageFeaturePrintRequest（钉死第 2 版），把输出向量做 L2 归一化。
/// 这是通用图像特征，不是人脸身份特征；阈值必须用 tools/probes/FaceFeaturePrintProbe.swift 在真机上标定。
///
/// 在调用方的队列上同步运行（相机工作队列，或探针自己的队列）。唯一的状态是一个只读的 CIContext
/// （Core Image 文档说明 CIContext 可跨线程共用），所以标 @unchecked Sendable。
/// 不存图像、不写日志、不记向量：裁切图只在这一次调用里活着。
final class VisionFaceEmbedder: FaceEmbedder, @unchecked Sendable {
    /// 钉死的特征修订；换修订就是另一个模型版本，旧模板按守卫的版本规则自动不参与。
    static let revision = VNGenerateImageFeaturePrintRequestRevision2
    static let cropMargin: CGFloat = 1.3
    static let side = 224
    /// 必须与 Core 阈值表里的 FaceScanModelProfile.visionFeaturePrintVersion 一字不差；
    /// 探针 --self-test 和刷脸实验启动时都会核对，对不上就不启用。这里不引用 Core，是为了让相机
    /// 采集的各个测试脚本不必多编一份守卫。
    static let modelVersion = "vision-featureprint-r\(revision)-crop1.3-\(side)"
    var modelVersion: String { Self.modelVersion }
    /// 头转得太偏时图像特征不可比，宁可不给。弧度。
    static let maximumYaw = 0.5
    static let maximumPitch = 0.5
    /// 裁切边长不到这么多像素就不算（太远、太糊）。
    static let minimumCropPixels: CGFloat = 48

    /// 一次裁切的几何：图像像素坐标，原点在左下（与 Vision、Core Image 相同）。
    struct Crop: Equatable {
        let center: CGPoint
        let side: CGFloat
        /// 两眼连线相对水平线的倾角（弧度，逆时针为正）；裁切时反向转回。
        let angle: Double
    }

    private let context = CIContext(options: [.cacheIntermediates: false])

    init() {}

    /// 这台机器的 Vision 是否支持钉死的修订。不支持就不给特征，不悄悄换修订。
    static var isSupported: Bool {
        VNGenerateImageFeaturePrintRequest.supportedRevisions.contains(revision)
    }

    // MARK: - 纯几何（探针 --self-test 覆盖）

    static func poseAcceptable(yaw: Double?, pitch: Double?) -> Bool {
        if let yaw, !(yaw.isFinite && abs(yaw) <= maximumYaw) { return false }
        if let pitch, !(pitch.isFinite && abs(pitch) <= maximumPitch) { return false }
        return true
    }

    /// Vision 的归一化人脸框 → 外扩 1.3 倍的正方形裁切。框不合法或太小返回 nil。
    static func crop(boundingBox: CGRect, imageSize: CGSize, eyeLineAngle: Double) -> Crop? {
        guard [boundingBox.minX, boundingBox.minY, boundingBox.width, boundingBox.height].allSatisfy(\.isFinite),
              boundingBox.width > 0, boundingBox.height > 0, eyeLineAngle.isFinite,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let side = max(boundingBox.width * imageSize.width, boundingBox.height * imageSize.height) * cropMargin
        guard side >= minimumCropPixels else { return nil }
        let center = CGPoint(x: boundingBox.midX * imageSize.width, y: boundingBox.midY * imageSize.height)
        return Crop(center: center, side: side, angle: eyeLineAngle)
    }

    /// 把裁切几何变成 Core Image 变换：移到原点、反向转正、缩到 side、移回正方形中心。
    static func transform(for crop: Crop) -> CGAffineTransform {
        let scale = CGFloat(side) / crop.side
        return CGAffineTransform(translationX: -crop.center.x, y: -crop.center.y)
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(-crop.angle)))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: CGFloat(side) / 2, y: CGFloat(side) / 2))
    }

    static func l2Normalized(_ vector: [Float]) -> [Float]? {
        guard !vector.isEmpty, vector.allSatisfy(\.isFinite) else { return nil }
        let norm = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0, norm.isFinite else { return nil }
        return vector.map { $0 / norm }
    }

    // MARK: - 特征

    /// 一张脸的特征：同一帧、同一个人脸框。头太偏、没有两眼倾角、裁切太小或 Vision 失败都返回 nil，
    /// 不报原因细节（不进日志）。
    func embed(pixelBuffer: CVPixelBuffer, face: FaceGeometry) -> [Float]? {
        guard Self.poseAcceptable(yaw: face.yaw, pitch: face.pitch), let angle = face.eyeLineAngle else { return nil }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let crop = Self.crop(boundingBox: face.boundingBox, imageSize: image.extent.size, eyeLineAngle: angle)
        else { return nil }
        return embed(image: image, crop: crop)
    }

    /// 已有完整画面（原点在左下）时直接裁；探针自检也走这里。
    func embed(image: CIImage, crop: Crop) -> [Float]? {
        guard Self.isSupported else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        let face = image.clampedToExtent().transformed(by: Self.transform(for: crop)).cropped(to: bounds)
        guard let rendered = context.createCGImage(face, from: bounds) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = Self.revision
        request.imageCropAndScaleOption = .scaleFill
        do { try VNImageRequestHandler(cgImage: rendered, options: [:]).perform([request]) } catch { return nil }
        guard let print = request.results?.first else { return nil }
        return Self.l2Normalized(Self.floats(of: print))
    }

    private static func floats(of print: VNFeaturePrintObservation) -> [Float] {
        let count = print.elementCount
        let data = print.data
        switch print.elementType {
        case .float:
            guard data.count >= count * MemoryLayout<Float>.size else { return [] }
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(count)) }
        case .double:
            guard data.count >= count * MemoryLayout<Double>.size else { return [] }
            return data.withUnsafeBytes { $0.bindMemory(to: Double.self).prefix(count).map { Float($0) } }
        case .unknown:
            return []
        @unknown default:
            return []
        }
    }
}
