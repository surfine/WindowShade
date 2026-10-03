// Stage zero only. Deliberately never guesses callback/MTTouch ABI.
import Foundation
import Darwin
@main struct Main {
    static func main() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let h = dlopen(path,RTLD_NOW | RTLD_LOCAL) else { print("framework_unavailable"); exit(2) }
        defer { dlclose(h) }
        let symbols = ["MTDeviceCreateList","MTDeviceGetFamilyID","MTDeviceGetSensorSurfaceDimensions",
            "MTDeviceIsBuiltIn","MTDeviceStart","MTDeviceStop","MTRegisterContactFrameCallback",
            "MTUnregisterContactFrameCallback","MTRegisterContactFrameCallbackWithRefcon",
            "MTDeviceCreateDefault","MTDeviceRelease","MTDeviceGetDeviceID","MTDeviceIsRunning","MTDeviceCreateFromDeviceID"]
        print("symbol,present,call_permitted")
        for symbol in symbols { print("\(symbol),\(dlsym(h,symbol) != nil),false") }
        print("STOP_ABI_UNVERIFIED: symbol presence does not establish callback layout, ownership or thread rules")
        exit(3)
    }
}
