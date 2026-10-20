import Foundation

@main
struct FacePresenceNoteTests {
    static func main() {
        var t = TestSuite("FacePresenceNote")
        t.section("FP-01", "off never looks like a device status")
        t.expect(FacePresenceNote.text(enabled: false, phone: .present, watch: .present) == "off", "off")
        t.section("FP-02", "phone and watch are both reported")
        t.expect(FacePresenceNote.text(enabled: true, phone: .present, watch: .away) == "phone=present watch=away", "present/away")
        t.expect(FacePresenceNote.text(enabled: true, phone: .unknown, watch: .connecting) == "phone=unknown watch=connecting", "unknown/connecting")
        t.section("FP-03", "every status has an ASCII name")
        for status in [PresenceLock.Status.unknown, .connecting, .present, .away] {
            let name = FacePresenceNote.name(status)
            t.expect(!name.isEmpty && name.unicodeScalars.allSatisfy { $0.isASCII }, "ascii \(name)")
        }
        t.section("FP-04", "presence is not an identity cue")
        t.expect(FacePresenceNote.text(enabled: true, phone: .present, watch: .present).contains("present"), "recorded")
        t.finish()
    }
}
