import Foundation
import WSNativeSRP

/// Experimental adapter for the existing protocol. Only the isolated probe links this module.
@MainActor final class WS2NativeSRPPrimitive: WS2SRPPrimitive {
    enum ProofConvention: String {
        case adkPadded = "adk-padded"
        case srptoolsMinimal = "srptools-minimal"
        var native: Int32 {
            switch self {
            case .adkPadded: return Int32(WS_SRP_ADK_PADDED_M2)
            case .srptoolsMinimal: return Int32(WS_SRP_SRPTOOLS_MINIMAL_M2)
            }
        }
    }
    struct Failure: Error { let code: Int32 }
    /// Immutable ownership wrapper; lifetime ends only after its MainActor owner releases it.
    /// All operations on its pointer occur through the MainActor adapter.
    private final class Storage {
        let pointer: OpaquePointer
        init(_ convention: ProofConvention) throws {
            guard let pointer = ws_srp_new(convention.native) else { throw Failure(code: Int32(WS_SRP_CRYPTO)) }
            self.pointer = pointer
        }
        deinit { ws_srp_free(pointer) }
    }
    private let storage: Storage
    // Deliberately no default: the HomeKit ADK / srptools leading-zero M2 difference is unresolved for Companion.
    init(proofConvention: ProofConvention) throws { storage = try Storage(proofConvention) }

    func begin(pin: String) throws -> (salt: Data, publicKey: Data) {
        var pinBytes = Data(pin.utf8)
        defer { pinBytes.resetBytes(in: 0..<pinBytes.count) }
        var salt = Data(repeating: 0, count: 16), publicKey = Data(repeating: 0, count: 384)
        let status = pinBytes.withUnsafeBytes { pinBuffer in
            salt.withUnsafeMutableBytes { saltBuffer in
                publicKey.withUnsafeMutableBytes { publicBuffer in
                    ws_srp_begin(storage.pointer, pinBuffer.bindMemory(to: UInt8.self).baseAddress, pinBuffer.count,
                                 saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                                 publicBuffer.bindMemory(to: UInt8.self).baseAddress)
                }
            }
        }
        guard status == WS_SRP_OK else { throw Failure(code: status) }
        return (salt, publicKey)
    }
    func verify(publicKey: Data, proof: Data) throws -> (serverProof: Data, key: Data) {
        var serverProof = Data(repeating: 0, count: 64), key = Data(repeating: 0, count: 64)
        let status = publicKey.withUnsafeBytes { publicBuffer in
            proof.withUnsafeBytes { proofBuffer in
                serverProof.withUnsafeMutableBytes { serverBuffer in
                    key.withUnsafeMutableBytes { keyBuffer in
                        ws_srp_verify(storage.pointer, publicBuffer.bindMemory(to: UInt8.self).baseAddress, publicBuffer.count,
                                      proofBuffer.bindMemory(to: UInt8.self).baseAddress, proofBuffer.count,
                                      serverBuffer.bindMemory(to: UInt8.self).baseAddress,
                                      keyBuffer.bindMemory(to: UInt8.self).baseAddress)
                    }
                }
            }
        }
        guard status == WS_SRP_OK else {
            key.resetBytes(in: 0..<key.count)
            throw Failure(code: status)
        }
        return (serverProof, key)
    }
    func clear() { ws_srp_clear(storage.pointer) }
}
