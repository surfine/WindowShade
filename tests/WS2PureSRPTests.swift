// 纯 Swift SRP 的官方向量验证（HomeKitADK fb201f98 的 SRP-3072/SHA-512 向量）。
// 向量从 tools/probes/companion-pairing/NativeSRPTests.c 机器提取到 WS2PureSRPVectors.json，不手抄。
// 全部离线：固定用户 alice / 口令 password123 / 固定盐与私钥。
import Foundation

@main struct WS2PureSRPTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func hex(_ text: String) -> [UInt8] {
        var out: [UInt8] = []
        var iterator = text.makeIterator()
        while let high = iterator.next(), let low = iterator.next() {
            out.append(UInt8(String([high, low]), radix: 16) ?? 0)
        }
        return out
    }

    static let vectors: [String: [UInt8]] = {
        let url = URL(fileURLWithPath: CommandLine.arguments.count > 1
            ? CommandLine.arguments[1] : "tests/WS2PureSRPVectors.json")
        let raw = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: String]
        return raw.mapValues { hex($0) }
    }()

    static func main() {
        @MainActor func run() throws {
            let salt = vectors["salt"]!, user = vectors["user"]!, pass = vectors["pass"]!
            let b = vectors["b"]!, a = vectors["A"]!
            let expectedB = vectors["B"]!, expectedK = vectors["K"]!
            let expectedM1 = vectors["M1"]!, expectedM2 = vectors["M2"]!, expectedV = vectors["v"]!

            // 向量会话：固定参数 begin → v/B；向量 A/M1 verify → K/M2（adk 填充规约）。
            let srp = WS2PureSRP(convention: .adkPadded)
            try srp.beginFixed(user: user, pin: pass, salt: salt, privateKey: b)
            expect(srp.verifierForTesting() == expectedV, "verifier matches the official vector")
            expect(srp.publicBForTesting() == expectedB, "B matches the official vector")
            let result = try srp.verify(publicKey: Data(a), proof: Data(expectedM1))
            expect([UInt8](result.key) == expectedK, "session key matches the official vector")
            expect([UInt8](result.serverProof) == expectedM2, "M2 (adk-padded) matches the official vector")

            // 同一组输入换成 srptoolsMinimal：向量 A 无前导零，两种规约的 M2 应一致。
            let minimal = WS2PureSRP(convention: .srptoolsMinimal)
            try minimal.beginFixed(user: user, pin: pass, salt: salt, privateKey: b)
            let minimalResult = try minimal.verify(publicKey: Data(a), proof: Data(expectedM1))
            expect([UInt8](minimalResult.serverProof) == expectedM2,
                   "M2 conventions agree when A has no leading zeros")

            // 重放被拒。
            do {
                _ = try srp.verify(publicKey: Data(a), proof: Data(expectedM1))
                expect(false, "replayed verify is rejected")
            } catch { expect(true, "replayed verify is rejected") }

            // A=0 与 A=N 拒绝并消费会话。
            let modulus = WS2SRPBig(bigEndian: WS2PureSRP.modulusBig.bigEndian384)!
            for invalid in [[UInt8](repeating: 0, count: 384), WS2PureSRP.modulusBig.bigEndian384] {
                let session = WS2PureSRP(convention: .adkPadded)
                try session.beginFixed(user: user, pin: pass, salt: salt, privateKey: b)
                do {
                    _ = try session.verify(publicKey: Data(invalid), proof: Data(expectedM1))
                    expect(false, "A=0/N is rejected")
                } catch { expect(true, "A=0/N is rejected") }
                do {
                    _ = try session.verify(publicKey: Data(a), proof: Data(expectedM1))
                    expect(false, "consumed session rejects later input")
                } catch { expect(true, "consumed session rejects later input") }
            }
            _ = modulus

            // 错证明拒绝。
            do {
                let session = WS2PureSRP(convention: .adkPadded)
                try session.beginFixed(user: user, pin: pass, salt: salt, privateKey: b)
                var wrong = expectedM1
                wrong[17] ^= 1
                _ = try session.verify(publicKey: Data(a), proof: Data(wrong))
                expect(false, "wrong proof is rejected")
            } catch { expect(true, "wrong proof is rejected") }

            // 大数边界：384 字节上限、减法借位、比较、往返。
            expect(WS2SRPBig(bigEndian: [UInt8](repeating: 0xff, count: 385)) == nil, "385 bytes refused")
            let one = WS2SRPBig(one: ())
            let zero = WS2SRPBig(zero: ())
            expect((zero - one) == nil, "negative subtraction refused")
            let modulusMinusOne = modulus - one
            expect(modulusMinusOne != nil && modulusMinusOne!.compare(modulus) < 0, "N - 1 < N")
            expect(WS2SRPBig(bigEndian: modulus.bigEndian384)! == modulus, "big-endian round trip")

            // 幂自洽：g^1 = g；g^2 = g·g。
            let montgomery = WS2SRPMontgomery(modulus: modulus)!
            expect(montgomery.power(WS2PureSRP.generatorBig, exponent: one) == WS2PureSRP.generatorBig,
                   "power exponent 1 is identity")
            var two = WS2SRPBig(zero: ())
            two.words[0] = 2
            let squared = montgomery.power(WS2PureSRP.generatorBig, exponent: two)
            let product = montgomery.fromMontgomery(montgomery.multiply(
                montgomery.toMontgomery(WS2PureSRP.generatorBig), montgomery.toMontgomery(WS2PureSRP.generatorBig)))
            expect(squared == product, "power exponent 2 equals modular square")

            // PIN 长度边界：空与 65 拒绝；1 与 64 接受。
            do {
                let session = WS2PureSRP()
                _ = try session.begin(pin: "")
                expect(false, "empty pin is rejected")
            } catch { expect(true, "empty pin is rejected") }
            do {
                let session = WS2PureSRP()
                _ = try session.begin(pin: String(repeating: "x", count: 65))
                expect(false, "65-char pin is rejected")
            } catch { expect(true, "65-char pin is rejected") }
            do {
                let session = WS2PureSRP()
                _ = try session.begin(pin: "1")
                expect(true, "1-char pin is accepted")
            } catch { expect(false, "1-char pin is accepted") }
            do {
                let session = WS2PureSRP()
                _ = try session.begin(pin: String(repeating: "x", count: 64))
                expect(true, "64-char pin is accepted")
            } catch { expect(false, "64-char pin is accepted") }

            // 随机路径冒烟：随机盐/私钥后，向量证明必须被拒。
            do {
                let session = WS2PureSRP()
                _ = try session.begin(pin: "111111")
                do {
                    _ = try session.verify(publicKey: Data(a), proof: Data(expectedM1))
                    expect(false, "random session rejects the vector proof")
                } catch { expect(true, "random session rejects the vector proof") }
            } catch {
                expect(false, "random begin succeeds")
            }
        }
        do { try run() } catch {
            print("FAIL threw: \(error)")
            failures += 1
        }
        if failures > 0 { print("\(failures) FAILED"); exit(1) }
        print("PASS pure SRP official vectors")
    }
}

// 测试观察口：只读，不参与协议。
@MainActor extension WS2PureSRP {
    func verifierForTesting() -> [UInt8] { _verifierForTesting() }
    func publicBForTesting() -> [UInt8] { _publicBForTesting() }
}
