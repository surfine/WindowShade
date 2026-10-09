import Foundation

@main
struct BystanderCameraPickTests {
    static func check(_ ok: Bool, _ message: String) {
        if !ok { FileHandle.standardError.write(Data("FAIL \(message)\n".utf8)); exit(1) }
    }
    static func main() {
        check(BystanderCameraPick.resolve(environmentCamera: nil, settingEnabled: false, available: ["a"]) == nil, "off -> nil")
        check(BystanderCameraPick.resolve(environmentCamera: "  ", settingEnabled: false, available: ["a"]) == nil, "blank env ignored")
        check(BystanderCameraPick.resolve(environmentCamera: "dev", settingEnabled: false, available: []) == "dev", "env overrides switch")
        check(BystanderCameraPick.resolve(environmentCamera: "dev", settingEnabled: true, available: ["a"]) == "dev", "env beats setting")
        check(BystanderCameraPick.resolve(environmentCamera: nil, settingEnabled: true, available: []) == nil, "no camera -> nil")
        check(BystanderCameraPick.resolve(environmentCamera: nil, settingEnabled: true, available: ["a"]) == "a", "single")
        check(BystanderCameraPick.resolve(environmentCamera: nil, settingEnabled: true, available: ["a", "b"]) == "a", "ambiguous -> first")
        print("PASS bystander-camera-pick")
    }
}
