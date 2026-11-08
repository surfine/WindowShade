import SceneKit
import Foundation

// 用法：swift dump.swift file.usdz [rootName]
// 每个带几何体的节点：世界坐标包围盒（模型单位）、顶点数、材质漫反射（颜色或贴图名）。
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let scene = try SCNScene(url: url, options: [.convertToYUp: false])

func desc(_ c: Any?) -> String {
  if let col = c as? NSColor, let s = col.usingColorSpace(.sRGB) {
    return String(format: "#%02x%02x%02x", Int(s.redComponent * 255), Int(s.greenComponent * 255), Int(s.blueComponent * 255))
  }
  if let u = c as? URL { return u.lastPathComponent }
  if let s = c as? String { return s }
  if c == nil { return "-" }
  return "\(type(of: c!))"
}

// 第二个参数：逗号分隔的网格名，把这些网格的世界坐标顶点写成 v_<名>.f32（x y z 连续 float32）。
let wanted = Set(CommandLine.arguments.count > 2 ? CommandLine.arguments[2].split(separator: ",").map(String.init) : [])
let outDir = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "."

var rows: [String] = []
scene.rootNode.enumerateHierarchy { n, _ in
  guard let g = n.geometry else { return }
  var lo = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
  var hi = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
  var count = 0
  var out: [Float] = []
  let keep = wanted.contains(n.name ?? "")
  for src in g.sources(for: .vertex) {
    let stride = src.dataStride, off = src.dataOffset
    src.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      for i in 0..<src.vectorCount {
        let b = raw.baseAddress!.advanced(by: i * stride + off)
        let x = b.load(as: Float.self), y = b.advanced(by: 4).load(as: Float.self), z = b.advanced(by: 8).load(as: Float.self)
        let w = n.convertPosition(SCNVector3(x, y, z), to: nil)
        lo = SCNVector3(min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z))
        hi = SCNVector3(max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z))
        count += 1
        if keep { out += [Float(w.x), Float(w.y), Float(w.z)] }
      }
    }
  }
  if keep {
    let data = out.withUnsafeBufferPointer { Data(buffer: $0) }
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/v_\(n.name!).f32"))
    var idx: [UInt32] = []
    for el in g.elements {
      el.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        func at(_ i: Int) -> UInt32 {
          switch el.bytesPerIndex {
          case 1: return UInt32(raw.load(fromByteOffset: i, as: UInt8.self))
          case 2: return UInt32(raw.load(fromByteOffset: i * 2, as: UInt16.self))
          default: return raw.load(fromByteOffset: i * 4, as: UInt32.self)
          }
        }
        if el.primitiveType == .triangles {
          for i in 0..<(el.primitiveCount * 3) { idx.append(at(i)) }
        } else if el.primitiveType == .polygon {
          // 前 primitiveCount 个是每个多边形的顶点数，后面是索引；按扇形拆成三角形。
          var k = el.primitiveCount
          for p in 0..<el.primitiveCount {
            let c = Int(at(p))
            for j in 1..<(c - 1) { idx += [at(k), at(k + j), at(k + j + 1)] }
            k += c
          }
        }
      }
    }
    let idata = idx.withUnsafeBufferPointer { Data(buffer: $0) }
    try? idata.write(to: URL(fileURLWithPath: "\(outDir)/i_\(n.name!).u32"))
  }
  let mats = g.materials.map { m -> String in
    "\(m.name ?? "?")=\(desc(m.diffuse.contents)) r\(desc(m.roughness.contents)) m\(desc(m.metalness.contents))"
  }.joined(separator: " | ")
  rows.append(String(format: "%@\tv%d\tx[%.3f, %.3f] y[%.3f, %.3f] z[%.3f, %.3f]\tsize %.3f×%.3f×%.3f\t%@",
                     n.name ?? "?", count, lo.x, hi.x, lo.y, hi.y, lo.z, hi.z, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, mats))
}
print(rows.joined(separator: "\n"))
