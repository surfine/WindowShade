// 參考圖：把 SF Symbol 用 AppKit 自己畫出來，輸出「螢幕方向」的 PNG。
//
// 只做一件事、不做任何座標轉換推論：畫進 CGContext（y 向上）→ 存 PNG 時保持
// 畫面上看到的樣子。這是我們抽出來的向量要比對的基準。
//
// 用法：swift tools/ref-symbol.swift <符號名> <weight> <尺寸> <輸出.png>
import AppKit
import CoreGraphics
import Foundation

let a = CommandLine.arguments
guard a.count >= 5 else { FileHandle.standardError.write("用法: ref-symbol <name> <weight> <size> <out.png>\n".data(using: .utf8)!); exit(2) }
let name = a[1], weightName = a[2]
let S = Int(a[3]) ?? 512
let outPath = a[4]

func weight(_ s: String) -> NSFont.Weight {
    switch s {
    case "ultralight": return .ultraLight
    case "thin": return .thin
    case "light": return .light
    case "regular": return .regular
    case "medium": return .medium
    case "semibold": return .semibold
    case "bold": return .bold
    case "heavy": return .heavy
    case "black": return .black
    default: return .regular
    }
}

guard let img = NSImage(systemSymbolName: name, accessibilityDescription: name)?
    .withSymbolConfiguration(.init(pointSize: 1400, weight: weight(weightName))) else {
    FileHandle.standardError.write("找不到 \(name)\n".data(using: .utf8)!); exit(1)
}

// 先把符號畫在一張「螢幕方向」的大圖上（左上為原點），量出墨跡框。
let R = 2048
guard let big = CGContext(data: nil, width: R, height: R, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
// 翻成螢幕方向：y 向下
big.translateBy(x: 0, y: CGFloat(R)); big.scaleBy(x: 1, y: -1)
let asz = img.size
big.draw(img.cgImage(forProposedRect: nil, context: nil, hints: nil)!, in: CGRect(x: 200, y: 200, width: asz.width, height: asz.height))
guard let bigImg = big.makeImage(), let dp = big.data else { exit(1) }
let buf = dp.bindMemory(to: UInt8.self, capacity: R * R * 4)
var minX = R, minY = R, maxX = -1, maxY = -1
for y in 0..<R { for x in 0..<R {
    if buf[(y * R + x) * 4 + 3] > 24 {
        if x < minX { minX = x }; if x > maxX { maxX = x }
        if y < minY { minY = y }; if y > maxY { maxY = y }
    }
} }
guard maxX > minX, maxY > minY else { FileHandle.standardError.write("沒有墨跡\n".data(using: .utf8)!); exit(1) }

// 裁墨跡、等比放到 S×S 中央。這一張就是「畫面上看到的樣子」。
let ink = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
guard let cropped = bigImg.cropping(to: ink) else { exit(1) }
guard let out = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
out.translateBy(x: 0, y: CGFloat(S)); out.scaleBy(x: 1, y: -1)   // 一樣是螢幕方向
let k = Swift.min(CGFloat(S) / CGFloat(cropped.width), CGFloat(S) / CGFloat(cropped.height))
let dw = CGFloat(cropped.width) * k, dh = CGFloat(cropped.height) * k
out.interpolationQuality = .high
out.draw(cropped, in: CGRect(x: (CGFloat(S) - dw) / 2, y: (CGFloat(S) - dh) / 2, width: dw, height: dh))
guard let final = out.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: final)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
FileHandle.standardError.write("REF \(name): 墨跡 \(Int(ink.width))×\(Int(ink.height)) → \(S)×\(S)（螢幕方向）\(outPath)\n".data(using: .utf8)!)
