// Original adapter for one pinned external dependency. Kept OUTSIDE prototype until dependency acceptance.
// Primary source review found the library's convenience proof API pads A/B/S. This adapter defines
// candidate HAP byte encoding explicitly and must pass independent vectors before hardware admission.
import Foundation
import CryptoKit
import SRP

@MainActor final class WS2SRPAdapter: WS2SRPPrimitive {
    enum Failure: Error { case state, invalidKey, proof }
    private let configuration = SRPConfiguration<CryptoKit.SHA512>(.N3072,padGeneratorForProof:false)
    private var keys: SRPKeyPair?
    private var verifier: SRPKey?
    private var salt: Data?
    private var used = false
    // Diagnostic-only deterministic keys belong in the test harness, never in this initializer.
    func begin(pin: String) throws -> (salt: Data, publicKey: Data) {
        guard !used, keys == nil, pin.utf8.count == 4, pin.utf8.allSatisfy({(48...57).contains($0)}) else { throw Failure.state }
        used = true
        let generated = SRPClient(configuration:configuration).generateSaltAndVerifier(username:"Pair-Setup",password:pin,saltLength:16)
        let keys = SRPServer(configuration:configuration).generateKeys(verifier:generated.verifier)
        self.keys = keys; verifier = generated.verifier; salt = Data(generated.salt)
        return (Data(generated.salt),Data(keys.public.unpaddedBytes))
    }
    func verify(publicKey: Data, proof: Data) throws -> (serverProof: Data, key: Data) {
        guard let keys, let verifier, let salt else { throw Failure.state }
        defer { clear() }
        guard (1...384).contains(publicKey.count), proof.count == 64 else { throw Failure.invalidKey }
        let client = SRPKey(publicKey,padding:384)
        guard client.unpaddedBytes.contains(where:{$0 != 0}), client.number < configuration.N else { throw Failure.invalidKey }
        let u = Data(CryptoKit.SHA512.hash(data:Data(client.bytes + keys.public.bytes)))
        guard u.contains(where:{$0 != 0}) else { throw Failure.invalidKey }
        let shared = try SRPServer(configuration:configuration).calculateSharedSecret(clientPublicKey:client,serverKeys:keys,verifier:verifier)
        let key = Data(CryptoKit.SHA512.hash(data:Data(shared.unpaddedBytes)))
        let nHash = [UInt8](CryptoKit.SHA512.hash(data:Data(configuration.N.bytes)))
        let gHash = [UInt8](CryptoKit.SHA512.hash(data:Data(configuration.g.bytes)))
        let xor = Data(zip(nHash,gHash).map { $0 ^ $1 })
        let expected = Data(CryptoKit.SHA512.hash(data:xor + Data(CryptoKit.SHA512.hash(data:Data("Pair-Setup".utf8))) + salt + Data(client.unpaddedBytes) + Data(keys.public.unpaddedBytes) + key))
        // Use CryptoKit's authentication-code verification rather than a short-circuit byte comparison.
        let comparisonKey = SymmetricKey(size:.bits256)
        let tag = HMAC<CryptoKit.SHA256>.authenticationCode(for:expected,using:comparisonKey)
        guard HMAC<CryptoKit.SHA256>.isValidAuthenticationCode(tag,authenticating:proof,using:comparisonKey) else { throw Failure.proof }
        let serverProof = Data(CryptoKit.SHA512.hash(data:Data(client.unpaddedBytes) + proof + key))
        return (serverProof,key)
    }
    func clear() { keys = nil; verifier = nil; salt = nil }
}
