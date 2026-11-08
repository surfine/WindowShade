// 找出一個物件（與它的父類）有哪些方法，用來認出私有 API 的真正 selector。
import Foundation
import ObjectiveC
import AppKit

func dumpMethods(_ cls: AnyClass, label: String) {
    var c: AnyClass? = cls
    var depth = 0
    while let cur = c, depth < 6 {
        var n: UInt32 = 0
        guard let list = class_copyMethodList(cur, &n) else { break }
        var names: [String] = []
        for i in 0..<Int(n) {
            let sel = method_getName(list[i])
            names.append(NSStringFromSelector(sel))
        }
        free(list)
        let interesting = names.filter {
            let l = $0.lowercased()
            return l.contains("path") || l.contains("vector") || l.contains("glyph") || l.contains("pdf") || l.contains("svg") || l.contains("layer") || l.contains("draw")
        }
        print("[\(label)] \(NSStringFromClass(cur)) (\(names.count) 個方法)")
        for s in interesting.sorted() { print("      \(s)") }
        c = class_getSuperclass(cur)
        depth += 1
    }
}

let syms = ["faceid", "iphone", "checkmark", "lock.fill"]
for s in syms {
    guard let img = NSImage(systemSymbolName: s, accessibilityDescription: nil) else { print("\(s): 沒有"); continue }
    for rep in img.representations {
        dumpMethods(type(of: rep), label: "\(s) rep")
    }
}

// CoreUI 的 CUICatalog / CUINamedVectorGlyph
let coreUI = "/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI"
if let h = dlopen(coreUI, RTLD_NOW) {
    for cname in ["CUICatalog", "CUINamedVectorGlyph", "CUINamedImage", "_CUIThemeSVGRendition"] {
        if let cls = NSClassFromString(cname) { dumpMethods(cls, label: cname) }
    }
    dlclose(h)
} else { print("CoreUI 開不了:", String(cString: dlerror())) }
