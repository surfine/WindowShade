import Cocoa

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
