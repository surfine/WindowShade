// SRP 交叉验证的执行器（隔离工具，不进 App）：
// 对同一批 (pin, salt, B) 分别用纯 Swift 与探针的 C 原生实现当服务端，
// 由 Python 参考客户端（tests/run-srp-cross-check.sh 内联）算 A/M1/K。
// 用法：crosscheck generate <pin>          → 打印 {salt, B}（服务端各自随机 begin）
//       crosscheck verify <pin> <saltHex> <BHex> <AHex> <M1Hex> → 打印 {accepted, K, M2}
// 分别以 --pure / --native 选择实现，输出 JSON 行。
import Foundation

@main struct WS2SRPCrossCheck {
    static func main() {
        MainActor.assumeIsolated {
            run()
        }
    }

    @MainActor static func run() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else { print(#"{"error":"usage"}"#); exit(64) }
        let implementation = arguments[1]
        let mode = arguments[2]

        @MainActor func makeServer() -> WS2SRPPrimitive {
            switch implementation {
            case "--pure": return WS2PureSRP(convention: .srptoolsMinimal)
            case "--native": return try! WS2NativeSRPPrimitive(proofConvention: .srptoolsMinimal)
            default: fatalError("unknown implementation")
            }
        }

        func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
        func unhex(_ text: String) -> Data {
            var digits = Array(text)
            if digits.count % 2 == 1 { digits.insert("0", at: 0) }
            var out = Data()
            var index = 0
            while index + 1 < digits.count {
                guard let high = UInt8(String(digits[index]), radix: 16),
                      let low = UInt8(String(digits[index + 1]), radix: 16) else { return Data() }
                out.append(high << 4 | low)
                index += 2
            }
            return out
        }

        let server = makeServer()
        switch mode {
        case "generate":
            let pin = arguments[3]
            do {
                let started = try server.begin(pin: pin)
                print(#"{"salt":"\#(hex(started.salt))","B":"\#(hex(started.publicKey))"}"#)
            } catch {
                print(#"{"error":"begin \#(error)"}"#)
                exit(2)
            }
        case "replay":
            // replay <pin> <saltHex> <bHex> <AHex> <M1Hex>：固定盐与私钥重建会话后验证。
            let pin = arguments[3]
            let salt = unhex(arguments[4])
            let privateB = unhex(arguments[5])
            let publicA = unhex(arguments[6])
            let m1 = unhex(arguments[7])
            guard let pure = server as? WS2PureSRP else { print(#"{"error":"replay is pure-only"}"#); exit(64) }
            do {
                try pure.beginFixed(user: Array("Pair-Setup".utf8), pin: Array(pin.utf8),
                                    salt: [UInt8](salt), privateKey: [UInt8](privateB))
                let startedB = pure._publicBForTesting()
                _ = try pure.verify(publicKey: publicA, proof: m1)
                let bHex = startedB.map { String(format: "%02x", $0) }.joined()
                print(#"{"accepted":true,"B":"\#(bHex)"}"#)
            } catch {
                let m1Hex = pure.diagnosticExpectedM1.map { String(format: "%02x", $0) }.joined()
                let kHex = pure.diagnosticKey.map { String(format: "%02x", $0) }.joined()
                let sHex = pure.diagnosticS.map { String(format: "%02x", $0) }.joined()
                let bHex2 = pure._publicBForTesting().map { String(format: "%02x", $0) }.joined()
                print(#"{"accepted":false,"serverM1":"\#(m1Hex)","K":"\#(kHex)","S":"\#(sHex)","B":"\#(bHex2)"}"#)
                exit(3)
            }
        case "run":
            // run <pin>：一次 begin，把 (salt,B) 打到 stderr，从 stdin 读客户端的 A/M1（hex,hex），
            // 打印最终 {accepted,K,M2}。
            let pin = arguments[3]
            do {
                let started = try server.begin(pin: pin)
                FileHandle.standardError.write(Data(#"{"salt":"\#(hex(started.salt))","B":"\#(hex(started.publicKey))"}"#.utf8))
                FileHandle.standardError.write(Data("\n".utf8))
                let line = readLine() ?? ""
                let parts = line.split(separator: ",").map(String.init)
                guard parts.count == 2 else { print(#"{"error":"client input"}"#); exit(2) }
                let result = try server.verify(publicKey: unhex(parts[0]), proof: unhex(parts[1]))
                print(#"{"accepted":true,"K":"\#(hex(result.key))","M2":"\#(hex(result.serverProof))"}"#)
            } catch {
                print(#"{"accepted":false,"error":"\#(error)"}"#)
                exit(3)
            }
        default:
            print(#"{"error":"mode"}"#)
            exit(64)
        }
    }
}
