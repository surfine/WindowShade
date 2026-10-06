// 把 SF Symbol 抽成 SVG 的 path（真向量，不是點陣）。
//
// 為什麼是這條路：`NSImage(systemSymbolName:)` 的表示層是私類別 `NSSymbolImageRep`，
// 它握著一個 `CUINamedVectorGlyph`，那個物件有 `CGPath` 方法。`cgImage(forProposedRect:)`
// 或 `draw(in:)` 都會把符號烤成點陣（PDF 內容流裡是 `/Im1 Do` 一張圖），4K 會軟，所以不能用。
//
// ⚠️ 座標方向（這條吃過一次虧，寫清楚，別再翻回去）：
//   `CUINamedVectorGlyph.CGPath` 回來的 y **已經是螢幕方向（y 向下）**，不是一般
//   CoreGraphics 字型那種 y 向上。實測 `checkmark` 的原始資料：右端 (259.68, 0) 是
//   y 最小值、中間底點 (107.92, 221.06) 是接近最大值 → 右端在「高」的地方、底點在
//   「低」的地方，這正是 ✓。所以**原樣輸出即可，不要再翻**。
//   先前多翻了一次 `y → maxY - y`，✓ 就變成 ∧。對稱的符號（faceid、iphone、lock、
//   xmark）看不出來，只有 checkmark 這種上下不對稱的會露餡——所以一律用
//   `tools/overlay-symbols.mjs` 跟 AppKit 自己畫的版本疊圖驗，不靠肉眼。
//
// 用法：
//   swift tools/extract-symbol.swift <符號名> <weight> <抽取點數> <忽略> <輸出路徑> [flip|b64]
//     flip：多做一次上下鏡射。只給疊圖工具 A/B 對照用，正式產物不要用。
//     b64：印出整份 SVG 的 base64（給內嵌用）。
import AppKit
import CoreGraphics
import Foundation

let a = CommandLine.arguments
guard a.count >= 6 else {
    FileHandle.standardError.write("用法: extract-symbol <name> <weight> <pt> <ignored> <out> [flip|b64]\n".data(using: .utf8)!) ; exit(2)
}
let name = a[1]
let weightName = a[2]
let pointSize = CGFloat(Double(a[3]) ?? 160)
let outPath = a[5]
let mode = a.count > 6 ? a[6] : ""
let asBase64 = mode == "b64"
// 預設「不翻」（正確，見上面）；`flip` 是故意做錯的對照組。
let flipY = mode == "flip"

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

guard let img = NSImage(systemSymbolName: name, accessibilityDescription: name) else {
    FileHandle.standardError.write("找不到符號 \(name)\n".data(using: .utf8)!) ; exit(1)
}
guard let configured = img.withSymbolConfiguration(.init(pointSize: pointSize, weight: weight(weightName))) else { exit(1) }
guard let rep = configured.representations.first(where: { String(describing: type(of: $0)) == "NSSymbolImageRep" }) else {
    FileHandle.standardError.write("沒有 NSSymbolImageRep\n".data(using: .utf8)!) ; exit(1)
}
let obj = rep as NSObject

var glyphPath: CGPath? = nil
if obj.responds(to: NSSelectorFromString("vectorGlyph")),
   let g = obj.perform(NSSelectorFromString("vectorGlyph"))?.takeUnretainedValue() as? NSObject,
   g.responds(to: NSSelectorFromString("CGPath")),
   let p = g.perform(NSSelectorFromString("CGPath"))?.takeUnretainedValue() {
    glyphPath = (p as! CGPath)
} else if obj.responds(to: NSSelectorFromString("outlinePath")),
          let b = obj.perform(NSSelectorFromString("outlinePath"))?.takeUnretainedValue() as? NSBezierPath {
    glyphPath = b.cgPath
}
guard let path = glyphPath else {
    FileHandle.standardError.write("兩條路都拿不到 CGPath\n".data(using: .utf8)!) ; exit(1)
}

var raw: [(CGPathElementType, [CGPoint])] = []
var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
func track(_ p: CGPoint) {
    minX = Swift.min(minX, Double(p.x)); maxX = Swift.max(maxX, Double(p.x))
    minY = Swift.min(minY, Double(p.y)); maxY = Swift.max(maxY, Double(p.y))
}
path.applyWithBlock { el in
    let p = el.pointee
    var pts: [CGPoint] = []
    switch p.type {
    case .moveToPoint, .addLineToPoint: pts = [p.points[0]]
    case .addQuadCurveToPoint: pts = [p.points[0], p.points[1]]
    case .addCurveToPoint: pts = [p.points[0], p.points[1], p.points[2]]
    case .closeSubpath: pts = []
    @unknown default: pts = []
    }
    for q in pts { track(q) }
    raw.append((p.type, pts))
}

let w = maxX - minX, h = maxY - minY
// x 不平移：讓所有符號留在同一個設計空間（lock 兩態才能疊在同一個框）。
// y 只在 flipY 時翻成 `maxY - y`，翻完最小值是 0、最大值是 h。
func nx(_ x: CGFloat) -> CGFloat { CGFloat(Double(x)) }
func ny(_ y: CGFloat) -> CGFloat { flipY ? CGFloat(maxY - Double(y)) : CGFloat(Double(y)) }
func num(_ v: CGFloat) -> String {
    let r = (Double(v) * 100).rounded() / 100
    if r == r.rounded() { return String(Int(r)) }
    var t = String(format: "%.2f", r)
    while t.hasSuffix("0") { t.removeLast() }
    if t.hasSuffix(".") { t.removeLast() }
    return t
}
var d = ""
for (type, pts) in raw {
    switch type {
    case .moveToPoint: d += "M\(num(nx(pts[0].x))) \(num(ny(pts[0].y)))"
    case .addLineToPoint: d += "L\(num(nx(pts[0].x))) \(num(ny(pts[0].y)))"
    case .addQuadCurveToPoint: d += "Q\(num(nx(pts[0].x))) \(num(ny(pts[0].y))) \(num(nx(pts[1].x))) \(num(ny(pts[1].y)))"
    case .addCurveToPoint: d += "C\(num(nx(pts[0].x))) \(num(ny(pts[0].y))) \(num(nx(pts[1].x))) \(num(ny(pts[1].y))) \(num(nx(pts[2].x))) \(num(ny(pts[2].y)))"
    case .closeSubpath: d += "Z"
    @unknown default: break
    }
}

let bMinY = flipY ? 0.0 : minY
let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(num(CGFloat(w)))\" height=\"\(num(CGFloat(h)))\" viewBox=\"\(num(CGFloat(minX))) \(num(CGFloat(bMinY))) \(num(CGFloat(w))) \(num(CGFloat(h)))\"><path fill-rule=\"evenodd\" d=\"\(d)\"/></svg>\n"
let boxJSON = "{\"minX\":\(num(nx(CGFloat(minX)))),\"minY\":\(num(CGFloat(bMinY))),\"w\":\(num(CGFloat(w))),\"h\":\(num(CGFloat(h)))}"
FileHandle.standardError.write("\(name)/\(weightName) [\(flipY ? "flip(故意錯)" : "原樣")] 墨跡 \(String(format: "%.2f", w))×\(String(format: "%.2f", h)) units path \(d.count) 字元\n".data(using: .utf8)!)
if asBase64 {
    print(svg.data(using: .utf8)!.base64EncodedString())
} else {
    try! svg.write(toFile: outPath, atomically: true, encoding: .utf8)
    print("\(boxJSON)\t\(d)")
}
