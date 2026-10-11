// iAP2 探针离线测试：CSM 编解码、链路包编解码与同步交换、MFi 身份加载与签名。
// 全部离线：身份材料现场生成（自签测试身份），不碰蓝牙、不连 iPhone。
import Foundation
import Security
import CryptoKit

@main struct Iap2OfflineTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        // CSM：帧编码与解析往返
        do {
            let frame = Iap2Csm.identificationInformation(
                name: "Probe", model: "WS2", manufacturer: "WindowShade",
                serialNumber: "S1", firmwareVersion: "0.1", hardwareVersion: "0.1",
                externalAccessoryProtocol: "me.test", bluetoothMac: "AA:BB:CC:DD:EE:FF", ssid: "net")
            let encoded = frame.encoded
            let (parsed, consumed) = Iap2Csm.parse(from: encoded)
            expect(consumed == encoded.count, "identification frame consumes exactly")
            expect(parsed.count == 1 && parsed[0].messageId == 0x1d01, "identification message id parses")
            expect(parsed[0].parameters.count == frame.parameters.count, "identification parameters survive roundtrip")
            expect(parsed[0].parameters.first?.payload == Array("Probe".utf8) + [0], "strings are NUL terminated")
            let macParam = parsed[0].parameters.first { $0.id == 17 }
            let macGroup = macParam.flatMap { Iap2Csm.parseParameters($0.payload) }?.first { $0.id == 3 }
            expect(macGroup?.payload == [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff], "bluetooth mac group roundtrips")
        }

        // CSM：分块与垃圾字节
        do {
            let frame = Iap2Csm.authenticationResponse(Array(repeating: 0x5a, count: 64))
            let encoded = frame.encoded
            var buffer: [UInt8] = [0x00, 0xff, 0x12] // 垃圾前缀
            for byte in encoded { buffer.append(byte) }
            buffer += [0x40, 0x40, 0x00] // 残缺尾
            let (parsed, consumed) = Iap2Csm.parse(from: buffer)
            expect(parsed.count == 1 && parsed[0].messageId == 0xaa03, "garbage before frame is skipped")
            expect(consumed == buffer.count - 3, "trailing partial frame stays in buffer")
        }

        // 链路：包编码校验为 0，标记与确认
        do {
            let data = Iap2Link.encode(payload: [1, 2, 3, 4], sequence: 100, control: Iap2Link.controlData,
                                       session: Iap2Link.controlSessionId, acknowledgement: 7)
            expect(data[0] == 0xff && data[1] == 0x5a, "packet starts with FF 5A")
            expect(Iap2Link.checksumValid(data), "packet bytes sum to zero")
            let ack = Iap2Link.encode(payload: nil, sequence: 100, control: Iap2Link.controlData,
                                      session: 0, acknowledgement: 7)
            expect(ack.count == 9 && Iap2Link.checksumValid(ack), "ack-only packet is 9 bytes and valid")
        }

        // 链路：marker → 同步 → 数据 → 事件
        do {
            var link = Iap2Link()
            link.start()
            var out = link.takeOutput()
            expect(out == Iap2Link.marker, "start emits exactly the marker")
            // 对方发 marker + 同步
            let peerSync = Iap2Link.Synchronization(maxOutgoing: 12, maxFrameBytes: 4096, sessions: [(10, 0, 1)])
            let peerPacket = Iap2Link.encode(payload: peerSync.encoded, sequence: 50,
                                             control: Iap2Link.controlSynchronize, session: 0, acknowledgement: 0)
            link.feed(Iap2Link.marker + peerPacket)
            var sawReady = false
            while let event = link.pollEvent() {
                if case .ready = event { sawReady = true }
            }
            expect(sawReady && link.state == .running, "peer sync completes negotiation")
            out = link.takeOutput()
            expect(out.contains(Iap2Link.marker) == false && out.count > 9, "our sync packet goes out after their marker")
            // 对方发一条控制会话数据（= 一个 CSM 帧）
            let csm = Iap2Csm.Frame(messageId: Iap2Csm.Mfi.requestCertificate, parameters: []).encoded
            let peerData = Iap2Link.encode(payload: csm, sequence: 51, control: Iap2Link.controlData,
                                           session: Iap2Link.controlSessionId, acknowledgement: 0)
            link.feed(peerData)
            var control: [UInt8]?
            while let event = link.pollEvent() {
                if case .control(let payload) = event { control = payload }
            }
            expect(control == csm, "session-10 payload surfaces as control event")
            // 我们回包后必须能写出带载荷的数据包
            link.sendControl(Iap2Csm.accessoryCertificate([0x01, 0x02]).encoded)
            out = link.takeOutput()
            expect(out.contains(where: { $0 == 0xaa }) && Iap2Link.checksumValidValid(out), "our reply frames as valid packets")
        }

        // MFi：现场生成身份 → pk8/证书文件 → 加载自检 → 签名/验签往返
        do {
            let (pkcs8, certificateDer) = Self.generateTestIdentity()
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("iap2-test-\(UUID().uuidString)", isDirectory: true)
            try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try! Data(pkcs8).write(to: dir.appendingPathComponent("identity.pk8"))
            try! Data(certificateDer).write(to: dir.appendingPathComponent("certificate.p7b"))
            defer { try? FileManager.default.removeItem(at: dir) }

            let identity = try? Iap2MfiIdentity(directory: dir.path)
            expect(identity != nil, "self-generated identity loads and self-checks")
            guard let identity else { return }
            let digest = Array(SHA256.hash(data: Data("challenge from phone".utf8)))
            let raw = try? identity.sign(digest: digest)
            expect(raw?.count == 64, "signature is 64-byte raw r||s")
            // 用证书公钥验证
            let publicKey = Iap2MfiIdentity.certificatePublicKey(identity.certificate)
            expect(publicKey != nil, "certificate public key extracts")
            if let publicKey, let raw {
                expect(Iap2MfiIdentity.verify(signed: raw, of: digest, with: publicKey),
                       "raw signature verifies against certificate key")
            }
            // 坏摘要签名验证必须失败
            if let publicKey, let raw {
                let other = Array(SHA256.hash(data: Data("other".utf8)))
                expect(!Iap2MfiIdentity.verify(signed: raw, of: other, with: publicKey),
                       "signature fails against a different digest")
            }
            // 缺文件拒绝
            let empty = FileManager.default.temporaryDirectory
                .appendingPathComponent("iap2-empty-\(UUID().uuidString)", isDirectory: true)
            try! FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: empty) }
            expect((try? Iap2MfiIdentity(directory: empty.path)) == nil, "missing files refuse to load")
        }

        if failures > 0 { print("\(failures) FAILED"); exit(1) }
        print("PASS iap2 offline")
    }

    /// 生成一份测试身份：PKCS#8 EC P-256 私钥 + 自签证书（DER）。
    /// 只用于离线验证签路；不代表任何真实 MFi 身份。
    static func generateTestIdentity() -> (pkcs8: [UInt8], certificate: [UInt8]) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error)!

        // Security 的私钥外部表示是 04||标量32||X||Y64（97 字节）。
        let sec1 = [UInt8]((SecKeyCopyExternalRepresentation(key, nil) as Data?) ?? Data())
        let publicKey = [UInt8]((SecKeyCopyExternalRepresentation(SecKeyCopyPublicKey(key)!, nil) as Data?) ?? Data())

        // 全部用 tlv 拼装，不手写长度字节。
        func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
            [tag] + DERLength(content.count) + content
        }
        let oidEC = tlv(0x06, [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01])          // id-ecPublicKey
        let oidP256 = tlv(0x06, [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07])   // prime256v1
        let alg = tlv(0x30, oidEC + oidP256)

        // PKCS#8：SEQUENCE{ INTEGER 0, alg, OCTET STRING sec1 }
        let pkcs8 = tlv(0x30, tlv(0x02, [0x00]) + alg + tlv(0x04, sec1))

        // 最小 X.509 自签证书：取公钥用，验真交给 iPhone。
        let name = tlv(0x30, tlv(0x31, tlv(0x30, tlv(0x06, [0x55, 0x04, 0x03]) + tlv(0x0c, Array("probe".utf8)))))
        let utc = Array("260101000000Z".utf8)
        let utc2 = Array("460101000000Z".utf8)
        let validity = tlv(0x30, tlv(0x17, utc) + tlv(0x17, utc2))
        let spki = tlv(0x30, alg + tlv(0x03, [0x00] + publicKey))
        let tbs = tlv(0x30, [
            tlv(0xa0, tlv(0x02, [0x02])),   // 版本 3
            tlv(0x02, [0x01]),              // 序列号 1
            alg,
            name, validity, name, spki,
        ].flatMap { $0 })
        let tbsDigest = Array(SHA256.hash(data: Data(tbs)))
        let sigDer = [UInt8]((SecKeyCreateSignature(key, SecKeyAlgorithm.ecdsaSignatureDigestX962SHA256,
                                                    Data(tbsDigest) as CFData, nil) as Data?) ?? Data())
        let certificate = tlv(0x30, tbs + alg + tlv(0x03, [0x00] + sigDer))

        return (pkcs8, certificate)
    }

    static func DERLength(_ count: Int) -> [UInt8] {
        if count < 0x80 { return [UInt8(count)] }
        if count <= 0xff { return [0x81, UInt8(count)] }
        return [0x82, UInt8(count >> 8), UInt8(count & 0xff)]
    }
}

// 链路包整体校验的辅助：写出的字节流里每个 FF 5A 包都要过校验。
extension Iap2Link {
    static func checksumValidValid(_ stream: [UInt8]) -> Bool {
        var index = 0
        var checked = 0
        while index + 2 <= stream.count {
            guard stream[index] == 0xff, stream[index + 1] == 0x5a else { index += 1; continue }
            guard index + 4 <= stream.count else { return false }
            let length = Int(stream[index + 2]) << 8 | Int(stream[index + 3])
            guard length >= 9, index + length <= stream.count else { return false }
            if !checksumValid(Array(stream[index..<(index + length)])) { return false }
            index += length
            checked += 1
        }
        return checked > 0
    }
}
