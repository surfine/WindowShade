// Candidate CryptoKit execution test. Not run on Linux. Synthetic keys ONLY.
import Foundation
import CryptoKit
@main struct MacCryptoTests {
    enum Failure: Error { case check, fixture }
    static func check(_ value: Bool) throws { if !value { throw Failure.check } }
    static func hex(_ text: String) throws -> Data {
        guard text.count % 2 == 0 else { throw Failure.fixture };var result=Data();var i=text.startIndex
        while i < text.endIndex { let n=text.index(i,offsetBy:2);guard let b=UInt8(text[i..<n],radix:16) else{throw Failure.fixture};result.append(b);i=n };return result
    }
    static func nonce(_ label: String) throws -> ChaChaPoly.Nonce { try .init(data:Data(repeating:0,count:4)+Data(label.utf8)) }
    static func kdf(_ shared:SharedSecret,_ salt:String,_ info:String)->SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using:SHA512.self,salt:Data(salt.utf8),sharedInfo:Data(info.utf8),outputByteCount:32)
    }
    @MainActor static func main() throws {
        let json=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:String]
        func v(_ name:String)throws->Data { guard let s=json[name] else{throw Failure.fixture};return try hex(s) }
        let ce=try Curve25519.KeyAgreement.PrivateKey(rawRepresentation:v("clientEphemeralPrivate"))
        let se=try Curve25519.KeyAgreement.PrivateKey(rawRepresentation:v("serverEphemeralPrivate"))
        let known=try ce.sharedSecretFromKeyAgreement(with:se.publicKey)
        try check(known.withUnsafeBytes{Data($0)} == v("sharedSecret"))
        try check(kdf(known,"","ClientEncrypt-main").withUnsafeBytes{Data($0)} == v("clientEncryptKey"))
        let signature=try Curve25519.Signing.PublicKey(rawRepresentation:v("serverSigningPublic"))
        try check(signature.isValidSignature(v("serverSignature"),for:v("serverEphemeralPublic")+v("serverID")+v("clientEphemeralPublic")))
        print("PASS fixed Python/CryptoKit key agreement, HKDF and signature vectors")
        let clientSigning=try Curve25519.Signing.PrivateKey(rawRepresentation:v("clientSigningSeed"))
        let serverSigning=try Curve25519.Signing.PrivateKey(rawRepresentation:v("serverSigningSeed"))
        let cid=try v("clientID"), sid=try v("serverID")
        let peer=WS2CompanionCrypto.Peer(identifier:cid,signingPublicKey:clientSigning.publicKey.rawRepresentation,revision:1,enabled:true)
        var revoked=false
        let server=try WS2CompanionCrypto(identity:.init(identifier:sid,signingKey:serverSigning),clock:WS2ContinuousClock(),
            lookup:{$0 == cid ? peer:nil},isCurrent:{ $0 == peer && !revoked })
        let m1=try PairingTLV.encode([(6,Data([1])),(3,ce.publicKey.rawRepresentation)])
        let m2=try PairingTLV.decode(server.answerM1(m1),allowed:[6,3,5])
        guard let sp=m2[3], let cipher=m2[5] else{throw Failure.check}
        try check(m2[6] == Data([2]))
        let shared=try ce.sharedSecretFromKeyAgreement(with:.init(rawRepresentation:sp))
        let key=kdf(shared,"Pair-Verify-Encrypt-Salt","Pair-Verify-Encrypt-Info")
        let box=try ChaChaPoly.SealedBox(nonce:nonce("PV-Msg02"),ciphertext:cipher.dropLast(16),tag:cipher.suffix(16))
        let proof=try PairingTLV.decode(ChaChaPoly.open(box,using:key),allowed:[1,10])
        guard let sig=proof[10] else{throw Failure.check}
        try check(proof[1] == sid && serverSigning.publicKey.isValidSignature(sig,for:sp+sid+ce.publicKey.rawRepresentation))
        let clientSig=try clientSigning.signature(for:ce.publicKey.rawRepresentation+cid+sp)
        let inner=try PairingTLV.encode([(1,cid),(10,clientSig)])
        let sealed=try ChaChaPoly.seal(inner,using:key,nonce:nonce("PV-Msg03"))
        let verified=try server.answerM3(PairingTLV.encode([(6,Data([3])),(5,sealed.ciphertext+sealed.tag)]))
        try check(try PairingTLV.decode(verified.m4,allowed:[6])[6] == Data([4]))
        print("PASS synthetic client/server M1-M4 with fresh server ephemeral")
        let hello=Data("hello fixture".utf8),c2s=kdf(shared,"","ClientEncrypt-main"),s2c=kdf(shared,"","ServerEncrypt-main")
        var counter=WS2CompanionCounter()
        let head=try WS2CompanionFrame.header(type:8,count:hello.count+16)
        let encrypted=try ChaChaPoly.seal(hello,using:c2s,nonce:.init(data:counter.take()),authenticating:head)
        let input=WS2CompanionFrame(type:8,payload:encrypted.ciphertext+encrypted.tag)
        try check(try verified.session.open(input)==hello)
        var decoder=WS2CompanionFrame.Decoder();let response=try decoder.feed(verified.session.seal(hello))[0]
        var responseCounter=WS2CompanionCounter()
        let replyBox=try ChaChaPoly.SealedBox(nonce:.init(data:responseCounter.take()),ciphertext:response.payload.dropLast(16),tag:response.payload.suffix(16))
        try check(try ChaChaPoly.open(replyBox,using:s2c,authenticating:head)==hello)
        print("PASS bidirectional protected records")
        do { _=try verified.session.open(input);throw Failure.check } catch is Failure { throw Failure.check } catch { print("PASS replay closes session") }
        do { _=try verified.session.seal(hello);throw Failure.check } catch is Failure { throw Failure.check } catch { print("PASS closed session cannot transmit") }
        revoked=true
        print("Synthetic execution only; no PIN setup, Keychain, sockets or native Remote tested")
    }
}
