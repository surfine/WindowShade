import CryptoKit
import Foundation
import Security

// App 内的原生 HAP SRP-6a 服务端（3072 位 RFC 5054 组、g=5、SHA-512），实现 WS2SRPPrimitive。
// 算法逐行对照隔离探针的 C 版（tools/probes/companion-pairing/WSNativeSRP.c，Apache-2.0，
// 向量取自 HomeKitADK fb201f98）；这里用定点 32 位 limb 的 Montgomery 算术重写，不依赖 OpenSSL。
// 官方向量与 C 交叉验证见 tests/WS2PureSRPTests.swift 与 tests/run-srp-cross-check.sh。
//
// 已知边界：模乘不是常数时间（比较与减法有数据依赖分支）。配对窗口 60 秒、
// 私钥 b 每次会话重抽；常数时间化留给后续审计轮，不冒充已加固。

/// SRP 原语的协议面：WS2PairSetupCrypto 只认这个，不关心后面是纯 Swift 还是探针的 C。
@MainActor protocol WS2SRPPrimitive: AnyObject {
    func begin(pin: String) throws -> (salt: Data, publicKey: Data)
    // key is raw 64-byte SHA-512 session key, never its hexadecimal text.
    func verify(publicKey: Data, proof: Data) throws -> (serverProof: Data, key: Data)
    func clear()
}

// MARK: - 定点大数（96 × 32 位 limb，小端）

/// 固定 3072 位无符号数。只服务 SRP 的模运算，不做通用大数。
struct WS2SRPBig: Equatable {
    static let limbs = 96
    var words: [UInt32] // 小端；恒为 limbs 个

    init(zero: Void = ()) { words = [UInt32](repeating: 0, count: Self.limbs) }
    init(one: Void = ()) {
        self.init(zero: ())
        words[0] = 1
    }

    /// 大端字节（自动补零）；超过 384 字节返回 nil。
    init?(bigEndian bytes: [UInt8]) {
        guard bytes.count <= 384 else { return nil }
        self.init(zero: ())
        var index = 0
        for byte in bytes.reversed() {
            words[index / 4] |= UInt32(byte) << UInt32(8 * (index % 4))
            index += 1
        }
    }

    /// 大端 384 字节（高位补零）。
    var bigEndian384: [UInt8] {
        var out = [UInt8](repeating: 0, count: Self.limbs * 4)
        for index in 0..<Self.limbs {
            out[index * 4 + 0] = UInt8(truncatingIfNeeded: words[index])
            out[index * 4 + 1] = UInt8(truncatingIfNeeded: words[index] >> 8)
            out[index * 4 + 2] = UInt8(truncatingIfNeeded: words[index] >> 16)
            out[index * 4 + 3] = UInt8(truncatingIfNeeded: words[index] >> 24)
        }
        return out.reversed()
    }

    var isZero: Bool { words.allSatisfy { $0 == 0 } }

    func compare(_ other: WS2SRPBig) -> Int {
        for index in stride(from: Self.limbs - 1, through: 0, by: -1) {
            if words[index] < other.words[index] { return -1 }
            if words[index] > other.words[index] { return 1 }
        }
        return 0
    }

    /// 减法；被减数小于减数时返回 nil。
    static func - (lhs: WS2SRPBig, rhs: WS2SRPBig) -> WS2SRPBig? {
        var borrowed = false
        var out = WS2SRPBig(zero: ())
        for index in 0..<Self.limbs {
            let left = UInt64(lhs.words[index])
            let right = UInt64(rhs.words[index]) + (borrowed ? 1 : 0)
            if left >= right {
                out.words[index] = UInt32(left - right)
                borrowed = false
            } else {
                out.words[index] = UInt32(left + 0x1_0000_0000 - right)
                borrowed = true
            }
        }
        return borrowed ? nil : out
    }
}

// MARK: - Montgomery 上下文

/// 固定模数 N 的 Montgomery 算术：模乘与模幂。R = 2^3072。
struct WS2SRPMontgomery {
    let modulus: WS2SRPBig
    /// -N^{-1} mod 2^32。
    private let inverse0: UInt32
    /// R^2 mod N，用于进出 Montgomery 表示。
    private let rSquared: WS2SRPBig

    init?(modulus: WS2SRPBig) {
        guard !modulus.isZero, modulus.words[0] & 1 == 1 else { return nil }
        self.modulus = modulus
        var inverse: UInt32 = 1
        for _ in 0..<32 {
            inverse = inverse &* (2 &- modulus.words[0] &* inverse)
        }
        inverse0 = 0 &- inverse
        // R^2 mod N：从 1 起做 6144 次模翻倍（R = 2^3072，R^2 = 2^6144）。
        var square = WS2SRPBig(one: ())
        for _ in 0..<(384 * 8 * 2) {
            square = Self.modAdd(square, square, modulus)
        }
        rSquared = square
    }

    /// a + b mod N（输入须 < N）。和最多 2N−2，可能跨过 2^3072：
    /// 进位时回绕语义等价于加回 2^3072−N（即对 N 取模），不能做不回绕的减法。
    static func modAdd(_ a: WS2SRPBig, _ b: WS2SRPBig, _ modulus: WS2SRPBig) -> WS2SRPBig {
        var carry: UInt64 = 0
        var out = WS2SRPBig(zero: ())
        for index in 0..<WS2SRPBig.limbs {
            let sum = UInt64(a.words[index]) &+ UInt64(b.words[index]) &+ carry
            out.words[index] = UInt32(truncatingIfNeeded: sum)
            carry = sum >> 32
        }
        if carry == 1 {
            // out_wrapped = a+b−2^3072；答案 = a+b−N = out_wrapped + (2^3072−N)。
            // 常量按位取反加一就是 2^3072−N；两数之和 < N，不会再进位。
            var bringBack: UInt64 = 1
            for index in 0..<WS2SRPBig.limbs {
                let sum = UInt64(~modulus.words[index]) + bringBack + UInt64(out.words[index])
                out.words[index] = UInt32(truncatingIfNeeded: sum)
                bringBack = sum >> 32
            }
        } else if out.compare(modulus) >= 0 {
            out = (out - modulus) ?? out
        }
        return out
    }

    /// Montgomery 乘（两步 REDC）：a·b·R^{-1} mod N。a、b 须 < N。
    /// 先算 192-limb 全积，再逐 limb 消低位；结果可达 2N（第 97 个 limb 有值），
    /// 条件减法前必须把它算进去——这里踩过坑，Python 参照机验过四个随机用例。
    func multiply(_ a: WS2SRPBig, _ b: WS2SRPBig) -> WS2SRPBig {
        let s = WS2SRPBig.limbs
        let n = modulus.words
        var product = [UInt32](repeating: 0, count: 2 * s + 2)
        for i in 0..<s {
            var carry: UInt64 = 0
            for j in 0..<s {
                let total = UInt64(product[i + j]) &+ UInt64(a.words[i]) &* UInt64(b.words[j]) &+ carry
                product[i + j] = UInt32(truncatingIfNeeded: total)
                carry = total >> 32
            }
            product[i + s] = product[i + s] &+ UInt32(truncatingIfNeeded: carry)
        }
        for i in 0..<s {
            let m = product[i] &* inverse0
            var carry: UInt64 = 0
            for j in 0..<s {
                let total = UInt64(product[i + j]) &+ UInt64(m) &* UInt64(n[j]) &+ carry
                product[i + j] = UInt32(truncatingIfNeeded: total)
                carry = total >> 32
            }
            var k = i + s
            while carry != 0 {
                let total = UInt64(product[k]) &+ carry
                product[k] = UInt32(truncatingIfNeeded: total)
                carry = total >> 32
                k += 1
            }
        }
        let high = product[2 * s] | product[2 * s + 1]
        var words = Array(product[s..<(2 * s)])
        var subtract = high != 0
        if !subtract {
            for index in stride(from: s - 1, through: 0, by: -1) {
                if words[index] != n[index] { subtract = words[index] > n[index]; break }
            }
        }
        if subtract {
            var borrowed = false
            for index in 0..<s {
                let left = UInt64(words[index])
                let right = UInt64(n[index]) + (borrowed ? 1 : 0)
                if left >= right { words[index] = UInt32(left - right); borrowed = false }
                else { words[index] = UInt32(left &+ 0x1_0000_0000 - right); borrowed = true }
            }
        }
        var out = WS2SRPBig(zero: ())
        out.words = words
        return out
    }

    func toMontgomery(_ value: WS2SRPBig) -> WS2SRPBig { multiply(value, rSquared) }
    func fromMontgomery(_ value: WS2SRPBig) -> WS2SRPBig { multiply(value, WS2SRPBig(one: ())) }

    /// base^exponent mod N（MSB 起平方-乘；结果 < N）。
    func power(_ base: WS2SRPBig, exponent: WS2SRPBig) -> WS2SRPBig {
        var result = toMontgomery(WS2SRPBig(one: ()))
        let montBase = toMontgomery(base)
        var seenSetBit = false
        for index in stride(from: WS2SRPBig.limbs - 1, through: 0, by: -1) {
            let word = exponent.words[index]
            for bit in stride(from: 31, through: 0, by: -1) {
                if seenSetBit { result = multiply(result, result) }
                if word >> UInt32(bit) & 1 == 1 {
                    result = seenSetBit ? multiply(result, montBase) : montBase
                    seenSetBit = true
                }
            }
        }
        return fromMontgomery(result)
    }

}

// MARK: - SHA-512 工具

private func sha512(_ parts: [[UInt8]]) -> [UInt8] {
    var hasher = SHA512()
    for part in parts { hasher.update(data: Data(part)) }
    return Array(hasher.finalize())
}

private func leadingZeros(_ bytes: [UInt8]) -> Int {
    var index = 0
    while index < bytes.count, bytes[index] == 0 { index += 1 }
    return index
}

// MARK: - SRP 服务端

/// WS2SRPPrimitive 的纯 Swift 实现。M2 规约与 C 版一致：srptoolsMinimal 是真机验收过的路径。
@MainActor
final class WS2PureSRP: WS2SRPPrimitive {
    enum Failure: Error {
        case state, input, proof, random
    }

    enum ProofConvention {
        /// A 前导零补齐到 384 字节再入哈希（HomeKitADK）。
        case adkPadded
        /// A 去前导零入哈希（srptools；iPhone 真机配对通过的是这个）。
        case srptoolsMinimal
    }

    /// RFC 5054 附录 A 的 3072 位 MODP 组（生成元 5）。
    static let primeHex = "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74" +
        "020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F1437" +
        "4FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED" +
        "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF05" +
        "98DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB" +
        "9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B" +
        "E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF695581718" +
        "3995497CEA956AE515D2261898FA051015728E5A8AAAC42DAD33170D04507A33" +
        "A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7" +
        "ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864" +
        "D87602733EC86A64521F2B18177B200CBBE117577A615D6C770988C0BAD946E2" +
        "08E24FA074E5AB3143DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF"

    static let generator: UInt32 = 5

    static let modulusBig: WS2SRPBig = {
        var bytes: [UInt8] = []
        var iterator = primeHex.makeIterator()
        while let high = iterator.next(), let low = iterator.next() {
            bytes.append(UInt8(String([high, low]), radix: 16) ?? 0)
        }
        return WS2SRPBig(bigEndian: bytes)!
    }()

    static let generatorBig: WS2SRPBig = {
        var value = WS2SRPBig(zero: ())
        value.words[0] = generator
        return value
    }()

    private let montgomery: WS2SRPMontgomery
    private let convention: ProofConvention
    private enum Phase { case fresh, started, consumed }
    private var phase: Phase = .fresh
    private var user = [UInt8]()
    private var salt = [UInt8](repeating: 0, count: 16)
    private var privateKey = WS2SRPBig(zero: ())
    private var verifier = WS2SRPBig(zero: ())
    private var publicB = WS2SRPBig(zero: ())

    init(convention: ProofConvention = .srptoolsMinimal) {
        self.convention = convention
        montgomery = WS2SRPMontgomery(modulus: Self.modulusBig)!
    }

    /// 交叉验证诊断口：verify 内部算出的期望 M1、会话密钥与预主密钥（被拒绝时也返回，供对拍）。
    private(set) var diagnosticExpectedM1: [UInt8] = []
    private(set) var diagnosticKey: [UInt8] = []
    private(set) var diagnosticS: [UInt8] = []

    func debugVerifier() -> WS2SRPBig { verifier }

    /// 官方向量与交叉验证的只读观察口；返回副本，不参与协议。
    var _verifierForTesting: () -> [UInt8] { { [verifier] in verifier.bigEndian384 } }
    var _publicBForTesting: () -> [UInt8] { { [publicB] in publicB.bigEndian384 } }

    func begin(pin: String) throws -> (salt: Data, publicKey: Data) {
        guard phase == .fresh else { clear(); throw Failure.state }
        phase = .consumed
        let pinBytes = Array(pin.utf8)
        guard (1...64).contains(pinBytes.count) else { clear(); throw Failure.input }
        var randomSalt = [UInt8](repeating: 0, count: 16)
        var randomB = [UInt8](repeating: 0, count: 32)
        let status = randomSalt.withUnsafeMutableBytes { saltBuffer in
            randomB.withUnsafeMutableBytes { keyBuffer in
                let saltStatus = SecRandomCopyBytes(kSecRandomDefault, 16, saltBuffer.baseAddress!)
                let keyStatus = SecRandomCopyBytes(kSecRandomDefault, 32, keyBuffer.baseAddress!)
                return saltStatus == errSecSuccess ? keyStatus : saltStatus
            }
        }
        guard status == errSecSuccess else { clear(); throw Failure.random }
        try beginFixed(user: Array("Pair-Setup".utf8), pin: pinBytes, salt: randomSalt, privateKey: randomB)
        return (Data(salt), Data(publicB.bigEndian384))
    }

    /// 官方向量与 C 交叉验证走这里：盐、私钥由外部给定。
    func beginFixed(user fixedUser: [UInt8], pin: [UInt8], salt fixedSalt: [UInt8], privateKey fixedKey: [UInt8]) throws {
        guard (1...128).contains(fixedUser.count), (1...64).contains(pin.count),
              fixedSalt.count == 16, fixedKey.count == 32,
              let key = WS2SRPBig(bigEndian: fixedKey), !key.isZero
        else { clear(); throw Failure.input }
        user = fixedUser
        salt = fixedSalt
        privateKey = key
        let inner = sha512([fixedUser, [0x3a], pin])
        let xBytes = sha512([fixedSalt, inner])
        guard let x = WS2SRPBig(bigEndian: xBytes) else { clear(); throw Failure.input }
        // k = H(N | g)，两者都补齐 384。
        let kBytes = sha512([Self.modulusBig.bigEndian384, Self.generatorBig.bigEndian384])
        guard let k = WS2SRPBig(bigEndian: kBytes) else { clear(); throw Failure.input }
        verifier = montgomery.power(Self.generatorBig, exponent: x)
        let gb = montgomery.power(Self.generatorBig, exponent: privateKey)
        // B = (k·v + g^b) mod N
        let kv = montgomery.fromMontgomery(montgomery.multiply(montgomery.toMontgomery(k), montgomery.toMontgomery(verifier)))
        publicB = WS2SRPMontgomery.modAdd(kv, gb, Self.modulusBig)
        guard !publicB.isZero else { clear(); throw Failure.input }
        phase = .started
    }

    func verify(publicKey: Data, proof: Data) throws -> (serverProof: Data, key: Data) {
        guard phase == .started else { clear(); throw Failure.state }
        phase = .consumed // 先消费会话，再碰任何外部输入。
        guard (1...384).contains(publicKey.count), proof.count == 64,
              let a = WS2SRPBig(bigEndian: [UInt8](publicKey)),
              !a.isZero, a.compare(Self.modulusBig) < 0
        else { clear(); throw Failure.input }
        let aPad = a.bigEndian384
        let bPad = publicB.bigEndian384
        let nPad = Self.modulusBig.bigEndian384
        let uBytes = sha512([aPad, bPad])
        guard let u = WS2SRPBig(bigEndian: uBytes), !u.isZero else { clear(); throw Failure.input }
        // S = (A · v^u)^b mod N
        let vu = montgomery.power(verifier, exponent: u)
        let base = montgomery.fromMontgomery(montgomery.multiply(montgomery.toMontgomery(a), montgomery.toMontgomery(vu)))
        let s = montgomery.power(base, exponent: privateKey)
        guard !s.isZero else { clear(); throw Failure.input }
        let sPad = s.bigEndian384
        // K = H(S 去前导零)
        let zS = leadingZeros(sPad)
        let key = sha512([Array(sPad[zS...])])
        // M1 = H( H(N) XOR H(g) | H(user) | salt | A | B | K )，A/B 去前导零。
        let hn = sha512([nPad])
        var hg = sha512([[UInt8(Self.generator)]])
        for index in 0..<64 { hg[index] ^= hn[index] }
        let hu = sha512([user])
        let zA = leadingZeros(aPad)
        let zB = leadingZeros(bPad)
        let expected = sha512([hg, hu, salt, Array(aPad[zA...]), Array(bPad[zB...]), key])
        diagnosticExpectedM1 = expected
        diagnosticKey = key
        diagnosticS = sPad
        guard Data(expected) == proof else { clear(); throw Failure.proof }
        // M2 = H( A | M1 | K )；adkPadded 的 A 补齐 384，srptoolsMinimal 的 A 去前导零。
        let m2Input: [UInt8] = convention == .adkPadded ? aPad : Array(aPad[zA...])
        let serverProof = sha512([m2Input, expected, key])
        defer { clear() }
        return (Data(serverProof), Data(key))
    }

    func clear() {
        phase = .consumed
        user = []
        salt = [UInt8](repeating: 0, count: 16)
        privateKey = WS2SRPBig(zero: ())
        verifier = WS2SRPBig(zero: ())
        publicB = WS2SRPBig(zero: ())
    }
}
