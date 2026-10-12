import Foundation
enum FileShelfTileName {
    /// 一行大约放 12 个西文字符或 6 个汉字；两行一共 24 个“字宽”。
    static let units = 22
    static let staleUnits = 10

    static func width(of c: Character) -> Int { c.unicodeScalars.contains { $0.value >= 0x2E80 } ? 2 : 1 }
    static func width(of s: String) -> Int { s.reduce(0) { $0 + width(of: $1) } }

    static func display(_ name: String, units limit: Int = units) -> String {
        guard width(of: name) > limit else { return name }
        let dot = name.lastIndex(of: ".")
        var ext = "", base = name
        if let dot, dot != name.startIndex, name.distance(from: dot, to: name.endIndex) <= 6 {
            ext = String(name[dot...]); base = String(name[..<dot])
        }
        let budget = max(2, limit - width(of: ext) - 1)
        let head = Int((Double(budget) * 0.6).rounded(.up)), tail = budget - head
        var h = "", hw = 0
        for c in base { let w = width(of: c); if hw + w > head { break }; h.append(c); hw += w }
        var t = "", tw = 0
        for c in base.reversed() { let w = width(of: c); if tw + w > tail { break }; t.insert(c, at: t.startIndex); tw += w }
        return h + "…" + t + ext
    }

    /// 失效的格：名字只留短短一行，下面写原因。
    static func stale(_ name: String, reason: String) -> String { display(name, units: staleUnits) + "\n" + reason }
}


import Cocoa
@main enum Measure {
 static func main() throws {
  let name=String(repeating:"long-file-name-",count:10)+".txt"
  let shown=FileShelfTileName.display(name)
  let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center;paragraph.lineBreakMode = .byWordWrapping;paragraph.minimumLineHeight=13;paragraph.maximumLineHeight=13
  let text=NSAttributedString(string:shown,attributes:[.font:NSFont.systemFont(ofSize:11),.paragraphStyle:paragraph])
  let measured=text.boundingRect(with:NSSize(width:68,height:1000),options:[.usesLineFragmentOrigin])
  let result:[String:Any]=["fullName":name,"coreDisplay":shown,"drawingWidth":68,"drawingHeight":28,"untruncatedTextHeight":measured.height,"untruncatedTextWidth":measured.width,"fullDisplayPreservesExtension":shown.hasSuffix(".txt"),"tooTallForDrawName":measured.height>28]
  let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]);try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]));print(String(data:data,encoding:.utf8)!)
 }
}
