// H4 评估：标题栏定位「像素启发式 vs Vision」、缩略图裁剪「Vision 注意力显著性」。
// 用法：h4-vision-eval <截图文件夹>   （PNG，默认按 2x 视网膜截图，1 逻辑点 = 2 像素）
// 只测量，不改产品行为。启发式来源：HeuristicCopy.swift（= PreviewRenderer.swift:98）。
import Foundation
import CoreGraphics
import ImageIO
import Vision

let scale: CGFloat = 2
let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
    .filter { $0.hasSuffix(".png") }.sorted()

// 机器负载很高时墙钟时间不可信，所以同时记进程 CPU 时间；每个方法跑 reps 次，取墙钟最小的那次（连同它的 CPU）。
// 返回 "墙钟/CPU"（毫秒）。
let reps = Int(ProcessInfo.processInfo.environment["REPS"] ?? "3") ?? 3
var wallSum = [Double](repeating: 0, count: 4), cpuSum = [Double](repeating: 0, count: 4)
func ms(_ slot: Int, _ body: () -> Void) -> String {
    var best = Double.infinity, bestCPU = 0.0
    for _ in 0..<reps {
        let c0 = clock(), t = DispatchTime.now().uptimeNanoseconds
        body()
        let w = Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6
        let c = Double(clock() - c0) / Double(CLOCKS_PER_SEC) * 1000
        if w < best { best = w; bestCPU = c }
    }
    wallSum[slot] += best; cpuSum[slot] += bestCPU
    return String(format: "%.1f/%.1f", best, bestCPU)
}
func f1(_ v: CGFloat?) -> String { v.map { String(format: "%.1f", $0) } ?? "-" }

print("image\tsize_pt\theur_pt\theur_ms(wall/cpu)\ttext_band_pt\ttext_ms\trect_band_pt\trect_ms\tsal_bbox(x,y,w,h in %)\tsal_ms")
var n = 0
for name in files {
    guard let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
    let wPt = CGFloat(img.width) / scale, hPt = CGFloat(img.height) / scale

    // 1) 启发式（逐字拷贝）。minimum 取 standardCropHeight 的下限量级 28。
    var heur: CGFloat?
    let tH = ms(0) { heur = preciseVisualChromeHeight(of: img, scale: scale, minimum: 28) }

    // 2) Vision 文本：只看顶部 110pt；带高 = 最低一条文字底边 + 与顶边对称的留白（文字上缘距顶）。
    let topPx = min(img.height, Int(110 * scale))
    let topImg = img.cropping(to: CGRect(x: 0, y: 0, width: img.width, height: topPx))!
    var textBand: CGFloat?
    let tT = ms(1) {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .fast
        req.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: topImg).perform([req])
        let boxes = (req.results ?? []).map { $0.boundingBox }
        // 归一化坐标原点在左下；转成距顶部的像素
        let tops = boxes.map { (1 - $0.maxY) * CGFloat(topPx) / scale }
        let bottoms = boxes.map { (1 - $0.minY) * CGFloat(topPx) / scale }
        // 只取第一行文字所在的带（顶部 70pt 内），避免把内容区文字当成标题栏。
        let inBand = zip(tops, bottoms).filter { $0.0 < 70 }
        if let b = inBand.map({ $0.1 }).max(), let t = inBand.map({ $0.0 }).min() {
            textBand = b + max(6, t)
        }
    }

    // 3) Vision 矩形：顶部 110pt 里找控件/搜索框类矩形，带高 = 最低矩形底边 + 对称留白。
    var rectBand: CGFloat?
    let tR = ms(2) {
        let req = VNDetectRectanglesRequest()
        req.minimumAspectRatio = 0.05
        req.maximumObservations = 12
        req.minimumSize = 0.02
        req.minimumConfidence = 0.5
        req.quadratureTolerance = 15
        try? VNImageRequestHandler(cgImage: topImg).perform([req])
        let rs = (req.results ?? []).filter { r in
            let t = (1 - r.boundingBox.maxY) * CGFloat(topPx) / scale
            return t < 70 && r.boundingBox.width < 0.9
        }
        if let b = rs.map({ (1 - $0.boundingBox.minY) * CGFloat(topPx) / scale }).max(),
           let t = rs.map({ (1 - $0.boundingBox.maxY) * CGFloat(topPx) / scale }).min() {
            rectBand = b + max(6, t)
        }
    }

    // 4) 注意力显著性：整图一次，取最大显著区域的外框（占整图百分比，原点左上）。
    var sal = "-"
    let tS = ms(3) {
        let req = VNGenerateAttentionBasedSaliencyImageRequest()
        try? VNImageRequestHandler(cgImage: img).perform([req])
        if let o = req.results?.first?.salientObjects?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) {
            let b = o.boundingBox
            sal = String(format: "%.0f,%.0f,%.0f,%.0f", b.minX * 100, (1 - b.maxY) * 100, b.width * 100, b.height * 100)
        } else { sal = "none" }
    }
    n += 1
    print("\(name)\t\(Int(wPt))x\(Int(hPt))\t\(f1(heur))\t\(tH)\t\(f1(textBand))\t\(tT)\t\(f1(rectBand))\t\(tR)\t\(sal)\t\(tS)")
}
if n > 0 {
    let d = Double(n)
    print(String(format: "MEAN_wall/cpu_ms\theur=%.1f/%.1f\ttext=%.1f/%.1f\trect=%.1f/%.1f\tsaliency=%.1f/%.1f\t(n=%d, reps=%d)",
                 wallSum[0]/d, cpuSum[0]/d, wallSum[1]/d, cpuSum[1]/d, wallSum[2]/d, cpuSum[2]/d, wallSum[3]/d, cpuSum[3]/d, n, reps))
}
