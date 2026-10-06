// 官方渲染：AppKit 自己畫的 SF Symbol，裁到墨跡框、等比縮成 512×512 並置中。
// 用途：跟我們抽出來的 SVG path 疊圖，證明轉換對不對。
//
// 這一版把「回報的數字」改成量**存檔後那張 512×512** 的墨跡，不再量縮放前的 bitmap：
// 先前印出的「3340×2855」是縮放前的框，跟存下來的檔案對不上（`checkmark.circle.fill`
// 是圓，檔案量起來是 438×438 比例 1.000，但印出來的是比例 1.17），
// 那種數字會把後面疊圖的歸正帶偏，所以直接讓回報等於檔案。
//
// 用法：swift tools/official-symbol.swift <符號名> <weight> <輸出路徑.png>
import AppKit
import CoreGraphics
import Foundation

let a = CommandLine.arguments
guard a.count >= 4 else { FileHandle.standardError.write("用法: official-symbol <name> <weight> <out.png>\n".data(using: .utf8)!); exit(2) }
let name = a[1]
let weightName = a[2]
let outPath = a[3]
let S = 512

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

// 先畫到很大的畫布，墨跡才不會被切到，再裁墨跡、等比縮到 512。
guard let base = NSImage(systemSymbolName: name, accessibilityDescription: name)?
    .withSymbolConfiguration(.init(pointSize: 1200, weight: weight(weightName))),
    let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("找不到 \(name)\n".data(using: .utf8)!); exit(1)
}
let W = cg.width, H = cg.height
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
guard let data = ctx.data else { exit(1) }
let bpr = ctx.bytesPerRow          // ⚠️ 可能大於 width*4（每列有補齊位元組）
let buf = data.bindMemory(to: UInt8.self, capacity: bpr * H)
// 門檻 96（不是 24）：符號邊緣有一圈很淡的抗鋸齒，用太低的門檻會多量一圈暈。
// 索引一定要用 bytesPerRow，不能寫 width*4——先前「圓 1.000、faceid 卻 1.253」
// 就是因為漏了每列補齊，量到歪掉的框。
func inkBox(_ w: Int, _ h: Int, _ b: UnsafeMutablePointer<UInt8>, _ stride: Int) -> (Int, Int, Int, Int)? {
    var x0 = w, y0 = h, x1 = -1, y1 = -1
    for y in 0..<h {
        let row = y * stride
        for x in 0..<w {
            if b[row + x * 4 + 3] > 96 { if x < x0 { x0 = x }; if x > x1 { x1 = x }; if y < y0 { y0 = y }; if y > y1 { y1 = y } }
        }
    }
    return x1 >= x0 ? (x0, y0, x1, y1) : nil
}
guard let ib = inkBox(W, H, buf, bpr) else { FileHandle.standardError.write("沒有墨跡\n".data(using: .utf8)!); exit(1) }
let ink = CGRect(x: ib.0, y: ib.1, width: ib.2 - ib.0 + 1, height: ib.3 - ib.1 + 1)
guard let cropped = ctx.makeImage()?.cropping(to: ink) else { exit(1) }

// 直接輸出「裁到墨跡框」的原始點陣，不做縮放：疊圖那一端會把兩邊都正規化到自己的墨跡框，
// 這樣就完全不會有我這邊縮放出錯的空間（先前那次「縮成 512」實際上沒縮，回報跟檔案對不上）。
try! NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
FileHandle.standardError.write(String(
    format: "官方 %@ [%@]: 墨跡框 (%d,%d,%d,%d) → %d×%d 比例 %.3f（原始點陣，未縮放）\n",
    name, weightName, ib.0, ib.1, ib.2, ib.3, ib.2 - ib.0 + 1, ib.3 - ib.1 + 1,
    Double(ib.2 - ib.0 + 1) / Double(ib.3 - ib.1 + 1)).data(using: .utf8)!)
