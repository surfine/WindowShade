import Foundation

// 规格 R27：按显示器落盘的设置先认 UUID、再退回旧编号。
@main
struct DisplayKeyResolverTests {
    static func main() {
        var failures = 0
        func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FAIL \(what)") } }
        typealias D = DisplayKeyResolver.Display
        let builtIn = D(id: 1, uuid: "AAAA-1111"), studio = D(id: 3, uuid: "BBBB-2222")
        check(DisplayKeyResolver.resolve(storedUUID: "BBBB-2222", storedID: 2, among: [builtIn, studio]) == 3,
              "重接后编号从 2 变成 3：按 UUID 还是认出那块屏")
        check(DisplayKeyResolver.resolve(storedUUID: "bbbb-2222", storedID: nil, among: [builtIn, studio]) == 3, "UUID 大小写不敏感")
        check(DisplayKeyResolver.resolve(storedUUID: "CCCC-3333", storedID: 1, among: [builtIn, studio]) == nil,
              "存的 UUID 那块屏不在：返回 nil，不拿编号去撞别的屏")
        check(DisplayKeyResolver.resolve(storedUUID: nil, storedID: 3, among: [builtIn, studio]) == 3, "旧设置只有编号：照旧按编号认")
        check(DisplayKeyResolver.resolve(storedUUID: "", storedID: 1, among: [builtIn, studio]) == 1, "空 UUID 当没存")
        check(DisplayKeyResolver.resolve(storedUUID: nil, storedID: 9, among: [builtIn, studio]) == nil, "编号对不上：nil")
        check(DisplayKeyResolver.resolve(storedUUID: nil, storedID: 0, among: [D(id: 0, uuid: nil)]) == nil, "编号 0 当没存")
        if failures > 0 { exit(1) }
        print("PASS display-key-resolver: UUID first, ID fallback for old settings, missing display is nil")
    }
}
