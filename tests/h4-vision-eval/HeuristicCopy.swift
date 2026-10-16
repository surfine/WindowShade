// 忠实拷贝：prototype/Capture/PreviewRenderer.swift:98-181（preciseVisualChromeHeight），逐字，由 sed -n 98,181p 生成。
import CoreGraphics
import Foundation
func preciseVisualChromeHeight(of image: CGImage, scale: CGFloat, minimum: CGFloat) -> CGFloat? {
    let w = image.width, h = image.height
    guard w > 20, h > 20, scale > 0 else { return nil }
    let maxScan = min(h, Int(ceil(130 * scale)))
    guard let top = image.cropping(to: CGRect(x: 0, y: 0, width: w, height: maxScan)) else { return nil }

    let bpr = w * 4
    var buf = [UInt8](repeating: 0, count: bpr * maxScan)
    guard let ctx = CGContext(data: &buf, width: w, height: maxScan, bitsPerComponent: 8,
                              bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(top, in: CGRect(x: 0, y: 0, width: w, height: maxScan))

    let step = max(1, w / 1200)
    let edgeInset = max(Int(18 * scale), min(w / 18, 96))
    let minRunWidth = max(Int(52 * scale), min(w / 14, 160))
    let maxRunWidth = Int(CGFloat(w) * 0.72)
    var controlRows: [(Int, Int)] = []

    for y in 0..<maxScan {
        var currentRunStart: Int?
        var bestRun = 0
        var x = 0
        while x < w {
            let i = y * bpr + x * 4
            let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2]), a = Int(buf[i + 3])
            let lum = (r + g + b) / 3
            let saturation = max(r, max(g, b)) - min(r, min(g, b))
            let blueBias = b - max(r, g)
            let isLightControl = a > 170 && lum > 232 && saturation < 26
            let isFocusRing = a > 150 && blueBias > 26 && b > 150 && r < 190
            let isControlPixel = isLightControl || isFocusRing

            if isControlPixel {
                if currentRunStart == nil { currentRunStart = x }
            } else if let start = currentRunStart {
                let width = x - start
                if start > edgeInset && x < w - edgeInset &&
                   width >= minRunWidth && width <= maxRunWidth {
                    bestRun = max(bestRun, width)
                }
                currentRunStart = nil
            }

            if x + step >= w, let start = currentRunStart {
                let end = min(w, x + step)
                let width = end - start
                if start > edgeInset && end < w - edgeInset &&
                   width >= minRunWidth && width <= maxRunWidth {
                    bestRun = max(bestRun, width)
                }
                currentRunStart = nil
            }
            x += step
        }
        if bestRun > 0 { controlRows.append((y, bestRun)) }
    }

    let maxGap = max(2, Int(ceil(2 * scale)))
    let minRows = max(12, Int(ceil(12 * scale)))
    var clusters: [[(Int, Int)]] = []
    for row in controlRows {
        if clusters.isEmpty || row.0 - (clusters[clusters.count - 1].last?.0 ?? row.0) > maxGap {
            clusters.append([])
        }
        clusters[clusters.count - 1].append(row)
    }

    let maxControlTop = Int(ceil(70 * scale))
    guard let cluster = clusters.first(where: {
        guard $0.count >= minRows, let first = $0.first, let last = $0.last else { return false }
        let height = last.0 - first.0
        return first.0 <= maxControlTop && height >= Int(12 * scale) && height <= Int(58 * scale)
    }), let first = cluster.first, let last = cluster.last else { return nil }

    let controlTop = CGFloat(first.0)
    let controlBottom = CGFloat(last.0)
    let topPadding = max(6 * scale, min(controlTop, 26 * scale))
    let candidate = (controlBottom + topPadding) / scale
    let minH = max(minimum, 32)
    guard candidate >= minH, candidate <= 96 else { return nil }
    return candidate
}

