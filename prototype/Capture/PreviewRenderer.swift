// 渲染与图像分析辅助（纯计算）：标题行绘制、布局度量、
// 标题栏 chrome 像素扫描、圆角镜像、截图降采样、卷帘条制备等。
// 全部为纯函数/纯类型，可在任意线程执行，不依赖 AppDelegate 状态。

import Cocoa
import CoreText
import Darwin

func drawAlignedTitleLine(_ attr: NSAttributedString, textX: CGFloat, textWidth: CGFloat,
                          centerY: CGFloat) {
    guard textWidth > 8,
          let context = NSGraphicsContext.current?.cgContext else { return }

    let line = CTLineCreateWithAttributedString(attr)
    let tokenAttr = NSAttributedString(string: "\u{2026}", attributes: attr.attributes(at: 0, effectiveRange: nil))
    let tokenLine = CTLineCreateWithAttributedString(tokenAttr)
    let displayLine = CTLineCreateTruncatedLine(line, Double(textWidth), .end, tokenLine) ?? line

    let glyphBounds = CTLineGetBoundsWithOptions(displayLine, [.useGlyphPathBounds])
    let baselineY: CGFloat
    if glyphBounds.height > 0, glyphBounds.minY.isFinite, glyphBounds.midY.isFinite {
        baselineY = round(centerY - glyphBounds.midY)
    } else {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(displayLine, &ascent, &descent, &leading)
        baselineY = round(centerY - (ascent - descent) / 2)
    }

    context.saveGState()
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: textX - min(0, glyphBounds.minX), y: baselineY)
    CTLineDraw(displayLine, context)
    context.restoreGState()
}

struct ProxyTitleLayoutMetrics {
    static let trafficLightDiameter: CGFloat = 14
    static let trafficLightGap: CGFloat = 8
    static let trafficLightGroupInset: CGFloat = 16
    static let iconSize: CGFloat = 14
    static let iconGap: CGFloat = 6
    static let textTrailingInset: CGFloat = 22

    static var step: CGFloat {
        trafficLightDiameter + trafficLightGap
    }

    static var firstCenterX: CGFloat {
        trafficLightGroupInset + trafficLightDiameter / 2
    }

    static func iconCenterX(trafficLightSlots: Int = 3) -> CGFloat {
        firstCenterX + step * CGFloat(max(trafficLightSlots, 1))
    }

    static func centerY(in bounds: NSRect) -> CGFloat {
        bounds.midY
    }

    static func trafficLightRects(in bounds: NSRect,
                                  actions: [TrafficAction] = [.close, .minimize, .zoom]) -> [(CGRect, TrafficAction)] {
        let centerY = centerY(in: bounds)
        return actions.enumerated().map { index, action in
            (CGRect(x: firstCenterX + step * CGFloat(index) - trafficLightDiameter / 2,
                    y: centerY - trafficLightDiameter / 2,
                    width: trafficLightDiameter,
                    height: trafficLightDiameter), action)
        }
    }

    static func iconRect(in bounds: NSRect, hasIcon: Bool, trafficLightSlots: Int = 3) -> NSRect {
        guard hasIcon else { return .zero }
        let centerY = centerY(in: bounds)
        return NSRect(x: iconCenterX(trafficLightSlots: trafficLightSlots) - iconSize / 2,
                      y: centerY - iconSize / 2,
                      width: iconSize,
                      height: iconSize)
    }

    static func textFrame(in bounds: NSRect, hasIcon: Bool, trafficLightSlots: Int = 3) -> NSRect {
        let iconRect = iconRect(in: bounds, hasIcon: hasIcon, trafficLightSlots: trafficLightSlots)
        let textX = hasIcon
            ? iconRect.maxX + iconGap
            : iconCenterX(trafficLightSlots: trafficLightSlots) - iconSize / 2
        let width = max(24, bounds.width - textX - textTrailingInset)
        return NSRect(x: textX, y: 0, width: width, height: bounds.height)
    }
}

// AX 看不到的 toolbar/titlebar 控件，用截图补判。只用于没有 AXToolbar 的窗口。
// 只在真的看见搜索框/输入框这类“内部浅色控件块”时生效：
// 取控件块上下边界，并用控件块上 margin 推出同等下 margin。纯 titlebar 没有控件时返回 nil。
func visualChromeHeight(of image: CGImage, scale: CGFloat, minimum: CGFloat) -> CGFloat? {
    let w = image.width, h = image.height
    guard w > 20, h > 20, scale > 0 else { return nil }
    let maxScan = min(h, Int(ceil(110 * scale)))
    guard maxScan > Int(minimum * scale) else { return nil }
    guard let top = image.cropping(to: CGRect(x: 0, y: 0, width: w, height: maxScan)) else { return nil }

    let bpr = w * 4
    var buf = [UInt8](repeating: 0, count: bpr * maxScan)
    guard let ctx = CGContext(data: &buf, width: w, height: maxScan, bitsPerComponent: 8,
                              bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(top, in: CGRect(x: 0, y: 0, width: w, height: maxScan))

    func transparentCount(row: Int) -> Int {
        var c = 0
        let edge = max(8, min(w / 8, 80))
        for x in 0..<edge {
            if buf[row * bpr + x * 4 + 3] < 96 { c += 1 }
        }
        for x in max(edge, w - edge)..<w {
            if buf[row * bpr + x * 4 + 3] < 96 { c += 1 }
        }
        return c
    }

    let topIsLowRow = transparentCount(row: 0) >= transparentCount(row: maxScan - 1)
    let step = max(1, w / 900)
    let edgeInset = max(Int(18 * scale), min(w / 18, 90))
    let minRunWidth = max(Int(60 * scale), min(w / 12, 120))
    let maxRunWidth = Int(CGFloat(w) * 0.56)
    var controlRows: [(Int, Int)] = []

    for rawY in 0..<maxScan {
        let y = topIsLowRow ? rawY : (maxScan - 1 - rawY)
        var currentRunStart: Int?
        var bestRun = 0
        var x = 0
        while x < w {
            let i = rawY * bpr + x * 4
            let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2]), a = Int(buf[i + 3])
            let lum = (r + g + b) / 3
            let saturation = max(r, max(g, b)) - min(r, min(g, b))
            let isControlFill = a > 180 && lum > 238 && saturation < 18

            if isControlFill {
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
        if bestRun > 0 {
            controlRows.append((y, bestRun))
        }
    }

    let sortedRows = controlRows.sorted { $0.0 < $1.0 }
    let maxGap = max(2, Int(ceil(2 * scale)))
    let minRows = max(10, Int(ceil(10 * scale)))
    var clusters: [[(Int, Int)]] = []
    for row in sortedRows {
        if clusters.isEmpty || row.0 - (clusters[clusters.count - 1].last?.0 ?? row.0) > maxGap {
            clusters.append([])
        }
        clusters[clusters.count - 1].append(row)
    }

    let minPx = minimum * scale
    let searchLimit = min(CGFloat(maxScan), minPx + 32 * scale)
    guard let chromeCluster = clusters.first(where: {
        guard $0.count >= minRows, let first = $0.first, let last = $0.last else { return false }
        return CGFloat(first.0) <= searchLimit && CGFloat(last.0 - first.0) >= 12 * scale
    }) else { return nil }

    let controlTop = CGFloat(chromeCluster.first!.0)
    let controlBottom = CGFloat(chromeCluster.last!.0)
    let topMargin = max(6 * scale, min(controlTop, 28 * scale))
    let candidate = controlBottom + topMargin
    guard candidate > minPx + 3 * scale else { return nil }
    let candidatePt = candidate / scale
    let maxReasonable = min(72, max(56, minimum + 24))
    guard candidatePt <= maxReasonable else { return nil }
    return candidatePt
}

// Elpass / WeChat 这类窗口的 AX 树不给稳定 toolbar：
// - Elpass 会把内容区控件混进顶部扫描，AX 高度偏大；
// - WeChat 只暴露交通灯，AX 高度偏小。
// 这条只在白名单 app 上使用：从截图上找搜索框/顶部控件的浅色填充行，
// 用控件上 padding 推出对称下 padding，得到“刚好包住顶部控件”的裁切高度。
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

// 把截图底部两角裁成和顶部两角完全一样的形状：每个像素的 alpha 与其「垂直镜像」位置取 min。
// 顶部本就有原生圆角的透明缺口，镜像到底部就得到对称、同半径同曲线的底部圆角——不靠猜半径。
func mirrorRoundCorners(_ image: CGImage) -> CGImage? {
    let w = image.width, h = image.height
    guard w > 0, h > 0 else { return nil }
    let bpr = w * 4
    var buf = [UInt8](repeating: 0, count: bpr * h)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    var origAlpha = [UInt8](repeating: 0, count: w * h)        // 先快照原始 alpha，避免边改边读
    for y in 0..<h { for x in 0..<w { origAlpha[y * w + x] = buf[y * bpr + x * 4 + 3] } }

    for y in 0..<h {
        let my = h - 1 - y
        for x in 0..<w {
            let aSelf = origAlpha[y * w + x]
            let aMirror = origAlpha[my * w + x]
            if aMirror < aSelf {                               // 镜像处更透明 → 把本像素也裁掉相应程度
                let i = y * bpr + x * 4
                let f = Float(aMirror) / Float(aSelf)          // 预乘 RGBA 同比缩放
                buf[i]     = UInt8(Float(buf[i])     * f)
                buf[i + 1] = UInt8(Float(buf[i + 1]) * f)
                buf[i + 2] = UInt8(Float(buf[i + 2]) * f)
                buf[i + 3] = aMirror
            }
        }
    }
    return ctx.makeImage()
}

func nativeTitleStripLooksBroken(_ image: CGImage, logicalHeight: CGFloat) -> (Bool, String) {
    let w = image.width, h = image.height
    guard w > 120, h > 12 else { return (true, "too-small") }
    let bpr = w * 4
    var buf = [UInt8](repeating: 0, count: bpr * h)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return (false, "unreadable")
    }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    let stepX = max(1, w / 360)
    let stepY = max(1, h / 80)
    var samples = 0
    var opaque = 0
    var rowCoverages: [CGFloat] = []

    var y = 0
    while y < h {
        var rowSamples = 0
        var rowOpaque = 0
        var x = 0
        while x < w {
            let alpha = buf[y * bpr + x * 4 + 3]
            samples += 1
            rowSamples += 1
            if alpha >= 190 {
                opaque += 1
                rowOpaque += 1
            }
            x += stepX
        }
        if rowSamples > 0 {
            rowCoverages.append(CGFloat(rowOpaque) / CGFloat(rowSamples))
        }
        y += stepY
    }

    guard samples > 0 else { return (false, "empty-sample") }
    let opaqueRatio = CGFloat(opaque) / CGFloat(samples)
    let strongRows = rowCoverages.filter { $0 >= 0.78 }.count
    let strongRowRatio = rowCoverages.isEmpty ? CGFloat(0) : CGFloat(strongRows) / CGFloat(rowCoverages.count)
    let medianRowCoverage = rowCoverages.sorted()[max(0, rowCoverages.count / 2)]

    func materialCoverage(xRange: Range<Int>, yRange: Range<Int>) -> CGFloat {
        var material = 0
        var count = 0
        let sx = max(1, (xRange.upperBound - xRange.lowerBound) / 80)
        let sy = max(1, (yRange.upperBound - yRange.lowerBound) / 24)
        var yy = yRange.lowerBound
        while yy < yRange.upperBound {
            var xx = xRange.lowerBound
            while xx < xRange.upperBound {
                let i = yy * bpr + xx * 4
                let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2]), a = Int(buf[i + 3])
                let lum = (r + g + b) / 3
                let saturation = max(r, max(g, b)) - min(r, min(g, b))
                count += 1
                if a > 90 && (lum < 246 || saturation > 22) {
                    material += 1
                }
                xx += sx
            }
            yy += sy
        }
        return count > 0 ? CGFloat(material) / CGFloat(count) : 0
    }

    // 只统计 alpha 覆盖率，不管颜色。用来区分两种"两侧空"：
    // 真悬浮岛（Codex 式分离标题药丸）两侧是 alpha≈0 的透明缺口；
    // Liquid Glass 全宽工具栏（Safari 非激活态）两侧是近白色半透明"材质"——
    // 后者是正常 chrome，不得降级成代理标题栏。
    func alphaCoverage(xRange: Range<Int>, yRange: Range<Int>) -> CGFloat {
        var covered = 0
        var count = 0
        let sx = max(1, (xRange.upperBound - xRange.lowerBound) / 80)
        let sy = max(1, (yRange.upperBound - yRange.lowerBound) / 24)
        var yy = yRange.lowerBound
        while yy < yRange.upperBound {
            var xx = xRange.lowerBound
            while xx < xRange.upperBound {
                if buf[yy * bpr + xx * 4 + 3] >= 120 { covered += 1 }
                count += 1
                xx += sx
            }
            yy += sy
        }
        return count > 0 ? CGFloat(covered) / CGFloat(count) : 0
    }

    let bandTop = max(0, Int(CGFloat(h) * 0.22))
    let bandBottom = min(h, max(bandTop + 1, Int(CGFloat(h) * 0.82)))
    let band = bandTop..<bandBottom
    let leadingRange = 0..<max(1, Int(CGFloat(w) * 0.10))
    let leftRange = 0..<max(1, Int(CGFloat(w) * 0.22))
    let leadingMaterial = materialCoverage(xRange: leadingRange, yRange: band)
    let leftShoulderMaterial = materialCoverage(xRange: Int(CGFloat(w) * 0.10)..<max(Int(CGFloat(w) * 0.10) + 1, Int(CGFloat(w) * 0.22)), yRange: band)
    let leftMaterial = materialCoverage(xRange: leftRange, yRange: band)
    let centerMaterial = materialCoverage(xRange: Int(CGFloat(w) * 0.32)..<max(Int(CGFloat(w) * 0.32) + 1, Int(CGFloat(w) * 0.72)), yRange: band)
    let rightMaterial = materialCoverage(xRange: Int(CGFloat(w) * 0.78)..<w, yRange: band)
    let leadingAlpha = alphaCoverage(xRange: leadingRange, yRange: band)
    let leftAlpha = alphaCoverage(xRange: leftRange, yRange: band)

    if logicalHeight >= 30,
       leadingAlpha <= 0.35,
       leadingMaterial <= 0.28,
       centerMaterial >= 0.55,
       centerMaterial - leadingMaterial >= 0.35,
       leftShoulderMaterial > leadingMaterial + 0.20 {
        return (true, String(format: "floating-island-leading leading=%.2f(a=%.2f) shoulder=%.2f center=%.2f right=%.2f",
                             leadingMaterial, leadingAlpha, leftShoulderMaterial, centerMaterial, rightMaterial))
    }
    if logicalHeight >= 30,
       leftAlpha <= 0.35,
       centerMaterial >= 0.30,
       leftMaterial <= 0.16,
       centerMaterial - leftMaterial >= 0.22 {
        return (true, String(format: "floating-island left=%.2f(a=%.2f) center=%.2f right=%.2f",
                             leftMaterial, leftAlpha, centerMaterial, rightMaterial))
    }
    if opaqueRatio < 0.30 {
        return (true, String(format: "sparse-alpha %.2f", opaqueRatio))
    }
    if logicalHeight >= 30,
       opaqueRatio < 0.46,
       strongRowRatio < 0.28,
       medianRowCoverage < 0.55 {
        return (true, String(format: "floating-chrome alpha=%.2f strongRows=%.2f median=%.2f",
                             opaqueRatio, strongRowRatio, medianRowCoverage))
    }
    return (false, String(format: "ok alpha=%.2f strongRows=%.2f median=%.2f",
                          opaqueRatio, strongRowRatio, medianRowCoverage))
}

func estimatedCornerRadiusPixels(from image: CGImage) -> CGFloat? {
    let w = image.width, h = image.height
    guard w > 8, h > 8 else { return nil }
    let bpr = w * 4
    var buf = [UInt8](repeating: 0, count: bpr * h)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    func firstOpaqueDistance(fromLeft: Bool, y: Int) -> CGFloat? {
        let threshold: UInt8 = 236
        if fromLeft {
            for x in 0..<min(w / 2, 160) {
                if buf[y * bpr + x * 4 + 3] >= threshold { return CGFloat(x) }
            }
        } else {
            for offset in 0..<min(w / 2, 160) {
                let x = w - 1 - offset
                if buf[y * bpr + x * 4 + 3] >= threshold { return CGFloat(offset) }
            }
        }
        return nil
    }

    let samples = [
        firstOpaqueDistance(fromLeft: true, y: 0),
        firstOpaqueDistance(fromLeft: false, y: 0),
        firstOpaqueDistance(fromLeft: true, y: h - 1),
        firstOpaqueDistance(fromLeft: false, y: h - 1),
    ].compactMap { $0 }.filter { $0 > 2 }
    guard let radius = samples.sorted().dropFirst(samples.count / 2).first else { return nil }
    return min(max(radius, 6), CGFloat(min(w, h)) / 2)
}

func roundedClippedImage(_ image: CGImage, cornerRadius: CGFloat,
                         whitePreviewGradient: Bool = false) -> CGImage? {
    let w = image.width, h = image.height
    guard w > 0, h > 0 else { return nil }
    let bpr = w * 4
    var buf = [UInt8](repeating: 0, count: bpr * h)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
    let rect = CGRect(x: 0, y: 0, width: w, height: h)
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                      transform: nil)
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(image, in: rect)
    if whitePreviewGradient {
        let colors = [
            NSColor.white.withAlphaComponent(0.56).cgColor,
            NSColor.white.withAlphaComponent(0.20).cgColor,
            NSColor.white.withAlphaComponent(0.00).cgColor,
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.32, 1.0]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors,
                                     locations: locations) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: h),
                                   end: CGPoint(x: 0, y: 0),
                                   options: [])
        }
    }
    return ctx.makeImage()
}

func imageHasTransparentCorners(_ image: NSImage) -> Bool {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
    let alphaInfo = cg.alphaInfo
    switch alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast:
        return false
    default:
        break
    }

    guard let rep = NSBitmapImageRep(cgImage: cg).copy() as? NSBitmapImageRep else { return false }
    let points = [
        NSPoint(x: 0, y: 0),
        NSPoint(x: max(0, rep.pixelsWide - 1), y: 0),
        NSPoint(x: 0, y: max(0, rep.pixelsHigh - 1)),
        NSPoint(x: max(0, rep.pixelsWide - 1), y: max(0, rep.pixelsHigh - 1)),
        NSPoint(x: min(4, max(0, rep.pixelsWide - 1)), y: min(4, max(0, rep.pixelsHigh - 1))),
        NSPoint(x: max(0, rep.pixelsWide - 5), y: min(4, max(0, rep.pixelsHigh - 1))),
        NSPoint(x: min(4, max(0, rep.pixelsWide - 1)), y: max(0, rep.pixelsHigh - 5)),
        NSPoint(x: max(0, rep.pixelsWide - 5), y: max(0, rep.pixelsHigh - 5)),
    ]
    return points.contains { point in
        guard let color = rep.colorAt(x: Int(point.x), y: Int(point.y)) else { return false }
        return color.alphaComponent < 0.92
    }
}

func configurePreviewImageView(_ imageView: NSImageView, image: NSImage) -> Bool {
    let hasSourceRoundedAlpha = imageHasTransparentCorners(image)
    imageView.image = image
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.wantsLayer = true
    if hasSourceRoundedAlpha {
        imageView.layer?.cornerRadius = 0
        imageView.layer?.masksToBounds = false
        imageView.layer?.borderWidth = 0
        imageView.layer?.borderColor = nil
    } else {
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 0.5
        imageView.layer?.borderColor = NSColor.black.withAlphaComponent(0.22).cgColor
    }
    return hasSourceRoundedAlpha
}

func downsampleCGImage(_ image: CGImage, maxPixelSize: CGSize) -> CGImage? {
    let maxWidth = max(1, maxPixelSize.width)
    let maxHeight = max(1, maxPixelSize.height)
    let scale = min(maxWidth / CGFloat(image.width),
                    maxHeight / CGFloat(image.height),
                    1)
    guard scale < 0.999 else { return image }
    let width = max(1, Int(ceil(CGFloat(image.width) * scale)))
    let height = max(1, Int(ceil(CGFloat(image.height) * scale)))
    guard let context = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

func quickWindowPreviewImage(id: CGWindowID, logicalSize: CGSize,
                             maxPixelSize: CGSize = hoverPreviewMaxPixelSize) -> NSImage? {
    let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
    typealias CreateImage = @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?
    struct Loader {
        static let createImage: CreateImage? = {
            guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
                  let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
            return unsafeBitCast(symbol, to: CreateImage.self)
        }()
    }
    guard let createImage = Loader.createImage else { return nil }
    guard let unmanaged = createImage(.null, .optionIncludingWindow, id, options) else { return nil }
    let raw = unmanaged.takeRetainedValue()
    let image = downsampleCGImage(raw, maxPixelSize: maxPixelSize) ?? raw
    return NSImage(cgImage: image, size: logicalSize)
}

// 截图后的标题栏条制备结果：像素分析全部在后台完成，主线程只消费这些值。
struct NativeStripPreparation {
    let barH: CGFloat
    let boundary: String
    let strip: CGImage?
    let brokenHealth: (Bool, String)
    let scale: CGFloat
    let fixedBarH: CGFloat?
    let visualBarH: CGFloat?
    let fallbackBarH: CGFloat
    let standardBarH: CGFloat
}

// 纯 CPU 计算，可在任意线程执行：决定标题栏裁切高度（visual/precise chrome
// 像素扫描）、裁切、原生条健康检查、底部圆角镜像。不触碰 AppKit/AX 状态，
// 因此可以安全地在 pixelAnalysisQueue 上跑。
func prepareNativeStrip(full: CGImage, logicalSize: CGSize,
                        profile: WindowChromeProfile, pid: pid_t) -> NativeStripPreparation {
    let scale = CGFloat(full.width) / max(1, logicalSize.width)
    let minimumBarH = profile.standardCropHeight
    let standardBarH = profile.standardCropHeight
    let fixedBarH = fixedNonstandardChromeHeight(pid: pid)
    let visualBarH = fixedBarH == nil && profile.preciseChrome
        ? preciseVisualChromeHeight(of: full, scale: scale, minimum: minimumBarH)
        : nil
    let fallbackBarH = fixedBarH
        ?? (profile.preciseChrome
            ? (fallbackControlPaddedChromeHeight(pid: pid, minimum: minimumBarH) ?? profile.axBarHeight)
            : profile.axBarHeight)
    let barH: CGFloat
    if profile.isQuickLook {
        barH = min(quickLookOriginalTitleBarHeight, logicalSize.height)
    } else if profile.standardTitleBarOnly {
        barH = standardBarH
    } else {
        barH = min(visualBarH ?? fallbackBarH, min(logicalSize.height, 300))
    }
    let cropHeight = max(1, Int(ceil(barH * scale)))
    let boundary = fixedBarH == nil ? profile.boundaryName : "fixed"
    guard let rawStrip = full.cropping(to: CGRect(x: 0, y: 0, width: full.width, height: cropHeight)) else {
        return NativeStripPreparation(barH: barH, boundary: boundary, strip: nil,
                                      brokenHealth: (false, ""), scale: scale,
                                      fixedBarH: fixedBarH, visualBarH: visualBarH,
                                      fallbackBarH: fallbackBarH, standardBarH: standardBarH)
    }
    let health = nativeTitleStripLooksBroken(rawStrip, logicalHeight: barH)
    let strip = health.0 ? rawStrip : (mirrorRoundCorners(rawStrip) ?? rawStrip)
    return NativeStripPreparation(barH: barH, boundary: boundary, strip: strip,
                                  brokenHealth: health, scale: scale,
                                  fixedBarH: fixedBarH, visualBarH: visualBarH,
                                  fallbackBarH: fallbackBarH, standardBarH: standardBarH)
}
