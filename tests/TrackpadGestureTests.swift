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

    // On a filled window, up first undoes the fill; down and spread have nothing left to do.
    do {
      let filled = GestureRecognizer(map: .titleBar(canUndoPlacement: true, isFilled: true))
      var t: TimeInterval = 0
      swipe(filled, dy: 5, steps: 12, &t)
      expect(filled.frame.action == .undoPlacement, "up on a window we filled undoes the fill first")
      expect(filled.end(at: t + 0.2) == .undoPlacement, "undo")
      swipe(filled, dy: -5, steps: 12, &t)
      expect(filled.frame == .idle && filled.end(at: t + 0.2) == nil, "down on a filled window does nothing")
      pinch(filled, 0.03, steps: 10, &t)
      expect(filled.frame == .idle && filled.end(at: t + 0.2) == nil, "spread on a filled window does nothing")

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

    // Spread fills the screen; pinch undoes the last placement only when there is one.
    do {
      var t: TimeInterval = 0
      let r = GestureRecognizer(map: titleBar)
      pinch(r, 0.025, steps: 10, &t)
      expect(r.frame.action == .fill && r.frame.armed, "spreading 0.25 arms fill")
      expect(r.end(at: t + 0.2) == .fill, "fill")

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
      expect(r.frame.action == .fill && !r.frame.armed, "a small spread shows fill")
      expect(r.end(at: t + 0.2) == nil, "a small spread and a pause cancels")
    }

    // Once a pinch starts, stray scroll deltas from the same touch are ignored.
    do {
      let r = GestureRecognizer(map: titleBar)
      var t: TimeInterval = 0
      swipe(r, dy: 3, steps: 2, &t)
      pinch(r, 0.06, steps: 4, &t)
      swipe(r, dy: 20, steps: 5, &t)
      expect(r.frame.action == .fill, "the frame reflects the pinch only")
      expect(r.end(at: t + 0.2) == .fill, "and the pinch decides")
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

    print("PASS: trackpad gestures — hysteresis, deliberate swipe with one tick, pause cancels, flick projection, short flick, pull-back cancel, halves, direction switch lead, return to origin, vertical ladder (fill / undo fill / roll up), app-owned horizontal on tabs, late map update, ownership rules, double tap, display refit, strip expand, spread/pinch with undo availability (unavailable undo explains itself), pinch exclusivity, reset, content direction")
  }
}
