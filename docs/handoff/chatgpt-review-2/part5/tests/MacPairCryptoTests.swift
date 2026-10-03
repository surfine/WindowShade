// Synthetic known-key tests of the CryptoKit signature/AEAD layer only. No real SRP or native Remote.
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
        let good = try engine(); let result = try good.finish(encryptedM5:field("m5"))
        guard result.identifier == (try field("clientID")),result.publicKey == (try field("clientPublic")),result.encryptedM6 == (try field("m6")) else { throw NSError(domain:"vector-mismatch",code:1) }
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
        print("PASS: M5 identity/key, exact M6 bytes, replay rejection, authenticated wrong-signature rejection, AEAD tampering rejection. SRP is a known-key test double; no native interoperability.")
    }
}
