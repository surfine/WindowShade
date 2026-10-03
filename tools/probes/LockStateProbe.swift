// Read-only observation. Aaron locks/unlocks with the system UI; no password input or lock command.
import Foundation
import CoreGraphics
@main struct Main {
    static func main() {
        print("sample,screen_locked_private_key,on_console,login_done")
        for sample in 0..<60 {
            let d = CGSessionCopyCurrentDictionary() as? [String:Any] ?? [:]
            func value(_ key: String) -> String { (d[key] as? Bool).map { $0 ? "true" : "false" } ?? "unknown" }
            print("\(sample),\(value("CGSSessionScreenIsLocked")),\(value("kCGSessionOnConsoleKey")),\(value("kCGSessionLoginDoneKey"))")
            fflush(stdout); Thread.sleep(forTimeInterval:1)
        }
    }
}
