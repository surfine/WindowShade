import CoreGraphics
import Foundation

@main struct GlanceIntentTests {
  static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }

  static func main() {
    let a: CGWindowID = 11
    let b: CGWindowID = 22
    let onA = GlancePointerSample(strip: a)
    let onB = GlancePointerSample(strip: b)
    let nowhere = GlancePointerSample(strip: nil)
    let onPanel = GlancePointerSample(strip: nil, overGlance: true)

    // Passing over a strip must not open anything, but may prepare the picture early.
    do {
      let intent = GlanceIntent()
      expect(intent.entered(a, at: 0) == [.prewarm(a)], "entering prepares the picture")
      expect(intent.sample(onA, at: 0.1).isEmpty, "no glance before the dwell time")
      expect(intent.sample(nowhere, at: 0.15) == [.discard(a)], "passing through discards")
      expect(intent.sample(onA, at: 0.5).isEmpty && !intent.isOpen, "no late open after leaving")
    }

    // Dwelling opens; moving down onto the picture keeps it; leaving closes after the grace.
    do {
      let intent = GlanceIntent()
      _ = intent.entered(a, at: 0)
      expect(intent.sample(onA, at: 0.23) == [.open(a)], "dwell opens")
      expect(intent.sample(onPanel, at: 0.4).isEmpty, "moving onto the picture keeps it open")
      expect(intent.sample(nowhere, at: 0.5).isEmpty, "a brief slip does not close")
      expect(intent.sample(onPanel, at: 0.55).isEmpty, "coming back resets the grace")
      expect(intent.sample(nowhere, at: 0.6).isEmpty, "leaving starts the grace")
      expect(intent.sample(nowhere, at: 0.7).isEmpty, "still within the grace")
      expect(intent.sample(nowhere, at: 0.77) == [.close(a)], "leaving closes")
      expect(!intent.needsSampling, "idle after closing")
    }

    // Resting on the traffic lights is not an intent to look; the clock restarts after them.
    do {
      let intent = GlanceIntent()
      _ = intent.entered(a, at: 0)
      var controls = onA
      controls.overControls = true
      expect(intent.sample(controls, at: 0.3).isEmpty, "controls hold the glance back")
      expect(intent.sample(controls, at: 0.9).isEmpty, "even for a long time")
      expect(intent.sample(onA, at: 1.0).isEmpty, "clock restarts after the controls")
      expect(intent.sample(onA, at: 1.2) == [.open(a)], "then opens after its own dwell")
    }

    // Sliding to a neighbouring strip switches the glance to it.
    do {
      let intent = GlanceIntent()
      _ = intent.entered(a, at: 0)
      _ = intent.sample(onA, at: 0.3)
      expect(intent.sample(onB, at: 0.4) == [.close(a), .prewarm(b)], "switches strips")
      expect(intent.sample(onB, at: 0.63) == [.open(b)], "the new strip needs its own dwell")
      expect(intent.entered(a, at: 0.7) == [.close(b), .prewarm(a)], "entering another closes")
    }

    // Right after folding, the pointer is still on the strip: it must leave once first.
    do {
      let intent = GlanceIntent()
      intent.block(a)
      expect(intent.entered(a, at: 0).isEmpty, "the strip under the fold click stays shut")
      expect(!intent.needsSampling, "nothing is prepared")
      intent.unblock(a)
      expect(intent.entered(a, at: 1) == [.prewarm(a)], "after leaving, hover works")
    }

    // A click opens at once, even on a blocked strip, and a second click changes nothing.
    do {
      let intent = GlanceIntent()
      intent.block(a)
      expect(intent.clicked(a, at: 0) == [.prewarm(a), .open(a)], "click opens at once")
      expect(intent.clicked(a, at: 0.05).isEmpty, "second click of a double click is a no-op")
      let arming = GlanceIntent()
      _ = arming.entered(a, at: 0)
      expect(arming.clicked(a, at: 0.05) == [.open(a)], "click during the dwell opens now")
    }

    // An open glance never jumps to a strip that is still blocked.
    do {
      let intent = GlanceIntent()
      _ = intent.clicked(a, at: 0)
      intent.block(b)
      expect(intent.sample(onB, at: 0.1).isEmpty, "blocked strip counts as leaving")
      expect(intent.sample(onB, at: 0.3) == [.close(a)], "and closes after the grace")
    }

    // Expanding or dragging one window only affects its own glance.
    do {
      let intent = GlanceIntent()
      _ = intent.clicked(a, at: 0)
      expect(intent.forget(b).isEmpty, "other windows leave the glance alone")
      expect(intent.forget(a) == [.close(a)], "its own window closes it")
      _ = intent.entered(b, at: 1)
      expect(intent.cancel() == [.discard(b)], "cancel discards an unopened preparation")
    }

    print("PASS glance intent")
  }
}
