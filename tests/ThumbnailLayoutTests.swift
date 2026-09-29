import CoreGraphics
import Foundation

@main struct ThumbnailLayoutTests {
  static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }

  static func close(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01
      && abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
  }

  static func main() {
    // Size: fits a 180 box with the window's aspect; never bigger than the window.
    expect(ThumbnailLayout.size(for: CGSize(width: 1200, height: 800)) == CGSize(width: 180, height: 120),
           "landscape fits the width")
    expect(ThumbnailLayout.size(for: CGSize(width: 600, height: 1200)) == CGSize(width: 90, height: 180),
           "portrait fits the height instead of growing tall")
    expect(ThumbnailLayout.size(for: CGSize(width: 150, height: 100)) == CGSize(width: 150, height: 100),
           "a window smaller than the box is not enlarged")
    // A very flat window keeps a clickable short side; the long side is capped (picture is cropped).
    let flat = ThumbnailLayout.size(for: CGSize(width: 1700, height: 100))
    expect(flat.height == 28 && flat.width <= 360, "flat windows keep a 28pt short side: \(flat)")
    let tiny = ThumbnailLayout.size(for: CGSize(width: 300, height: 20))
    expect(tiny.height == 20, "never taller than the window itself: \(tiny)")
    expect(ThumbnailLayout.size(for: .zero).width == 180, "degenerate sizes still give a thumbnail")

    // Placement: top-left stays at the window's top-left (Cocoa, y up).
    let window = CGRect(x: 300, y: 200, width: 900, height: 600)
    let thumb = ThumbnailLayout.thumbnail(topLeft: CGPoint(x: window.minX, y: window.maxY), window: window.size)
    expect(thumb.minX == window.minX && thumb.maxY == window.maxY, "thumbnail sits at the window's top-left")
    let overlay = ThumbnailLayout.overlayFrame(thumbnail: thumb)
    expect(overlay.minX == thumb.minX && overlay.maxY == thumb.maxY,
           "the overlay's top-left is still the window's top-left (unfold and journal rely on it)")
    expect(close(ThumbnailLayout.thumbnail(inOverlayFrame: overlay), thumb), "overlay → thumbnail round trip")
    let inView = ThumbnailLayout.thumbnailInView(overlaySize: overlay.size)
    expect(inView.maxY == overlay.height && inView.minX == 0 && inView.size == thumb.size,
           "thumbnail fills the view except the icon overhang")
    let icon = ThumbnailLayout.iconInView(overlaySize: overlay.size)
    expect(icon.maxX == overlay.width && icon.minY == 0 && icon.maxX - inView.maxX == ThumbnailLayout.iconOverhang,
           "icon hangs over the bottom-right corner")

    // Tidy: one row from the bottom-left of the visible area, wrapping upward.
    let visible = CGRect(x: 0, y: 80, width: 600, height: 800)
    let sizes = [CGSize(width: 180, height: 120), CGSize(width: 180, height: 100), CGSize(width: 180, height: 90),
                 CGSize(width: 90, height: 180)]
    let frames = ThumbnailLayout.tidy(sizes, in: visible)
    expect(frames.count == 4, "every thumbnail gets a slot")
    expect(frames[0].minX == 16 && frames[0].minY == 80 + 12 + ThumbnailLayout.iconOverhang,
           "first slot hugs the bottom-left, leaving room for the icon overhang: \(frames[0])")
    expect(frames[1].minX == frames[0].maxX + ThumbnailLayout.iconOverhang + 10 && frames[1].minY == frames[0].minY,
           "second slot follows on the same row")
    expect(frames[2].minX == 16 && frames[2].minY == frames[0].minY + 120 + 10 + ThumbnailLayout.iconOverhang,
           "a full row wraps upward above the tallest thumbnail: \(frames[2])")
    for (a, b) in zip(frames, frames.dropFirst()) {
      let reachA = ThumbnailLayout.overlayFrame(thumbnail: a), reachB = ThumbnailLayout.overlayFrame(thumbnail: b)
      expect(!reachA.intersects(reachB), "tidied thumbnails (with icons) do not overlap")
    }
    for frame in frames {
      expect(ThumbnailLayout.overlayFrame(thumbnail: frame).maxX <= visible.maxX - 16 + 0.01, "stays inside the right margin")
    }

    // Translucency: the old switch carries over until the slider is moved.
    let suite = "ThumbnailLayoutTests.\(getpid())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    expect(ShadeTranslucency.fraction(in: defaults) == 0, "default is opaque (nothing changes)")
    defaults.set(true, forKey: ShadeTranslucency.legacyDefaultsKey)
    expect(abs(ShadeTranslucency.opacity(in: defaults) - 0.82) < 0.0001, "old switch on = 0.82 like before")
    ShadeTranslucency.set(0.3, in: defaults)
    expect(abs(ShadeTranslucency.fraction(in: defaults) - 0.3) < 0.0001, "slider value wins once moved")
    expect(defaults.bool(forKey: ShadeTranslucency.legacyDefaultsKey), "old switch follows the slider (on)")
    ShadeTranslucency.set(0, in: defaults)
    expect(!defaults.bool(forKey: ShadeTranslucency.legacyDefaultsKey) && ShadeTranslucency.fraction(in: defaults) == 0,
           "slider at 0 turns the old switch off")
    // The old switch still works after the slider was used (both controls on screen at once).
    ShadeTranslucency.set(0.3, in: defaults)
    defaults.set(false, forKey: ShadeTranslucency.legacyDefaultsKey)
    expect(ShadeTranslucency.fraction(in: defaults) == 0, "old switch turned off after the slider: opaque")
    defaults.set(true, forKey: ShadeTranslucency.legacyDefaultsKey)
    expect(abs(ShadeTranslucency.fraction(in: defaults) - 0.3) < 0.0001, "old switch back on: the slider's value again")
    ShadeTranslucency.set(0, in: defaults)
    defaults.set(true, forKey: ShadeTranslucency.legacyDefaultsKey)
    expect(abs(ShadeTranslucency.fraction(in: defaults) - ShadeTranslucency.legacyFraction) < 0.0001,
           "old switch turned on with the slider at 0: the old 18%")
    expect(ShadeTranslucency.set(5, in: defaults) == ShadeTranslucency.maximum, "clamped to the maximum")
    expect(ShadeTranslucency.set(.nan, in: defaults) == 0, "garbage becomes opaque")
    print("PASS thumbnail layout and translucency")
  }
}
