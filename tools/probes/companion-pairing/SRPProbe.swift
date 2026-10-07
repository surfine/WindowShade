import Foundation

/// Pipe-only test harness. Never start a listener or enroll peers; keys are returned only to the test driver.
@main @MainActor struct SRPProbe {
    enum InputError: Error { case malformed }
    static func bytes(_ value: Any?) throws -> Data {
        guard let text = value as? String, text.count <= 768, text.count % 2 == 0 else { throw InputError.malformed }
        var data = Data(); var position = text.startIndex
        while position < text.endIndex {
            let next = text.index(position, offsetBy: 2)
            guard let byte = UInt8(text[position..<next], radix: 16) else { throw InputError.malformed }
            data.append(byte); position = next
        }
        return data
    }
    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    static func reply(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { exit(2) }
        print(text)
        fflush(stdout)
    }
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 3, args[0] == "--test-json", args[1] == "--m2",
              let convention = WS2NativeSRPPrimitive.ProofConvention(rawValue: args[2]) else {
            print("Isolated test only: --test-json --m2 adk-padded|srptools-minimal. Not for distribution.")
            exit(64)
        }
        do {
            let primitive = try WS2NativeSRPPrimitive(proofConvention: convention)
            defer { primitive.clear() }
            while let line = readLine() {
                do {
                    guard line.utf8.count <= 4096, let data = line.data(using: .utf8),
                          let input = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let operation = input["op"] as? String else { throw InputError.malformed }
                    switch operation {
                    case "begin":
                        guard let pin = input["pin"] as? String else { throw InputError.malformed }
                        let result = try primitive.begin(pin: pin)
                        reply(["salt": hex(result.salt), "publicKey": hex(result.publicKey)])
                    case "verify":
                        let result = try primitive.verify(publicKey: bytes(input["publicKey"]), proof: bytes(input["proof"]))
                        reply(["serverProof": hex(result.serverProof), "key": hex(result.key)])
                    case "clear": primitive.clear(); reply(["cleared": true])
                    default: throw InputError.malformed
                    }
                } catch let error as WS2NativeSRPPrimitive.Failure { reply(["error": error.code]) }
                catch { primitive.clear(); reply(["error": "malformed"]) }
            }
        } catch { reply(["error": "initialization"]); exit(2) }
    }
}
