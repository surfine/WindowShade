import CoreGraphics

// 角落停放的几何：留 1 像素、避开别的屏、8×8 才算看得见。

@main
struct CornerParkingTests {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = CGSize(width: 400, height: 300)

        // 右下角优先，窗口左上角落在 (1919, 1079)，只露 1 像素
        let spots = cornerParkingSpots(screen: screen, otherScreens: [], windowSize: window)
        precondition(spots.count == 2)
        precondition(spots[0] == CGPoint(x: 1919, y: 1079))
        precondition(spots[1] == CGPoint(x: -399, y: 1079))

        // 右边还有一块屏：右下角会压到它，只剩左下角
        let rightScreen = CGRect(x: 1920, y: 800, width: 1280, height: 800)
        let blocked = cornerParkingSpots(screen: screen, otherScreens: [rightScreen], windowSize: window)
        precondition(blocked == [CGPoint(x: -399, y: 1079)])

        // 可见判定：1 像素不算，8×8 算
        let peeking = CGRect(x: 1919, y: 1079, width: 400, height: 300)
        precondition(rectIsVisible(peeking, onScreens: [screen]) == false)
        let enough = CGRect(x: 1912, y: 1072, width: 400, height: 300)
        precondition(rectIsVisible(enough, onScreens: [screen]) == true)

        // 比 8 点还小的窗口：按窗口自身尺寸算
        let tiny = CGRect(x: 10, y: 10, width: 4, height: 4)
        precondition(rectIsVisible(tiny, onScreens: [screen]) == true)

        // 窗口跨两块屏：选相交面积大的那块
        let left = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let right = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let straddling = CGRect(x: 1800, y: 100, width: 400, height: 300)
        let spot = cornerParkingSpot(windowFrame: straddling, screens: [left, right])
        precondition(spot == CGPoint(x: 3839, y: 1079), "expected right screen corner, got \(String(describing: spot))")

        print("CornerParkingTests ok")
    }
}
