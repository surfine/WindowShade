import Foundation

/// 刷脸实验的特征后端选择。App 读 defaults 的 `FaceScan.experiment.backend`，探针读 `--backend`。
///
/// 加一个后端：在 `make` 里加一个 case，在 Core 的 FaceScanModelProfile.table 里加一条阈值，
/// 再把源文件加进 tools/probes/run-probe.sh 里 FaceFeaturePrintProbe 那一行。
enum FaceEmbedderBackends {
    static let defaultsKey = "FaceScan.experiment.backend"
    static let fallback = "vision"
    /// "arcface" 先占名；这份源码里没有 ArcFace 后端，选它会退回 vision。
    static let names = ["vision", "arcface"]

    /// 这台机器上能用的后端；没有或不支持就返回 nil。
    static func make(_ name: String) -> (any FaceEmbedder)? {
        switch name {
        case "vision": return VisionFaceEmbedder.isSupported ? VisionFaceEmbedder() : nil
        default: return nil
        }
    }

    /// App 用：选中的后端不可用就退回 vision；返回实际用上的名字。
    static func resolve(_ requested: String?) -> (name: String, embedder: any FaceEmbedder)? {
        let name = requested?.trimmingCharacters(in: .whitespaces).lowercased() ?? fallback
        if let embedder = make(name) { return (name, embedder) }
        return make(fallback).map { (fallback, $0) }
    }
}
