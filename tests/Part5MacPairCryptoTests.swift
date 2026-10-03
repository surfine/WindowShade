// Synthetic known-key tests of the CryptoKit signature/AEAD layer only. No real SRP or native Remote.
//
// 真机发现：CryptoKit 的 Ed25519 签名加了随机量（同一密钥、同一消息，每次签名都不同），
// 所以不能拿自己产出的 M6 去和 Python 的确定性向量逐字节比。对端验收看的是「它能不能验证」：
// 用同一把会话密钥解封、TLV 结构正确、身份与公钥一致、签名在 Accessory-Sign 上成立。
import Foundation
import CryptoKit
@MainActor final class KnownKeySRP: WS2SRPPrimitive {
    let key: Data
    init(_ key: Data) { self.key = key }
    func begin(pin: String) throws -> (salt: Data, publicKey: Data) { (Data(repeating:1,count:16),Data([5])) }
    func verify(publicKey: Data, proof: Data) throws -> (serverProof: Data, key: Data) { (Data(repeating:2,count:64),key) }
    func clear() {}
}
@main @MainActor struct MacPairCryptoTests {
    static func hex(_ value: String) throws -> Data {
        guard value.count % 2 == 0 else { throw NSError(domain:"hex",code:1) }
        var data = Data(); var index = value.startIndex
        while index != value.endIndex {
            let end = value.index(index,offsetBy:2)
            guard let b = UInt8(value[index..<end],radix:16) else { throw NSError(domain:"hex",code:2) }
            data.append(b); index = end
        }; return data
    }
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw NSError(domain:"usage",code:1) }
        let v = try JSONDecoder().decode([String:String].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        func field(_ k:String) throws -> Data { guard let text = v[k] else { throw NSError(domain:k,code:1) }; return try hex(text) }
        func engine() throws -> WS2PairSetupCrypto {
            let e = try WS2PairSetupCrypto(srp:KnownKeySRP(field("key")),identifier:field("serverID"),signingSeed:field("serverSeed"))
            _ = try e.begin(pin:"0000"); _ = try e.verify(clientPublicKey:Data([5]),proof:Data(repeating:1,count:64)); return e
        }
        func derive(_ suffix: String) throws -> SymmetricKey {
            HKDF<SHA512>.deriveKey(inputKeyMaterial: SymmetricKey(data: try field("key")),
                                   salt: Data("Pair-Setup-\(suffix)-Salt".utf8),
                                   info: Data("Pair-Setup-\(suffix)-Info".utf8), outputByteCount: 32)
        }
        let good = try engine(); let result = try good.finish(encryptedM5:field("m5"))
        guard result.identifier == (try field("clientID")),result.publicKey == (try field("clientPublic")) else { throw NSError(domain:"m5-identity-mismatch",code:1) }
        // Our M6 must satisfy the peer's verification rule: same key, PS-Msg06 nonce, correct TLV and signature.
        let m6 = result.encryptedM6
        guard m6.count >= 16 else { throw NSError(domain:"m6-short",code:1) }
        let box = try ChaChaPoly.SealedBox(nonce:.init(data:Data(repeating:0,count:4)+Data("PS-Msg06".utf8)),
                                           ciphertext:m6.dropLast(16),tag:m6.suffix(16))
        let plain = try ChaChaPoly.open(box,using:try derive("Encrypt"),authenticating:Data())
        let fields = try PairingTLV.decode(plain,allowed:[1,3,10])
        let serverID = try field("serverID"), serverPublic = try field("serverPublic")
        guard fields[1] == serverID, fields[3] == serverPublic, fields[10]?.count == 64 else { throw NSError(domain:"m6-structure",code:1) }
        let accessory = try derive("Accessory-Sign").withUnsafeBytes { Data($0) }
        guard try Curve25519.Signing.PublicKey(rawRepresentation:serverPublic)
            .isValidSignature(fields[10]!,for:accessory + serverID + serverPublic) else { throw NSError(domain:"m6-signature",code:1) }
        // Apple 的实现是随机化签名：再签一次必然字节不同，但两份都必须能验证。
        let second = try engine().finish(encryptedM5:field("m5"))
        guard second.encryptedM6 != m6 else { throw NSError(domain:"signature-not-randomised",code:1) }
        var rejectedRepeat = false
        do { _ = try good.finish(encryptedM5:field("m5")) } catch { rejectedRepeat = true }
        guard rejectedRepeat else { throw NSError(domain:"replay-accepted",code:1) }
        var badSignature = false
        do { _ = try engine().finish(encryptedM5:field("m5BadSignature")) } catch { badSignature = true }
        guard badSignature else { throw NSError(domain:"bad-signature-accepted",code:1) }
        var tampered = try field("m5"); tampered[tampered.count-1] ^= 1
        var badTag = false
        do { _ = try engine().finish(encryptedM5:tampered) } catch { badTag = true }
        guard badTag else { throw NSError(domain:"bad-tag-accepted",code:1) }
        print("PASS: M5 identity/key, verifiable M6 under the peer's rule (signature is randomised by CryptoKit, so bytes are not compared), replay rejection, authenticated wrong-signature rejection, AEAD tampering rejection. SRP is a known-key test double; no native interoperability.")
    }
}
