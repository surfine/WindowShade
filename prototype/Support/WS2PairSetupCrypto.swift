import Foundation

@MainActor protocol WS2SRPPrimitive: AnyObject {
    func begin(pin: String) throws -> (salt: Data, publicKey: Data)
    // key is raw 64-byte SHA-512 session key, never its hexadecimal text.
    func verify(publicKey: Data, proof: Data) throws -> (serverProof: Data, key: Data)
    func clear()
}

#if canImport(CryptoKit)
import CryptoKit

// Original HAP-style signature/AEAD layer; it does not implement Companion OPACK/session negotiation.
@MainActor final class WS2PairSetupCrypto: WS2PairSetupEngine {
    enum Failure: Error { case state, malformed, signature }
    private enum Phase { case fresh, started, proven, finished }
    private var phase: Phase = .fresh
    private let srp: any WS2SRPPrimitive
    private let localIdentifier: Data
    private let signingKey: Curve25519.Signing.PrivateKey
    private var sessionKey: SymmetricKey?
    init(srp: any WS2SRPPrimitive, identifier: Data, signingSeed: Data) throws {
        guard (1...128).contains(identifier.count), signingSeed.count == 32 else { throw Failure.malformed }
        self.srp = srp; localIdentifier = identifier
        signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: signingSeed)
    }
    func begin(pin: String) throws -> (salt: Data, publicKey: Data) {
        guard phase == .fresh else { throw Failure.state }; phase = .started
        return try srp.begin(pin: pin)
    }
    func verify(clientPublicKey: Data, proof: Data) throws -> Data {
        guard phase == .started else { throw Failure.state }
        let result = try srp.verify(publicKey: clientPublicKey, proof: proof)
        guard result.key.count == 64, result.serverProof.count == 64 else { throw Failure.malformed }
        sessionKey = SymmetricKey(data: result.key); phase = .proven
        return result.serverProof
    }
    private func derive(_ suffix: String) throws -> SymmetricKey {
        guard let sessionKey else { throw Failure.state }
        return HKDF<SHA512>.deriveKey(inputKeyMaterial: sessionKey,
            salt: Data("Pair-Setup-\(suffix)-Salt".utf8), info: Data("Pair-Setup-\(suffix)-Info".utf8), outputByteCount: 32)
    }
    private func nonce(_ name: String) throws -> ChaChaPoly.Nonce {
        guard name.utf8.count == 8 else { throw Failure.malformed }
        return try ChaChaPoly.Nonce(data: Data(repeating:0,count:4) + Data(name.utf8))
    }
    func finish(encryptedM5: Data) throws -> (identifier: Data, publicKey: Data, encryptedM6: Data) {
        guard phase == .proven, (16...2048).contains(encryptedM5.count) else { throw Failure.state }
        // A failed M5 cannot be retried under this ephemeral state.
        phase = .finished
        let encryption = try derive("Encrypt")
        let box = try ChaChaPoly.SealedBox(nonce:nonce("PS-Msg05"),ciphertext:Data(encryptedM5.dropLast(16)),tag:Data(encryptedM5.suffix(16)))
        let plain = try ChaChaPoly.open(box,using:encryption,authenticating:Data())
        let fields = try PairingTLV.decode(plain,allowed:[1,3,10,17])
        guard let identifier = fields[1], (1...128).contains(identifier.count),
              let publicKey = fields[3], publicKey.count == 32,
              let signature = fields[10], signature.count == 64, (fields[17]?.count ?? 0) <= 1024 else { throw Failure.malformed }
        // Tag 17 is optional untrusted descriptive OPACK; it is neither an identity nor an authorization claim.
        let controllerX = try derive("Controller-Sign").withUnsafeBytes { Data($0) }
        let peerKey = try Curve25519.Signing.PublicKey(rawRepresentation:publicKey)
        guard peerKey.isValidSignature(signature,for:controllerX + identifier + publicKey) else { throw Failure.signature }
        let accessoryX = try derive("Accessory-Sign").withUnsafeBytes { Data($0) }
        let ownPublic = signingKey.publicKey.rawRepresentation
        let ownSignature = try signingKey.signature(for:accessoryX + localIdentifier + ownPublic)
        let reply = try PairingTLV.encode([(1,localIdentifier),(3,ownPublic),(10,ownSignature)])
        let sealed = try ChaChaPoly.seal(reply,using:encryption,nonce:nonce("PS-Msg06"),authenticating:Data())
        return (identifier,publicKey,sealed.ciphertext + sealed.tag)
    }
    func clear() { srp.clear(); sessionKey = nil; phase = .finished }
}
#endif
