// Verifies the OS authentication path and model integrity boundary, not face recognition accuracy.
import Foundation
import LocalAuthentication
import CryptoKit
@main struct Main {
    static func main() {
        let args = CommandLine.arguments
        if args.count == 4,args[1] == "--model" {
            let url = URL(fileURLWithPath:args[2])
            do {
                let attrs = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                guard attrs.isRegularFile == true,attrs.isSymbolicLink != true,let size=attrs.fileSize,size <= 1_073_741_824 else { exit(2) }
                let data = try Data(contentsOf:url,options:.mappedIfSafe)
                let hash = SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
                guard hash == args[3].lowercased() else { print("MODEL_HASH_MISMATCH"); exit(2) }
                print("MODEL_HASH_MATCH; accuracy, anti-spoofing, training license and OS unlock remain unverified")
                return
            } catch { print("MODEL_UNREADABLE"); exit(2) }
        }
        guard args == [args[0],"--authenticate"] else {
            print("Use --authenticate with Aaron present, or --model FILE EXPECTED_SHA256"); exit(64)
        }
        let context = LAContext(); context.localizedCancelTitle = "取消"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,error:&error) else {
            print("BIOMETRICS_UNAVAILABLE; no identity or unlock claim"); exit(2)
        }
        let semaphore = DispatchSemaphore(value:0)
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,localizedReason:"核对 WindowShade 身份验证边界，不解锁系统") { success,_ in
            print(success ? "OS_BIOMETRICS_SUCCESS; not an OS unlock" : "OS_BIOMETRICS_CANCELLED_OR_FAILED")
            semaphore.signal()
        }
        if semaphore.wait(timeout:.now()+60) == .timedOut { context.invalidate(); print("AUTH_TIMEOUT"); exit(2) }
    }
}
