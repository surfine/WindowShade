// Sparkle 2 清单签名小工具（只给 tests/vm/run-updater-phase3.sh 用，不碰钥匙串、不碰真私钥）。
//   keygen                     打印 "私钥base64 公钥base64"（一次性测试密钥）
//   sign   <私钥base64> <文件> 打印文件全部字节的 Ed25519 签名（base64）
//   verify <公钥base64> <清单> 按 Sparkle 的规则验清单末尾 sparkle-signatures 块：签名覆盖块之前的全部字节
import Foundation
import CryptoKit

let a = CommandLine.arguments
func fail(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(2) }
guard a.count >= 2 else { fail("usage: keygen | sign <priv> <file> | verify <pub> <feed>") }
switch a[1] {
case "keygen":
    let k = Curve25519.Signing.PrivateKey()
    print(k.rawRepresentation.base64EncodedString(), k.publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard a.count == 4, let raw = Data(base64Encoded: a[2]), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw),
          let body = FileManager.default.contents(atPath: a[3]) else { fail("sign: bad arguments") }
    print(try! key.signature(for: body).base64EncodedString())
case "verify":
    guard a.count == 4, let raw = Data(base64Encoded: a[2]), let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
          let all = FileManager.default.contents(atPath: a[3]),
          let r = all.range(of: Data("<!-- sparkle-signatures:".utf8)) else { fail("verify: bad arguments or no signature block") }
    let body = all.subdata(in: 0..<r.lowerBound)
    let tail = String(decoding: all.subdata(in: r.lowerBound..<all.count), as: UTF8.self)
    guard let line = tail.split(separator: "\n").first(where: { $0.hasPrefix("edSignature: ") }),
          let sig = Data(base64Encoded: String(line.dropFirst(13))) else { fail("verify: no edSignature line") }
    print(pub.isValidSignature(sig, for: body) ? "OK" : "BAD")
    exit(pub.isValidSignature(sig, for: body) ? 0 : 1)
default: fail("unknown command")
}
