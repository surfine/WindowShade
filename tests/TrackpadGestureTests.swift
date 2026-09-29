import CoreGraphics
import Foundation

@main struct TrackpadGestureTests {
  static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }

  /// 按 8ms 一帧喂同样的位移；返回这一段里的触感反馈。
  @discardableResult
  static func swipe(_ r: GestureRecognizer, dx: CGFloat = 0, dy: CGFloat = 0, steps: Int,
                    _ t: inout TimeInterval) -> [GestureFeedback] {
    var feedback: [GestureFeedback] = []
    for _ in 0..<steps {
      t += 0.008
      feedback += r.scroll(CGVector(dx: dx, dy: dy), at: t)
    }
    return feedback
  }

  @discardableResult
  static func pinch(_ r: GestureRecognizer, _ delta: CGFloat, steps: Int,
                    _ t: inout TimeInterval) -> [GestureFeedback] {
    var feedback: [GestureFeedback] = []
    for _ in 0..<steps {
      t += 0.008
      feedback += r.magnify(delta, at: t)
    }
    return feedback
  }

  static func main() {
    let titleBar = GestureMap.titleBar(canUndoPlacement: false)

    // A tiny wobble on the title bar shows nothing and does nothing.
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      swipe(r, dy: 2, steps: 3, &t)
      expect(r.frame == .idle, "below the hysteresis nothing shows")
      expect(r.end(at: t + 0.2) == nil, "releasing a wobble does nothing")
    }

    // A slow, deliberate swipe up fills the bar, ticks once at the threshold and rolls the window up.
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      var last: CGFloat = 0
      var armedTicks = 0
      for _ in 0..<40 {
        t += 0.008
        armedTicks += r.scroll(CGVector(dx: 0, dy: 1.5), at: t).filter { $0 == .armed }.count
        if r.frame.action != nil {
          expect(r.frame.action == .shade, "up on a title bar means roll up")
          expect(r.frame.progress >= last, "progress follows the fingers monotonically")
          last = r.frame.progress
        }
      }
      expect(r.frame.armed, "60pt is past the threshold")
      expect(armedTicks == 1, "exactly one haptic tick at the threshold")
      expect(r.end(at: t + 0.2) == .shade, "releasing after a pause still rolls up")
    }

    // Stopping short and pausing is a change of mind.
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      swipe(r, dy: 2, steps: 20, &t)
      expect(r.frame.action == .shade && !r.frame.armed, "40pt shows the action, not yet armed")
      expect(r.end(at: t + 0.2) == nil, "releasing short of the threshold without a flick cancels")
    }

    // A quick flick counts even though it never reached the threshold.
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      swipe(r, dy: 5, steps: 6, &t)
      expect(!r.frame.armed, "30pt is not armed")
      expect(r.end(at: t + 0.008) == .shade, "a fast 30pt flick projects past the threshold")
    }

    // A flick that is too short is a tap-like accident, however fast.
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      swipe(r, dy: 4, steps: 3, &t)
      expect(r.end(at: t + 0.008) == nil, "12pt is below the minimum commit distance")
    }

    // Pulling back right before release cancels, even from past the threshold.
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      swipe(r, dy: 1.75, steps: 40, &t)
      expect(r.frame.armed, "70pt is armed")
      let back = swipe(r, dy: -8, steps: 3, &t)
      expect(back.contains(.disarmed), "dropping under the threshold untick")
      expect(r.frame.action == .shade && !r.frame.armed, "still showing roll up, not armed")
      expect(r.end(at: t + 0.008) == nil, "moving back at release cancels")
    }

    // The vertical ladder: pulling down on a normal window fills the screen, like lowering the shade.
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      swipe(r, dy: -5, steps: 12, &t)
      expect(r.frame.action == .fill && r.frame.armed, "down on a normal title bar arms fill")
      expect(r.end(at: t + 0.2) == .fill, "and fills")
    }

    // On a filled window, up first undoes the fill; down has nothing left to do; spread still arranges (magic tiling).
    do {
      let filled = GestureRecognizer(map: .titleBar(canUndoPlacement: true, isFilled: true))
      var t: TimeInterval = 0
      swipe(filled, dy: 5, steps: 12, &t)
      expect(filled.frame.action == .undoPlacement, "up on a window we filled undoes the fill first")
      expect(filled.end(at: t + 0.2) == .undoPlacement, "undo")
      swipe(filled, dy: -5, steps: 12, &t)
      expect(filled.frame == .idle && filled.end(at: t + 0.2) == nil, "down on a filled window does nothing")
      pinch(filled, 0.03, steps: 10, &t)
      expect(filled.end(at: t + 0.2) == .magicTile, "spread on a filled window arranges the screen around it")

      let filledByHand = GestureRecognizer(map: .titleBar(canUndoPlacement: false, isFilled: true))
      swipe(filledByHand, dy: 5, steps: 12, &t)
      expect(filledByHand.frame.action == .shade, "filled some other way: up rolls it up")
    }

    // On a tab or address field the app keeps left and right; up still rolls up.
    do {
      let tabs = GestureMap.titleBar(canUndoPlacement: false, appOwnsHorizontal: true)
      let r = GestureRecognizer(map: tabs)
      var t: TimeInterval = 0
      swipe(r, dx: -5, steps: 12, &t)
      expect(r.frame == .idle, "left on a tab is the app's tab switch: nothing shows")
      swipe(r, dy: 5, steps: 20, &t)
      expect(r.frame == .idle, "a sloppy tab switch that drifts upward is still not ours")
      expect(r.end(at: t + 0.2) == nil, "and never rolls the window up")
      swipe(r, dy: 5, steps: 12, &t)
      expect(r.frame.action == .shade, "a clean upward swipe on a tab rolls up")
      expect(r.end(at: t + 0.2) == .shade, "roll up")
    }

    // The map can arrive after the fingers started moving (the check is asynchronous).
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      swipe(r, dx: -5, steps: 6, &t)
      expect(r.frame.action == .leftHalf, "before the check, left looks like the left half")
      r.updateMap(.titleBar(canUndoPlacement: false, appOwnsHorizontal: true))
      expect(r.frame == .idle, "after the check finds a tab, left belongs to the app")
      swipe(r, dy: 5, steps: 12, &t)
      expect(r.frame == .idle && r.end(at: t + 0.2) == nil, "and the rest of that gesture stays the app's")
    }

    // A late ownership check must use the first intent, even after the fingers turn.
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      swipe(r, dx: -5, steps: 6, &t)
      swipe(r, dy: 5, steps: 16, &t)
      expect(r.frame.action == .shade, "provisional map sees the later upward drift")
      r.updateMap(.titleBar(canUndoPlacement: false, appOwnsHorizontal: true))
      expect(r.frame == .idle, "late confirmation preserves the original tab-switch intent")
      r.updateMap(.titleBar(canUndoPlacement: false, appOwnsHorizontal: true))
      expect(r.end(at: t + 0.2) == nil, "rechecking must not turn a tab switch into roll up")
      swipe(r, dy: 5, steps: 12, &t)
      expect(r.end(at: t + 0.2) == .shade, "a new upward gesture still works after rejection")
    }

    // The result of an app-owned swipe cannot depend on when AX confirmation arrives.
    for confirmationFrame in 0...22 {
      let r = GestureRecognizer(map: titleBar)
      let tabs = GestureMap.titleBar(canUndoPlacement: false, appOwnsHorizontal: true)
      var t: TimeInterval = 0
      for frame in 0...22 {
        if frame == confirmationFrame { r.updateMap(tabs) }
        if frame < 6 { swipe(r, dx: -5, steps: 1, &t) }
        else if frame < 22 { swipe(r, dy: 5, steps: 1, &t) }
      }
      expect(r.frame == .idle && r.end(at: t + 0.2) == nil,
             "tab switching stays with the app for every confirmation delay")
    }

    // Double tap (smart zoom): fill, and back; on a strip it expands.
    do {
      let fill = GestureMap.doubleTap(zone: .titleBar, isFilled: false, canUndoPlacement: false)
      expect(fill.action == .fill && fill.armed, "double tap on a normal window fills at once")
      let back = GestureMap.doubleTap(zone: .titleBar, isFilled: true, canUndoPlacement: true)
      expect(back.action == .undoPlacement && back.armed, "double tap on a window we filled puts it back")
      let stuck = GestureMap.doubleTap(zone: .titleBar, isFilled: true, canUndoPlacement: false)
      expect(stuck.action == .undoPlacement && !stuck.available && !stuck.armed,
             "filled some other way: says there is nothing to undo")
      let strip = GestureMap.doubleTap(zone: .strip, isFilled: false, canUndoPlacement: false)
      expect(strip.action == .expand && strip.armed, "double tap on a strip expands")
    }

    // Switching displays: windows WindowShade placed go back to their layout on the new screen.
    do {
      let external = CGRect(x: -435, y: -1415, width: 2560, height: 1390)  // Studio Display, below its menu bar
      let builtIn = CGRect(x: 0, y: 34, width: 1710, height: 1000)          // MacBook, menu bar to Dock
      let filledOnExternal = RefitLayout.fill.frame(in: external)
      let squeezed = CGRect(x: 0, y: 40, width: 1710, height: 990)
      expect(DisplayRefit.target(layout: .fill, placed: filledOnExternal, current: squeezed, area: builtIn) == builtIn,
             "a filled window the system squeezed onto the built-in screen fills it again")
      expect(DisplayRefit.target(layout: .fill, placed: filledOnExternal, current: builtIn, area: builtIn) == nil,
             "already filling the new screen: leave it")
      let leftOnExternal = RefitLayout.leftHalf.frame(in: external)
      let moved = CGRect(x: 0, y: 34, width: 1280, height: 1000)
      expect(DisplayRefit.target(layout: .leftHalf, placed: leftOnExternal, current: moved, area: builtIn)
               == CGRect(x: 0, y: 34, width: 855, height: 1000),
             "a left half squeezed by the system becomes the left half of the new screen")
      let resizedByHand = CGRect(x: 100, y: 120, width: 900, height: 600)
      expect(DisplayRefit.target(layout: .fill, placed: filledOnExternal, current: resizedByHand, area: builtIn) == nil,
             "a window the person resized is their new arrangement: leave it")
      let rightHalf = RefitLayout.rightHalf.frame(in: builtIn)
      let draggedAside = CGRect(x: 200, y: 300, width: 855, height: 1000)
      expect(DisplayRefit.target(layout: .rightHalf, placed: rightHalf, current: draggedAside, area: builtIn) == rightHalf,
             "same size, only moved by the system: back into the right half")
      let before = CGRect(x: 100, y: 134, width: 855, height: 500)
      let mapped = DisplayRefit.mapped(before, from: builtIn, to: external)
      expect(external.contains(mapped) && abs(mapped.width - 855 * 2560 / 1710) < 1,
             "undo still returns to the same place and size, scaled onto the new screen")
    }

    // Which directions the control under the pointer keeps for itself.
    do {
      let safariTab: [GestureOwnership.Element] = [
        ("AXRadioButton", "AXTabButton"), ("AXOpaqueProviderGroup", "AXOpaqueProviderList"),
        ("AXGroup", nil), ("AXToolbar", nil)]
      expect(GestureOwnership.appOwnsHorizontal(safariTab), "Safari's tab keeps left and right")
      expect(!GestureOwnership.appOwnsAll(safariTab), "but not up and down")
      let addressField: [GestureOwnership.Element] = [("AXTextField", nil), ("AXRadioButton", "AXTabButton")]
      expect(GestureOwnership.appOwnsHorizontal(addressField), "the address field inside the tab too")
      let emptyToolbar: [GestureOwnership.Element] = [("AXGroup", nil), ("AXToolbar", nil)]
      expect(!GestureOwnership.appOwnsHorizontal(emptyToolbar), "an empty toolbar keeps nothing")
      let webPage: [GestureOwnership.Element] = [("AXGroup", nil), ("AXWebArea", nil), ("AXScrollArea", nil)]
      expect(GestureOwnership.appOwnsAll(webPage), "a web page scrolls: the whole gesture is the app's")
    }

    // Left and right place the window in halves.
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      swipe(r, dx: -5, steps: 12, &t)
      expect(r.frame.action == .leftHalf && r.frame.armed, "left arms the left half")
      expect(r.end(at: t + 0.2) == .leftHalf, "left half")
      swipe(r, dx: 5, steps: 12, &t)
      expect(r.frame.action == .rightHalf, "right shows the right half")
      expect(r.end(at: t + 0.2) == .rightHalf, "right half")
    }

    // Changing direction needs a clear lead, so the HUD does not flicker around 45 degrees.
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      swipe(r, dx: 5, steps: 6, &t)
      expect(r.frame.action == .rightHalf, "30pt right")
      swipe(r, dy: 5, steps: 6, &t)
      expect(r.frame.action == .rightHalf, "equal up and right keeps the first direction")
      swipe(r, dy: 5, steps: 2, &t)
      expect(r.frame.action == .shade, "up leading by more than 1.25x switches to roll up")
    }

    // Coming back to where the fingers started cancels.
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      swipe(r, dy: 5, steps: 8, &t)
      expect(r.frame.action == .shade, "40pt up shows roll up")
      swipe(r, dy: -5, steps: 7, &t)
      expect(r.frame == .idle, "back near the start shows nothing")
      expect(r.end(at: t + 0.2) == nil, "and releasing there does nothing")
    }

    // On a strip, pulling down expands; pushing up does nothing.
    do {
      let r = GestureRecognizer(map: .strip)
      var t: TimeInterval = 0
      let feedback = swipe(r, dy: -5, steps: 12, &t)
      expect(r.frame.action == .expand && feedback.contains(.armed), "down on a strip arms expand")
      expect(r.end(at: t + 0.2) == .expand, "releasing expands")
      swipe(r, dy: 5, steps: 12, &t)
      expect(r.frame == .idle, "up on a strip shows nothing")
      expect(r.end(at: t + 0.2) == nil, "and does nothing")
    }

    // Spread is magic tiling (a lone window just fills); pinch undoes the last placement only when there is one.
    do {
      var t: TimeInterval = 0
      let r = GestureRecognizer(map: titleBar)
      pinch(r, 0.025, steps: 10, &t)
      expect(r.frame.action == .magicTile && r.frame.armed, "spreading 0.25 arms magic tiling")
      expect(r.end(at: t + 0.2) == .magicTile, "magic tiling")

      let feedback = pinch(r, -0.025, steps: 10, &t)
      expect(r.frame.action == .undoPlacement && !r.frame.available,
             "pinch without anything to undo is recognized and says so")
      expect(!r.frame.armed && r.frame.progress == 0 && !feedback.contains(.armed),
             "an unavailable action never fills or ticks")
      expect(r.end(at: t + 0.2) == nil, "and releasing does nothing")

      let undoable = GestureRecognizer(map: .titleBar(canUndoPlacement: true))
      pinch(undoable, -0.025, steps: 10, &t)
      expect(undoable.frame.action == .undoPlacement, "pinch shows undo when there is a placement")
      expect(undoable.end(at: t + 0.2) == .undoPlacement, "undo")

      pinch(r, 0.01, steps: 5, &t)
      expect(r.frame.action == .magicTile && !r.frame.armed, "a small spread shows magic tiling")
      expect(r.end(at: t + 0.2) == nil, "a small spread and a pause cancels")
    }

    // Once a pinch starts, stray scroll deltas from the same touch are ignored.
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      swipe(r, dy: 3, steps: 2, &t)
      pinch(r, 0.06, steps: 4, &t)
      swipe(r, dy: 20, steps: 5, &t)
      expect(r.frame.action == .magicTile, "the frame reflects the pinch only")
      expect(r.end(at: t + 0.2) == .magicTile, "and the pinch decides")
    }

    // After ending or cancelling, the recognizer starts fresh.
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      swipe(r, dy: 5, steps: 12, &t)
      r.cancel()
      expect(r.frame == .idle, "cancel clears the frame")
      expect(r.end(at: t + 0.2) == nil, "a cancelled gesture does nothing on release")
      swipe(r, dx: -5, steps: 12, &t)
      expect(r.frame.action == .leftHalf, "a fresh gesture is recognized from zero")
    }

    // Directions follow the content, like scrolling the window itself.
    do {
      let up = GestureFingerDelta.fromScroll(deltaX: 0, deltaY: -10)
      expect(up == CGVector(dx: 0, dy: 10), "content moving up (natural: fingers up) is up — roll up")
      let wheelAway = GestureFingerDelta.fromScroll(deltaX: 0, deltaY: 3)
      expect(wheelAway.dy < 0, "a classic mouse wheel pushed away moves content down — fill, as in HyperDock")
      let right = GestureFingerDelta.fromScroll(deltaX: 10, deltaY: 0)
      expect(right == CGVector(dx: 10, dy: 0), "content moving right is right")
    }

    // Turning the corner: once left or right is armed, going on up or down takes that corner.
    do {
      let map = GestureMap.titleBar(canUndoPlacement: false)
      var r = GestureRecognizer(map: map)
      var t: TimeInterval = 0
      swipe(r, dx: -5, steps: 14, &t)
      expect(r.frame.action == .leftHalf && r.frame.armed, "left arms the left half first")
      swipe(r, dy: 5, steps: 10, &t)
      expect(r.frame.action == .topLeft && r.frame.armed, "then turning up takes the top left corner")
      expect(r.end(at: t + 0.2) == .topLeft, "and releasing there places it in the corner")

      r = GestureRecognizer(map: map)
      swipe(r, dx: 5, steps: 14, &t)
      swipe(r, dy: -3, steps: 10, &t)
      expect(r.frame.action == .rightHalf, "a small drift downward is not a turn")
      expect(r.end(at: t + 0.2) == .rightHalf, "so the right half stays")

      r = GestureRecognizer(map: map)
      swipe(r, dx: 5, steps: 14, &t)
      swipe(r, dy: -5, steps: 10, &t)
      expect(r.frame.action == .bottomRight, "turning down on the right is the bottom right corner")
      swipe(r, dy: 5, steps: 10, &t)
      expect(r.frame.action == .rightHalf && r.frame.armed, "turning back is the half again")

      r = GestureRecognizer(map: map)
      swipe(r, dx: -5, dy: -1.5, steps: 30, &t)
      expect(r.frame.action == .leftHalf && r.frame.armed, "a long left swipe that drifts down along an arc stays the left half")
      r.cancel()

      r = GestureRecognizer(map: map)
      swipe(r, dx: -5, steps: 6, &t)
      swipe(r, dy: 5, steps: 12, &t)
      expect(r.frame.action == .shade, "going up before left is armed is still a roll up, not a corner")
      r.cancel()

      r = GestureRecognizer(map: map)
      swipe(r, dx: -5, steps: 14, &t)
      swipe(r, dy: 5, steps: 10, &t)
      swipe(r, dx: 5, steps: 10, &t)
      expect(r.frame.action == .topLeft && !r.frame.armed, "pulling back sideways disarms the corner")
      expect(r.end(at: t + 0.2) == nil, "and releasing then does nothing")

      r = GestureRecognizer(map: GestureMap.titleBar(canUndoPlacement: false, appOwnsHorizontal: true))
      swipe(r, dx: -5, steps: 14, &t)
      swipe(r, dy: 5, steps: 10, &t)
      expect(r.frame == .idle, "on a tab strip left and right belong to the app, so there is no corner either")
      r.cancel()
    }

    // Left and right are a ladder too: ½ → ⅔ → ⅓, then on to the display on that side (or back to ½).
    do {
      var t: TimeInterval = 0
      expect(HorizontalLadder.next(from: nil, toward: .left, neighbor: false) == .leftHalf, "a free window goes to the left half first")
      expect(HorizontalLadder.next(from: .leftHalf, toward: .left, neighbor: false) == .leftTwoThirds, "then two thirds")
      expect(HorizontalLadder.next(from: .leftTwoThirds, toward: .left, neighbor: false) == .leftThird, "then one third")
      expect(HorizontalLadder.next(from: .leftThird, toward: .left, neighbor: true) == .toLeftDisplay, "then over to the display on the left")
      expect(HorizontalLadder.next(from: .leftThird, toward: .left, neighbor: false) == .leftHalf, "with no display there, back to the half")
      expect(HorizontalLadder.next(from: .leftThird, toward: .right, neighbor: false) == .centerThird, "from a third, pushing inward walks one column: the middle third")
      expect(HorizontalLadder.next(from: .centerThird, toward: .right, neighbor: false) == .rightThird, "then the right third")
      expect(HorizontalLadder.next(from: .centerThird, toward: .left, neighbor: false) == .leftThird, "and back to the left third")
      expect(HorizontalLadder.next(from: .rightThird, toward: .left, neighbor: false) == .centerThird, "the right third walks inward the same way")
      expect(HorizontalLadder.next(from: .leftTwoThirds, toward: .right, neighbor: false) == .rightHalf, "two thirds pushed the other way is still the other half")
      expect(HorizontalLadder.next(from: .rightTwoThirds, toward: .right, neighbor: false) == .rightThird, "and the right side climbs the same way")

      // The grid: a window already in the top or bottom row climbs the same ladder inside that row.
      let topLeft = GestureAction.topLeft.tile
      expect(HorizontalLadder.next(from: topLeft, toward: .left, neighbor: false) == .topLeftTwoThirds, "a top-left corner pushed left becomes the top-left two thirds")
      expect(HorizontalLadder.next(from: GestureAction.topLeftTwoThirds.tile, toward: .left, neighbor: false) == .topLeftThird, "then the top-left sixth")
      expect(HorizontalLadder.next(from: GestureAction.topLeftThird.tile, toward: .right, neighbor: false) == .topCenterThird, "the sixths walk across the row: top middle")
      expect(HorizontalLadder.next(from: GestureAction.topCenterThird.tile, toward: .right, neighbor: false) == .topRightThird, "then top right")
      expect(HorizontalLadder.next(from: GestureAction.topRightThird.tile, toward: .right, neighbor: false) == .topRight, "past the edge with no display, back to that row's half")
      expect(HorizontalLadder.next(from: GestureAction.bottomRightThird.tile, toward: .right, neighbor: true) == .toRightDisplay, "or over to the next display")
      expect(HorizontalLadder.next(from: topLeft, toward: .right, neighbor: false) == .topRight, "a corner pushed across stays in its row")
      expect(HorizontalLadder.next(from: GestureAction.bottomRightTwoThirds.tile, toward: .left, neighbor: false) == .bottomLeft, "bottom two thirds pushed across is the other bottom corner")
      let area = CGRect(x: 0, y: 0, width: 600, height: 400)
      expect(GestureAction.topCenterThird.tile?.frame(in: area) == CGRect(x: 200, y: 0, width: 200, height: 200), "the top middle sixth sits in the middle of the top row")
      expect(GestureAction.bottomRightTwoThirds.tile?.frame(in: area) == CGRect(x: 200, y: 200, width: 400, height: 200), "bottom-right two thirds")
      for layout in [RefitLayout.leftHalf, .rightHalf, .topLeft, .bottomRight, .leftTwoThirds, .rightTwoThirds, .leftThird, .rightThird] {
        let old: CGRect
        switch layout {
        case .leftHalf: old = CGRect(x: 0, y: 0, width: 300, height: 400)
        case .rightHalf: old = CGRect(x: 300, y: 0, width: 300, height: 400)
        case .topLeft: old = CGRect(x: 0, y: 0, width: 300, height: 200)
        case .bottomRight: old = CGRect(x: 300, y: 200, width: 300, height: 200)
        case .leftTwoThirds: old = CGRect(x: 0, y: 0, width: 400, height: 400)
        case .rightTwoThirds: old = CGRect(x: 200, y: 0, width: 400, height: 400)
        case .leftThird: old = CGRect(x: 0, y: 0, width: 200, height: 400)
        default: old = CGRect(x: 400, y: 0, width: 200, height: 400)
        }
        expect(layout.frame(in: area) == old, "\(layout) lands exactly where it did before the grid")
      }
      expect(RefitLayout(rawValue: GestureAction.bottomCenterThird.rawValue)?.frame(in: area) == CGRect(x: 200, y: 200, width: 200, height: 200),
             "grid cells are refitted after a display change too")
      // 3×3: a sixth turned toward its row's edge becomes a ninth; third rows step up and down one row at a time.
      let topLeftSixth = GestureAction.topLeftThird.tile
      expect(GridTurn.action(current: topLeftSixth, armed: .topCenterThird, horizontal: .right, vertical: .up) == .topCenterNinth,
             "a top sixth turned up (toward its edge) becomes a top ninth")
      expect(GridTurn.action(current: topLeftSixth, armed: .topCenterThird, horizontal: .right, vertical: .down) == .bottomRight,
             "turned the other way it is still a corner, as before")
      expect(GridTurn.action(current: GestureAction.topCenterNinth.tile, armed: .topCenterNinth, horizontal: .right, vertical: .down) == .middleCenterNinth,
             "in the top third row, turning down steps to the middle row")
      expect(GridTurn.action(current: GestureAction.middleCenterNinth.tile, armed: .middleLeftNinth, horizontal: .left, vertical: .down) == .bottomLeftNinth,
             "then the bottom row, in the column just walked to")
      expect(GridTurn.action(current: GestureAction.bottomLeftNinth.tile, armed: .bottomLeftNinth, horizontal: .left, vertical: .down) == .bottomLeftThird,
             "turning past the bottom third row goes back to the bottom half row")
      expect(GridTurn.action(current: GestureAction.topLeft.tile, armed: .topLeftTwoThirds, horizontal: .left, vertical: .up) == .topLeft,
             "a two-thirds cell does not become a ninth: turning stays a corner")
      expect(GridTurn.action(current: nil, armed: .leftHalf, horizontal: .left, vertical: .down) == .bottomLeft,
             "a free window turning a corner is unchanged")
      expect(HorizontalLadder.next(from: GestureAction.topLeftNinth.tile, toward: .right, neighbor: false) == .topCenterNinth,
             "ninths walk across their row")
      expect(HorizontalLadder.next(from: GestureAction.topLeftNinth.tile, toward: .left, neighbor: false) == .topLeftNinth,
             "at the edge with no display there, a ninth stays put so it can still turn")
      expect(HorizontalLadder.next(from: GestureAction.middleRightNinth.tile, toward: .right, neighbor: true) == .toRightDisplay,
             "or goes over to the next display")
      let square = CGRect(x: 0, y: 0, width: 600, height: 600)
      expect(GestureAction.middleCenterNinth.tile?.frame(in: square) == CGRect(x: 200, y: 200, width: 200, height: 200),
             "the middle ninth is the centre square")
      expect(KeyTurn.corner(after: .right, elapsed: 0.3, press: .up, from: topLeftSixth, armed: .topCenterThird) == .topCenterNinth,
             "the keyboard turns into ninths the same way")
      expect(RefitLayout(rawValue: GestureAction.bottomRightNinth.rawValue)?.frame(in: square) == CGRect(x: 400, y: 400, width: 200, height: 200),
             "ninths are refitted after a display change too")

      var g: TimeInterval = 0
      let inRow = GestureRecognizer(map: GestureMap.titleBar(canUndoPlacement: false, side: GestureAction.topLeftThird.tile))
      swipe(inRow, dx: 5, steps: 14, &g)
      expect(inRow.end(at: g + 0.2) == .topCenterThird, "swiping right on the top-left sixth walks to the top middle")
      let onHalf = GestureMap.titleBar(canUndoPlacement: false, side: .leftHalf)
      var r = GestureRecognizer(map: onHalf)
      swipe(r, dx: -5, steps: 14, &t)
      expect(r.frame.action == .leftTwoThirds && r.frame.armed, "swiping left on the left half is two thirds")
      expect(r.end(at: t + 0.2) == .leftTwoThirds, "on release")
      r = GestureRecognizer(map: GestureMap.titleBar(canUndoPlacement: false, side: .leftThird, neighbors: [.left]))
      swipe(r, dx: -5, steps: 14, &t)
      expect(r.end(at: t + 0.2) == .toLeftDisplay, "from one third it moves to the display on the left")
      r = GestureRecognizer(map: onHalf)
      swipe(r, dx: -5, steps: 14, &t)
      swipe(r, dy: -5, steps: 10, &t)
      expect(r.frame.action == .bottomLeft, "turning the corner still works from any column")
      r.cancel()

      // Flicking the title bar with the pointer climbs the same ladder: only fast releases count.
      let plain = GestureMap.titleBar(canUndoPlacement: false)
      expect(FlickClassifier.action(velocity: CGVector(dx: -900, dy: 0), map: plain) == nil, "an ordinary drag is too slow to be a flick")
      expect(FlickClassifier.action(velocity: CGVector(dx: -2400, dy: 100), map: plain) == .leftHalf, "a fast flick left is the left half")
      expect(FlickClassifier.action(velocity: CGVector(dx: 0, dy: -2600), map: plain) == .fill, "flicking down fills, like pulling down")
      expect(FlickClassifier.action(velocity: CGVector(dx: 60, dy: 2600), map: plain) == .shade, "flicking up rolls it up, like pushing up")
      let filled = GestureMap.titleBar(canUndoPlacement: true, isFilled: true)
      expect(FlickClassifier.action(velocity: CGVector(dx: 0, dy: 2600), map: filled) == .undoPlacement, "up on a filled window puts it back first")
      expect(FlickClassifier.windowFollowed(moved: CGVector(dx: -120, dy: 2), pointer: CGVector(dx: -160, dy: 0)), "a window a frame behind a fast flick still counts as dragged")
      expect(!FlickClassifier.windowFollowed(moved: CGVector(dx: 0, dy: 0), pointer: CGVector(dx: -160, dy: 0)), "dragging text or a tab out leaves the window where it was")
      expect(!FlickClassifier.windowFollowed(moved: CGVector(dx: 0, dy: 150), pointer: CGVector(dx: -160, dy: 0)), "a window moving another way is not following the pointer")
      expect(!FlickClassifier.windowFollowed(moved: CGVector(dx: -10, dy: 0), pointer: CGVector(dx: -20, dy: 0)), "a nudge is too short to judge")
      expect(FlickClassifier.action(velocity: CGVector(dx: 2000, dy: 2000), map: plain) == .topRight, "toward a corner takes that corner")
      expect(FlickClassifier.action(velocity: CGVector(dx: -1900, dy: -1900), map: plain) == .bottomLeft, "including the bottom ones")
      expect(FlickClassifier.action(velocity: CGVector(dx: -2400, dy: 0),
                                    map: GestureMap.titleBar(canUndoPlacement: false, side: .leftHalf)) == .leftTwoThirds,
             "flicking left again walks the left ladder")

      let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
      let leftOfMain = CGRect(x: -1920, y: -180, width: 1920, height: 1080)
      let aboveRight = CGRect(x: 1440, y: 1000, width: 1920, height: 1080)
      let frames = [main, leftOfMain, aboveRight]
      expect(DisplayNeighbor.index(in: frames, of: 0, toward: .left) == 1, "the external display on the left is found")
      expect(DisplayNeighbor.index(in: frames, of: 0, toward: .right) == nil, "a display up and away is not beside it")
      expect(DisplayNeighbor.index(in: frames, of: 1, toward: .right) == 0, "and from the left display, the main one is on the right")
    }

    // Arrow keys climb the same ladder as the gestures, one step per press.
    do {
      let plain = GestureMap.titleBar(canUndoPlacement: false)
      expect(plain.keyFrame(.down) == GestureFrame(action: .fill, progress: 1), "down on a normal window fills")
      expect(plain.keyFrame(.up) == GestureFrame(action: .shade, progress: 1), "up on a normal window rolls up")
      expect(plain.keyFrame(.left)?.armed == true && plain.keyFrame(.left)?.action == .leftHalf, "left is the left half")
      let filled = GestureMap.titleBar(canUndoPlacement: true, isFilled: true)
      expect(filled.keyFrame(.up) == GestureFrame(action: .undoPlacement, progress: 1), "up on a filled window undoes the fill")
      expect(filled.keyFrame(.down) == nil, "down on a filled window has nothing to do")
      let stuck = GestureMap.titleBar(canUndoPlacement: false, isFilled: true)
      expect(stuck.keyFrame(.up)?.action == .shade, "filled by hand with nothing to undo: up rolls up")
      expect(GestureMap.strip.keyFrame(.down) == GestureFrame(action: .expand, progress: 1), "down on a bar unrolls it")
      expect(GestureMap.strip.keyFrame(.up) == nil, "up on a bar does nothing")
      var noUndo = GestureMap.titleBar(canUndoPlacement: false)
      noUndo.up = .undoPlacement
      let explained = noUndo.keyFrame(.up)
      expect(explained?.action == .undoPlacement && explained?.armed == false, "an unavailable step explains itself and does nothing")
    }

    // The keyboard turns corners too: a quick up or down right after left or right.
    do {
      expect(KeyTurn.corner(after: .left, elapsed: 0.3, press: .down) == .bottomLeft, "⌃⌘← then ⌃⌘↓ is the bottom left corner")
      expect(KeyTurn.corner(after: .right, elapsed: 0.5, press: .up) == .topRight, "⌃⌘→ then ⌃⌘↑ is the top right corner")
      expect(KeyTurn.corner(after: .left, elapsed: 1.2, press: .down) == nil, "after a pause, ⌃⌘↓ is just a step larger again")
      expect(KeyTurn.corner(after: nil, elapsed: 0.1, press: .down) == nil, "without a half first there is no corner")
      expect(KeyTurn.corner(after: .left, elapsed: 0.2, press: .right) == nil, "left then right is not a turn")
    }

    // Thirds go back too.
    do {
      let big = CGRect(x: 0, y: 25, width: 2400, height: 1200)
      let small = CGRect(x: 0, y: 25, width: 1500, height: 900)
      let placed = RefitLayout.rightTwoThirds.frame(in: big)
      expect(placed == CGRect(x: 800, y: 25, width: 1600, height: 1200), "right two thirds of the big screen")
      let moved = CGRect(x: 0, y: 25, width: 1500, height: 900)
      expect(DisplayRefit.target(layout: .rightTwoThirds, placed: placed, current: moved, area: small)
               == CGRect(x: 500, y: 25, width: 1000, height: 900), "a two-thirds window squeezed by the system is laid out again")
    }

    // Corners go back to their corner on the new screen too.
    do {
      let big = CGRect(x: 0, y: 25, width: 2000, height: 1200)
      let small = CGRect(x: 0, y: 25, width: 1400, height: 860)
      let placed = RefitLayout.bottomRight.frame(in: big)
      expect(placed == CGRect(x: 1000, y: 625, width: 1000, height: 600), "bottom right quarter of the big screen")
      let moved = CGRect(x: 400, y: 285, width: 1000, height: 600)
      expect(DisplayRefit.target(layout: .bottomRight, placed: placed, current: moved, area: small)
               == CGRect(x: 700, y: 455, width: 700, height: 430), "a quarter moved by the system is laid out again")
      let resized = CGRect(x: 100, y: 100, width: 640, height: 400)
      expect(DisplayRefit.target(layout: .topLeft, placed: RefitLayout.topLeft.frame(in: big), current: resized, area: small) == nil,
             "a quarter resized by hand stays as the person left it")
    }

    // Flicks: measuring the release and gliding into place.
    do {
      // Turns a list of per-frame velocities into samples, integrating the path at 8ms steps.
      func samples(_ velocities: [CGVector], from origin: CGPoint = CGPoint(x: 1200, y: 600),
                   start: TimeInterval = 1.0, step: TimeInterval = 0.008) -> [FlickSample] {
        var result = [FlickSample(time: start, point: origin)]
        var point = origin
        for (index, velocity) in velocities.enumerated() {
          point.x += velocity.dx * CGFloat(step)
          point.y += velocity.dy * CGFloat(step)
          result.append(FlickSample(time: start + TimeInterval(index + 1) * step, point: point))
        }
        return result
      }

      // The samples that leave the hand at the last one.
      func lifting(_ velocities: [CGVector]) -> ([FlickSample], TimeInterval) {
        let s = samples(velocities)
        return (s, s.last!.time)
      }

      // A straight throw keeps the speed it was thrown with.
      let (steady, steadyLift) = lifting(Array(repeating: CGVector(dx: -24 / 0.008, dy: 0), count: 16))
      guard let steadyRelease = FlickRelease.measure(steady, lift: steadyLift) else {
        expect(false, "a steady throw at 8ms a frame should measure")
        return
      }
      expect(abs(steadyRelease.velocity.dx - (-3000)) <= 150, "a steady throw keeps its speed")
      expect(abs(steadyRelease.velocity.dy) < 50, "a straight throw does not drift sideways")
      expect(steadyRelease.isThrow, "a steady throw is a throw")
      expect(FlickClassifier.action(release: steadyRelease, map: .titleBar(canUndoPlacement: false)) == .leftHalf,
             "thrown left, the window goes to the left half")

      // Slowing down before letting go is a deliberate drag, however quick the peak was.
      let slowing = (0..<19).map { CGVector(dx: -3000 + 2850 * CGFloat($0) / 18, dy: 0) }
      let (slowSamples, slowLift) = lifting(slowing)
      guard let slowRelease = FlickRelease.measure(slowSamples, lift: slowLift) else {
        expect(false, "a slowing drag should still have something to measure")
        return
      }
      expect(slowRelease.peakSpeed > 2000, "it was moving fast at some point")
      expect(!slowRelease.isThrow, "slowing down before letting go is a drag, not a throw")
      expect(FlickClassifier.action(release: slowRelease, map: .titleBar(canUndoPlacement: false)) == nil,
             "a drag that ends slow does nothing")

      // Speeding up and letting go at the top of the swing is a throw.
      let (snapSamples, snapLift) = lifting((1...10).map { CGVector(dx: -300 * CGFloat($0), dy: 0) })
      guard let snap = FlickRelease.measure(snapSamples, lift: snapLift) else {
        expect(false, "an accelerating snap should measure")
        return
      }
      expect(snap.isThrow, "letting go while accelerating is a throw")
      expect(snap.speed >= FlickClassifier.minimumSpeed, "an accelerating snap is fast enough to act on")

      // A shaking hand does not fool the fit: ±3 pt of alternating noise on a steady −2400 pt/s throw.
      var (jitterSamples, jitterLift) = lifting(Array(repeating: CGVector(dx: -2400, dy: 0), count: 16))
      for index in jitterSamples.indices { jitterSamples[index].point.x += index.isMultiple(of: 2) ? 3 : -3 }
      guard let jitter = FlickRelease.measure(jitterSamples, lift: jitterLift) else {
        expect(false, "a jittery throw should still measure")
        return
      }
      expect(abs(jitter.velocity.dx - (-2400)) <= 240, "a shaking hand does not change the speed")

      // One frame that jumps far ahead (three-finger drag does this) must not make a real throw look like it slowed down.
      var (spiky, spikyLift) = lifting(Array(repeating: CGVector(dx: -3000, dy: 0), count: 16))
      spiky[10].point.x -= 160
      guard let spike = FlickRelease.measure(spiky, lift: spikyLift) else {
        expect(false, "a throw with one jumpy frame should measure")
        return
      }
      expect(spike.isThrow, "one jumpy frame does not turn a throw into a placement")
      // Events that bunch up and land as one big step, then carry on at the same speed.
      var (stepped, steppedLift) = lifting(Array(repeating: CGVector(dx: -3000, dy: 0), count: 16))
      for index in 10..<stepped.count { stepped[index].point.x -= 160 }
      expect(FlickRelease.measure(stepped, lift: steppedLift)?.isThrow == true, "a bunched-up step is still a throw")

      // Two samples are not enough to fit anything.
      expect(FlickRelease.measure(samples([CGVector(dx: -2400, dy: 0)]), lift: 1.008) == nil,
             "two samples are not enough to measure a release")

      // A button or a finger leaving right after the last move carries the throw on.
      let last = 5.0
      let buttonUp = FlickLift.resolve(.buttonUp, signal: last + 0.02, lastSample: last)
      expect(buttonUp?.lift == last + 0.02 && buttonUp?.carry == true, "a button released right away carries the throw")
      expect(FlickLift.resolve(.buttonUp, signal: last + 0.2, lastSample: last) == nil,
             "a button released much later is not this throw")

      // Three-finger drag waits for the system's button up, a couple of frames late.
      let touchLift = FlickLift.resolve(.touchLift, signal: last + 0.03, lastSample: last)
      expect(touchLift?.lift == last + 0.012 && touchLift?.carry == true, "a finger leaving counts one frame later")
      expect(abs((touchLift?.lift ?? 0) - (last + 0.012)) <= 1e-9, "and to the exact frame")
      expect(FlickLift.resolve(.touchLift, signal: last + 0.2, lastSample: last) == nil,
             "but not after the hand has clearly stopped")

      // A late button up with no finger lift: the window already stopped, so carry is false.
      let late = FlickLift.resolve(.lateUp, signal: last + 0.05, lastSample: last)
      expect(late?.lift == last && late?.carry == true, "a late up soon after the last move still carries")
      let later = FlickLift.resolve(.lateUp, signal: last + 0.5, lastSample: last)
      expect(later?.lift == last && later?.carry == false, "a late up after the window has stopped does not carry")
      expect(FlickLift.resolve(.lateUp, signal: last + 1.5, lastSample: last) == nil,
             "a very late up is not this throw at all")

      // Fingers leaving the trackpad at the edge they were moving toward is a reposition, not a throw.
      expect(FlickLift.isRepositioning([CGPoint(x: 0.03, y: 0.5)], velocity: CGVector(dx: -2500, dy: 0)),
             "leaving at the left edge while moving left is a reposition")
      expect(!FlickLift.isRepositioning([CGPoint(x: 0.5, y: 0.5)], velocity: CGVector(dx: -2500, dy: 0)),
             "the middle of the trackpad is not an edge")
      expect(!FlickLift.isRepositioning([CGPoint(x: 0.97, y: 0.5)], velocity: CGVector(dx: -2500, dy: 0)),
             "leaving at the far edge is not the edge it was heading for")
      expect(FlickLift.isRepositioning([CGPoint(x: 0.5, y: 0.95)], velocity: CGVector(dx: 0, dy: 2500)),
             "leaving at the top edge while moving up is a reposition")
      expect(!FlickLift.isRepositioning([], velocity: CGVector(dx: -2500, dy: 0)),
             "no fingers means no reposition")

      // A natural arm arc still counts as a straight flick.
      let arc = FlickRelease(velocity: CGVector(dx: -2400, dy: 1100), peakSpeed: hypot(-2400, 1100))
      expect(FlickClassifier.action(release: arc, map: .titleBar(canUndoPlacement: false)) == .leftHalf,
             "a flick 25 degrees off horizontal is still the left half")
      expect(FlickClassifier.action(release: FlickRelease(velocity: CGVector(dx: -2000, dy: 2000), peakSpeed: 2829),
                                    map: .titleBar(canUndoPlacement: false)) == .topLeft,
             "a flick right at the corner takes the top left")
      expect(FlickClassifier.action(release: FlickRelease(velocity: CGVector(dx: -1200, dy: 0), peakSpeed: 1200),
                                    map: .titleBar(canUndoPlacement: false)) == nil,
             "too slow to be a flick")
      // A finger right on the screen moves the window one to one, with no pointer acceleration: a gentler flick counts.
      let gentle = FlickRelease(velocity: CGVector(dx: -1000, dy: 0), peakSpeed: 1000)
      expect(FlickClassifier.action(release: gentle, map: .titleBar(canUndoPlacement: false)) == nil,
             "a gentle flick with the pointer is just a drag")
      expect(FlickClassifier.action(release: gentle, map: .titleBar(canUndoPlacement: false), direct: true) == .leftHalf,
             "the same flick with a finger on the screen tiles the window")
      let slowedByHand = FlickRelease(velocity: CGVector(dx: -3000, dy: 0), peakSpeed: 6000)
      expect(!slowedByHand.isThrow && FlickClassifier.action(release: slowedByHand, map: .titleBar(canUndoPlacement: false)) == nil,
             "fast at release but already at half speed: that was a drag")

      // The springs start exactly where they are put.
      for spring in [FlickSpring.position, FlickSpring.size] {
        let start = spring.state(displacement: 100, velocity: 40, at: 0)
        expect(abs(start.x - 100) <= 1e-6 && abs(start.v - 40) <= 1e-6, "a spring starts where it is put")
      }

      // A size change never bounces past its target.
      let size = FlickSpring.size
      var previous = size.state(displacement: 100, velocity: 0, at: 0).x
      var below = false
      var t = 0.0
      while t <= 0.8 {
        let x = size.state(displacement: 100, velocity: 0, at: t).x
        if x > previous + 1e-9 { below = true }
        if x < -0.001 { below = true }
        previous = x
        t += 0.01
      }
      expect(!below, "a size change never goes backwards or past the target")
      expect(abs(size.state(displacement: 100, velocity: 0, at: 0.8).x) < 1, "and it has arrived by 0.8s")

      // A fling that would overshoot far is slowed down, but never sent backwards.
      let capped = FlickSpring.position.limitingOvershoot(displacement: 100, velocity: -6000, limit: 28)
      expect(abs(capped) < 6000, "a hard fling is slowed down before it overshoots")
      expect(capped < 0, "and it still heads toward the target")
      expect(FlickSpring.position.overshoot(displacement: 100, velocity: capped) <= 28.5,
             "the slowdown keeps the overshoot inside the limit")
      expect(FlickSpring.position.limitingOvershoot(displacement: 100, velocity: -300, limit: 28) == -300,
             "a gentle nudge is left alone")

      // The window keeps gliding the way it was thrown, and settles within a second.
      let glide = FlickGlidePath(from: CGRect(x: 900, y: 300, width: 640, height: 452),
                                 to: CGRect(x: 0, y: 34, width: 855, height: 1003),
                                 velocity: CGVector(dx: -3000, dy: 0))
      let startFrame = glide.frame(at: 0)
      expect(abs(startFrame.minX - 900) <= 0.01 && abs(startFrame.minY - 300) <= 0.01
               && abs(startFrame.width - 640) <= 0.01 && abs(startFrame.height - 452) <= 0.01,
             "the glide starts at the window it was thrown from")
      expect(glide.frame(at: 0.004).minX < 900 - 8, "a thrown window keeps moving the way it was thrown")
      let earlyVelocity = (glide.frame(at: 0.002).minX - glide.frame(at: 0).minX) / 0.002
      expect(abs(earlyVelocity - (-3000)) <= 300, "it glides at the speed it was thrown with")
      expect(glide.duration >= 0.25 && glide.duration <= 1.0, "it takes between a quarter and a whole second")
      let endFrame = glide.frame(at: glide.duration)
      expect(abs(endFrame.minX - 0) <= 1.5 && abs(endFrame.minY - 34) <= 1.5
               && abs(endFrame.width - 855) <= 1.5 && abs(endFrame.height - 1003) <= 1.5,
             "and it lands on the target frame")
      expect(glide.settled(at: glide.duration), "and is settled when it gets there")

      // Even a huge fling at a nearby edge never slams more than 28pt past it.
      let nearEdge = FlickGlidePath(from: CGRect(x: 60, y: 200, width: 600, height: 400),
                                    to: CGRect(x: 0, y: 34, width: 855, height: 1003),
                                    velocity: CGVector(dx: -8000, dy: 0))
      var leftmost = CGFloat.greatestFiniteMagnitude
      var step = 0.0
      while step <= nearEdge.duration {
        leftmost = min(leftmost, nearEdge.frame(at: step).minX)
        step += 1.0 / 240
      }
      expect(leftmost >= -28.5, "a huge fling at a nearby edge overshoots by no more than 28pt")

    }

    // Notch alerts: only essential, not too often.
    do {
      var policy = ChangeAlertPolicy()

      // A title that never changed is nothing to look at.
      var quiet = ChangeAlertPolicy()
      quiet.baseline(CGWindowID(7), title: "Building…", at: 100)
      expect(quiet.titleSettled(CGWindowID(7), title: "Building…", at: 100.5) == .ignore,
             "an unchanged title is ignored")

      // Right after a window is tucked away, one change of title is the app tidying up.
      _ = quiet.titleSettled(CGWindowID(7), title: "Build 42", at: 101)
      expect(quiet.titles[CGWindowID(7)] == "Build 42", "a change during the quiet period is remembered")
      expect(quiet.titleSettled(CGWindowID(7), title: "Build 42", at: 110) == .ignore,
             "the tucked-away title is not announced")

      // A window that just got tucked away and then really says something alerts.
      policy.baseline(CGWindowID(8), title: "Building…", at: 100)
      expect(policy.titleSettled(CGWindowID(8), title: "Build Succeeded", at: 105) == .alert,
             "a settled change after the quiet period alerts")

      // Two changes in quick succession: the second only gets a dot, but a fresh one later alerts.
      expect(policy.titleSettled(CGWindowID(8), title: "Deploying", at: 120) == .mark,
             "a change within 30s of the last alert is only marked")
      expect(policy.titleSettled(CGWindowID(8), title: "All done", at: 140) == .alert,
             "a change a full 30s after the alert is worth announcing")

      // A window that keeps changing is marked, not announced.
      var noisy = ChangeAlertPolicy()
      noisy.baseline(CGWindowID(9), title: "Step 0", at: 100)
      _ = noisy.titleSettled(CGWindowID(9), title: "Step 1", at: 103)
      _ = noisy.titleSettled(CGWindowID(9), title: "Step 2", at: 104)
      _ = noisy.titleSettled(CGWindowID(9), title: "Step 3", at: 105)
      expect(noisy.titleSettled(CGWindowID(9), title: "Step 4", at: 106) == .mark,
             "the fourth change in a minute is only marked")
      expect(noisy.titleSettled(CGWindowID(9), title: "Step 5", at: 170) == .alert,
             "a change once the storm has settled announces again")

      // A forgotten window is left alone.
      policy.forget(CGWindowID(8))
      expect(policy.titleSettled(CGWindowID(8), title: "Anything", at: 200) == .ignore,
             "a window we stopped tracking never alerts")

      // Windows do not share the alert budget.
      var pair = ChangeAlertPolicy()
      pair.baseline(CGWindowID(11), title: "Building…", at: 100)
      _ = pair.titleSettled(CGWindowID(11), title: "Done", at: 105)
      pair.baseline(CGWindowID(12), title: "Building…", at: 100)
      expect(pair.titleSettled(CGWindowID(12), title: "Done", at: 106) == .alert,
             "an alert on one window does not silence another")
    }

    // Rubber band and momentum projection (WWDC18).
    do {
      let near = FluidMotion.rubberBand(10, limit: 40), far = FluidMotion.rubberBand(10_000, limit: 40)
      expect(near > 0 && near < 10, "a small pull moves less than the finger")
      expect(far < 40 && far > 39, "a huge pull approaches the limit without reaching it (no wall)")
      expect(FluidMotion.rubberBand(30, limit: 40) > FluidMotion.rubberBand(20, limit: 40), "pulling further always moves further")
      let slope = FluidMotion.rubberBandSlope(20, limit: 40)
      let numeric = (FluidMotion.rubberBand(20.01, limit: 40) - FluidMotion.rubberBand(19.99, limit: 40)) / 0.02
      expect(abs(slope - numeric) < 0.001, "the slope matches the curve")
      expect(abs(FluidMotion.projection(velocity: 1000) - 499) < 0.5, "normal deceleration carries 1000 pt/s about 499 pt")
      expect(abs(FluidMotion.projection(velocity: 1000, decelerationRate: 0.99) - 99) < 0.5, "fast deceleration carries it about 99 pt")
      expect(FluidMotion.projection(velocity: -500) < 0, "projection keeps the direction")
    }

    print("PASS: trackpad gestures — hysteresis, deliberate swipe with one tick, pause cancels, flick projection, short flick, pull-back cancel, halves, direction switch lead, return to origin, vertical ladder (fill / undo fill / roll up), app-owned horizontal on tabs, late map update, ownership rules, double tap, display refit, strip expand, spread/pinch with undo availability (unavailable undo explains itself), pinch exclusivity, reset, content direction, arrow-key ladder, corner refit, turning corners, horizontal ladder with thirds and the middle third, grid rows (quarters → two thirds → sixths, walking across) and 3×3 ninths by turning within a row, pushing to the next display, keyboard corner turns, flick directions, flick release and glide physics, notch change alerts, rubber band and projection")
  }
}
