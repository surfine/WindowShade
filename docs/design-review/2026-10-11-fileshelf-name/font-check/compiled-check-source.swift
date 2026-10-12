import Cocoa
@MainActor
enum FileShelfNameLayout {
    static func lines(_ name: String, width: CGFloat, font: NSFont, maxLines: Int = 2) -> [String] {
        let text = name.map { $0.isNewline ? " " : String($0) }.joined()
        guard width > 0, maxLines > 0 else { return [] }
        func measure(_ value: String) -> CGFloat { NSAttributedString(string: value, attributes: [.font: font]).size().width }
        func prefix(_ value: String, fitting room: CGFloat) -> String {
            var result = ""
            for character in value {
                let next = result + String(character)
                guard measure(next) <= room else { break }
                result = next
            }
            return result
        }
        func suffix(_ value: String, fitting room: CGFloat) -> String {
            var result = ""
            for character in value.reversed() {
                let next = String(character) + result
                guard measure(next) <= room else { break }
                result = next
            }
            return result
        }
        guard measure(text) > width else { return [text] }
        let mark = "…"
        let markWidth = measure(mark)
        guard markWidth <= width else { return [""] }
        let dot = text.lastIndex(of: ".")
        let extensionStart = dot.flatMap { $0 != text.startIndex && text.distance(from: $0, to: text.endIndex) <= 6 ? $0 : nil }
        if maxLines == 1 {
            let extWidth = extensionStart.map { measure(String(text[$0...])) } ?? 0
            let tail = suffix(text, fitting: min(width - markWidth, max(width * 0.4, extWidth)))
            let head = prefix(String(text.dropLast(tail.count)), fitting: width - markWidth - measure(tail))
            return [head + mark + tail]
        }
        var head = prefix(text, fitting: width)
        // 常见扩展名保持完整；不要把 .txt 拆到两行。
        if let extensionStart, head.count > text.distance(from: text.startIndex, to: extensionStart) {
            head = String(text[..<extensionStart])
        }
        let remainder = String(text.dropFirst(head.count))
        if measure(remainder) <= width { return [head, remainder] }
        return [head, mark + suffix(remainder, fitting: width - markWidth)]
    }
}


@main enum NameChecks {
 @MainActor static func main() throws {
  let font=NSFont.systemFont(ofSize:11)
  let names=["样件文件7.txt",String(repeating:"long-file-name-",count:10)+".txt",String(repeating:"W",count:80)+".pdf",String(repeating:"字👨‍👩‍👧‍👦",count:8)+".txt",String(repeating:"很长的文件名",count:12)+".pages",String(repeating:"MMMMMM",count:15),".gitignore", "a\nb.txt"]
  var records:[[String:Any]]=[]
  for maxLines in [1,2] {
   for name in names {
    let lines=FileShelfNameLayout.lines(name,width:68,font:font,maxLines:maxLines)
    let widths=lines.map{NSAttributedString(string:$0,attributes:[.font:font]).size().width}
    let joined=lines.joined()
    let dot=name.lastIndex(of:".")
    let ext=dot.flatMap{$0 != name.startIndex && name.distance(from:$0,to:name.endIndex)<=6 ? String(name[$0...]):nil}
    let preserved=ext.map{lines.last?.hasSuffix($0)==true} ?? true
    let passed=lines.count<=maxLines && widths.allSatisfy{$0<=68} && preserved && joined.filter{$0=="…"}.count<=1 && !joined.contains("\n")
    records.append(["name":name,"maxLines":maxLines,"lines":lines,"widths":widths,"extensionPreserved":preserved,"passed":passed])
    guard passed else {print("FAIL \(records.last!)");exit(1)}
   }
  }
  let data=try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]);try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]));print("PASS \(records.count) actual-font boundary cases")
 }
}
