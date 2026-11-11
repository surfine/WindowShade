#!/usr/bin/env python3
"""Consumer for render-native-surfaces.sh --swift6 output of ProgressQuantityPreview.swift.

Reads ONLY ABS_OUTPUT/frames.json, sources.json, renderer.json plus the local
source files NAMED BY sources.json (for SHA256). It never touches UI, product
code, the network, permissions, or rewrites any other file.

What this proves: the emitted static frame JSON is internally consistent with
the current on-disk sources and with the ProgressQuantityPreview.swift
control-path schema (26 frames = 2 appearances x 13 samples, exact real
quantities, identical corresponding actual quantity/geometry/core labels across
both parent appearances, hidden window/host flags, one completion, zero
windows/controllers/actions, and finite contained tile/picture root frames).
What it cannot prove: that anything was actually drawn, composited, or
presented. The consumer runs no drawing, no compositor, no GPU and no hardware
path, so visual/compositor/motion claims stay `not_run`. A clean ast.parse of
this script is NOT behavioural evidence.

Design-review boundary: naturalQuantityWidth vs available tile width minus 20
(and minus ring diameter when a ring is shown) is only ever REPORTED. It is not
failed here. If an overflow is observed the script records the issue and exits
with `status: design_review_required` instead of pass, because the main design
owns the decision. This consumer does NOT claim the draw amount means the task
is done, and it does NOT copy any product algorithm or alternative
activity/motion model.
"""
import ast, hashlib, json, math, sys
from pathlib import Path

# 13 samples in the exact order emitted by ProgressQuantityPreview.swift.
SAMPLES = ["zero", "percent", "complete-value", "count", "large-count",
           "huge-count", "indeterminate", "unknown", "paused", "ended",
           "stale", "long", "three"]
# parent appearance name -> canvasDark expectation.
APPEARANCES = {"light": True, "dark": True}

# Exact real quantity strings (String(describing:) of NotchActivity.Quantity).
QUANTITY = {
    "zero": "fraction(0.0)",
    "percent": "fraction(0.42)",
    "complete-value": "fraction(1.0)",
    "count": "count(2, 9)",
    "large-count": "count(999, 1000)",
    "huge-count": "count(999999, 1000000)",
    "indeterminate": "indeterminate",
    "unknown": "unknown",
    "paused": "fraction(0.42)",
    "ended": "fraction(1.0)",
    "stale": "fraction(0.42)",
    "long": "fraction(0.42)",
    "three": None,  # per-tile: fraction(0.42) | count(2, 9) | indeterminate
}
THREE_QUANTITIES = ["fraction(0.42)", "count(2, 9)", "indeterminate"]

# Samples that are .count(...) with a parseable (completed, total) pair.
COUNT_PAIRS = {"count": (2, 9), "large-count": (999, 1000),
               "huge-count": (999999, 1000000)}
# Samples whose quantity is indeterminate / unknown.
NON_NUMERIC = {"indeterminate", "unknown"}

# Real, distinct per-sample flags emitted by the entry.
PAUSED = {"paused"}
ENDED = {"ended"}            # item.endedAt = 1 -> isEnded true
STALE = {"stale"}
COMPLETE = {"complete-value"}  # fraction(1) value ends the quantity, not the row

TILES = "tiles"
WINDOWS = 0
ACTIONS = 0
SOURCE_CONTROLLERS = 0
SOURCE_COUNT = 518
RING_DIAMETER = 0.0  # text gap reserved for the ring when a ring layer is shown


def finite(value, label):
    assert isinstance(value, (int, float)) and not isinstance(value, bool), \
        f"{label}: not a number: {value!r}"
    assert math.isfinite(value), f"{label}: not finite: {value!r}"
    return value


def finite_nonnegative(value, label):
    value = finite(value, label)
    assert value >= 0, f"{label}: negative: {value!r}"
    return value


def parse_count(qtext):
    """Parse 'count(completed, total)' -> (completed, total) or None."""
    if not isinstance(qtext, str) or not qtext.startswith("count(") or not qtext.endswith(")"):
        return None
    inner = qtext[len("count("):-1]
    parts = [p.strip() for p in inner.split(",")]
    if len(parts) != 2:
        return None
    try:
        return int(parts[0]), int(parts[1])
    except ValueError:
        return None


def has_ring(tile):
    """True when the optional progress part shows a ring (shape layer w/ stroke)."""
    for layer in tile.get("layerChildren") or []:
        if isinstance(layer, dict) and "strokeEnd" in layer:
            return True
    return False


def check_part(tile, label, expect_hidden=None, expect_indeterminate=None):
    """Validate the optional part model mirrors the tile quantity and geometry."""
    assert "partQuantity" in tile, f"{label}: missing actual progress part"
    assert tile.get("partHidden") in (True, False), f"{label}: partHidden must be bool"
    if expect_hidden is not None:
        assert tile["partHidden"] is expect_hidden, \
            f"{label}: partHidden expected {expect_hidden} got {tile['partHidden']!r}"
    assert tile["partQuantity"] == tile.get("quantity"), \
        f"{label}: part.model.quantity {tile['partQuantity']!r} != tile quantity {tile.get('quantity')!r}"
    assert isinstance(tile.get("layerChildren"), list), f"{label}: layerChildren must be a list"
    indeterminate_shown = any(
        isinstance(layer, dict) and layer.get("hidden") is False
        for layer in tile["layerChildren"])
    if expect_indeterminate is not None:
        assert indeterminate_shown is expect_indeterminate, \
            f"{label}: indeterminate layer shown expected {expect_indeterminate} got {indeterminate_shown}"
    return indeterminate_shown


def check_tile_common(tile, label, frame_w, frame_h):
    # finite + contained tile frame.
    assert isinstance(tile.get("frame"), dict), f"{label}: missing frame"
    fx, fy = finite(tile["frame"].get("x"), f"{label}.frame.x"), finite(tile["frame"].get("y"), f"{label}.frame.y")
    fw = finite_nonnegative(tile["frame"].get("width"), f"{label}.frame.width")
    fh = finite_nonnegative(tile["frame"].get("height"), f"{label}.frame.height")
    assert fx >= 0 and fy >= 0 and fx + fw <= frame_w and fy + fh <= frame_h, \
        f"{label}: tile frame {tile['frame']!r} not contained in {frame_w}x{frame_h}"

    # optional part root frame must also be finite and contained, and the
    # optional part must not touch real UI (no window/controller/action fields).
    if "partFrame" in tile:
        pf = tile["partFrame"]
        px, py = finite(pf.get("x"), f"{label}.partFrame.x"), finite(pf.get("y"), f"{label}.partFrame.y")
        pw = finite_nonnegative(pf.get("width"), f"{label}.partFrame.width")
        ph = finite_nonnegative(pf.get("height"), f"{label}.partFrame.height")
        assert tile.get("partHidden") is True or (px >= 0 and py >= 0 and px + pw <= fw and py + ph <= fh), \
            f"{label}: part root frame {pf!r} not contained in {frame_w}x{frame_h}"
        for forbidden in ("window", "controller", "action", "actions", "windowActions"):
            assert forbidden not in tile, f"{label}: optional part touched real UI via {forbidden!r}"

    # AX value must equal quantityText.
    assert tile.get("accessibilityValue") == tile.get("quantityText"), \
        f"{label}: accessibilityValue {tile.get('accessibilityValue')!r} != quantityText {tile.get('quantityText')!r}"
    # tooltip must include the full subtitle.
    subtitle = tile.get("subtitle")
    tooltip = tile.get("tooltip")
    assert isinstance(tooltip, str) and isinstance(subtitle, str), f"{label}: tooltip/subtitle must be strings"
    assert subtitle in tooltip, f"{label}: tooltip {tooltip!r} does not include full subtitle {subtitle!r}"
    return fw


def check_tile(tile, label, sample, index, frame_w, frame_h):
    # identity / core labels.
    assert isinstance(tile.get("id"), int) and not isinstance(tile["id"], bool), f"{label}: bad tile id"
    assert isinstance(tile.get("title"), str) and tile["title"], f"{label}: bad title"
    assert isinstance(tile.get("subtitle"), str), f"{label}: bad subtitle"
    assert tile.get("dark") is True, f"{label}: hardware host must stay dark"
    assert isinstance(tile.get("accessibility"), str) and tile["accessibility"], f"{label}: bad accessibility label"

    # exact real quantity.
    expected_q = THREE_QUANTITIES[index] if sample == "three" else QUANTITY[sample]
    assert tile.get("quantity") == expected_q, \
        f"{label}: quantity expected {expected_q!r} got {tile.get('quantity')!r}"

    # quantityText presence: indeterminate/unknown have no numeric text.
    qtext = tile.get("quantityText")
    if expected_q in NON_NUMERIC:
        assert qtext is None, f"{label}: quantityText should be null for {sample} got {qtext!r}"
    else:
        assert isinstance(qtext, str) and qtext, f"{label}: quantityText required for {sample}"

    # count parses to the exact real (completed, total) and stays consistent.
    if sample in COUNT_PAIRS:
        pair = parse_count(tile["quantity"])
        assert pair == COUNT_PAIRS[sample], f"{label}: count pair {pair!r} != {COUNT_PAIRS[sample]!r}"
        assert pair[0] <= pair[1], f"{label}: count pair ordering invalid: {pair!r}"
    elif sample == "three" and expected_q.startswith("count("):
        assert parse_count(expected_q) == (2, 9), f"{label}: three[1] count mismatch"

    # paused / ended / stale flags are exactly per sample.
    assert tile.get("paused") is (sample in PAUSED), f"{label}: paused flag mismatch"
    assert tile.get("ended") is (sample in ENDED), f"{label}: ended flag mismatch"
    assert tile.get("stale") is (sample in STALE), f"{label}: stale flag mismatch"

    # percent value 1 is NOT ended; ended comes from the separate ended flag.
    if sample in COMPLETE:
        assert tile.get("quantity") == "fraction(1.0)", f"{label}: complete-value must be fraction(1.0)"
        assert tile.get("ended") is False, f"{label}: fraction(1) value must not imply ended"
    # do NOT assert draw amount means task done; only the explicit ended flag says so.
    if sample == "ended":
        assert tile.get("ended") is True, f"{label}: ended flag must be true"

    fw = check_tile_common(tile, label, frame_w, frame_h)

    # part model must match the tile quantity exactly.
    expect_hidden = expected_q.startswith("count(") or expected_q == "unknown"
    expect_ind = True if expected_q == "indeterminate" else None
    check_part(tile, label, expect_hidden=expect_hidden, expect_indeterminate=expect_ind)

    layers = tile["layerChildren"]
    assert len(layers) == 3, f"{label}: expected actual track/fill/arc layers"
    if expected_q.startswith("fraction("):
        value = float(expected_q[len("fraction("):-1])
        assert layers[0]["hidden"] is False and layers[2]["hidden"] is True, f"{label}: wrong ring layers"
        assert layers[1]["hidden"] is (value == 0), f"{label}: zero must not leave round-cap dot"
        assert abs(layers[1]["strokeEnd"] - value) < 0.00001, f"{label}: actual fill end differs"
    elif expected_q == "indeterminate":
        assert [x["hidden"] for x in layers] == [True, True, False], f"{label}: wrong indeterminate layers"
    else:
        assert all(x["hidden"] for x in layers), f"{label}: count/unknown must not paint invented ring"

    # Natural width vs available tile width minus 20 (and ring diameter when shown).
    natural = finite_nonnegative(tile.get("naturalQuantityWidth"), f"{label}.naturalQuantityWidth")
    available = fw - 20.0 - (tile["partFrame"]["width"] + 4 if tile["drawing"] in ("ring", "spinningArc") else 0.0)
    rendered = tile.get("renderedQuantityText", qtext or "")
    width = finite_nonnegative(tile.get("renderedQuantityWidth", natural), f"{label}.renderedQuantityWidth")
    if "renderedQuantityText" in tile:
        expected = "999999/1000000" if sample == "huge-count" else (qtext or "")
        assert rendered == expected, f"{label}: rendered exact quantity {rendered!r} != {expected!r}"
        assert abs(tile["quantityAvailableWidth"] - available) < 0.01, f"{label}: available glyph width differs"
    return {
        "renderedText": rendered, "renderedWidth": width,
        "label": label,
        "quantity": tile.get("quantity"),
        "quantityText": qtext,
        "naturalWidth": natural,
        "availableWidth": available,
        "overflow": width > available,
    }


def main():
    assert len(sys.argv) == 2, "usage: check-progress-quantity-preview.py ABS_OUTPUT"
    out = Path(sys.argv[1]).resolve()
    root = Path(__file__).resolve().parents[2]

    frames_path = out / "frames.json"
    sources_path = out / "sources.json"
    renderer_path = out / "renderer.json"
    for required in (frames_path, sources_path, renderer_path):
        assert required.is_file(), f"missing required output: {required.name}"

    report = json.loads(frames_path.read_text())
    frames = report.get("frames")
    assert isinstance(frames, list), "frames must be a list"

    # --- report-level schema / identity ------------------------------------
    assert report.get("sourceControllers") == SOURCE_CONTROLLERS, \
        f"sourceControllers must be {SOURCE_CONTROLLERS} got {report.get('sourceControllers')!r}"
    assert report.get("actions") == ACTIONS, \
        f"actions must be {ACTIONS} got {report.get('actions')!r}"

    # --- 26 frames: aqua/dark x 13 samples ---------------------------------
    assert len(frames) == 26, f"expected 26 frames got {len(frames)}"
    by_appearance = {}
    for frame in frames:
        name = frame.get("name")
        assert isinstance(name, str) and "-" in name, f"bad frame name: {name!r}"
        appearance, sample = name.split("-", 1)
        assert appearance in APPEARANCES, f"unexpected appearance in frame name: {name!r}"
        assert frame.get("sample") == sample, f"{name}: sample field mismatch"
        assert sample in SAMPLES, f"{name}: unexpected sample {sample!r}"
        assert frame.get("windows") == WINDOWS, f"{name}: windows must be {WINDOWS} got {frame.get('windows')!r}"
        assert frame.get("completions") == 1, f"{name}: completions must be 1 got {frame.get('completions')!r}"
        assert frame.get("canvasDark") is APPEARANCES[appearance], \
            f"{name}: canvasDark mismatch"
        # hidden window alpha0 activefalse.
        assert frame.get("alpha") == 0, f"{name}: alpha must be 0 got {frame.get('alpha')!r}"
        assert frame.get("visible") is False, f"{name}: visible must be false"
        assert frame.get("active") is False, f"{name}: active must be false"
        by_appearance.setdefault(appearance, []).append(frame)

    for appearance in APPEARANCES:
        names = [f["sample"] for f in by_appearance.get(appearance, [])]
        assert names == SAMPLES, f"{appearance}: sample order/sequence mismatch: {names}"

    # --- per-frame checks ---------------------------------------------------
    observed = []
    issues = []
    for appearance in APPEARANCES:
        for frame in by_appearance[appearance]:
            sample = frame["sample"]
            label = frame["name"]
            width = finite_nonnegative(frame.get("width"), f"{label}.width")
            height = finite_nonnegative(frame.get("height"), f"{label}.height")
            tiles = frame.get(TILES)
            assert isinstance(tiles, list), f"{label}: tiles must be a list"

            expected_tiles = 3 if sample == "three" else 1
            assert len(tiles) == expected_tiles, \
                f"{label}: expected {expected_tiles} tiles got {len(tiles)}"

            for index, tile in enumerate(tiles):
                tl = f"{label}[{index}]"
                obs = check_tile(tile, tl, sample, index, width, height)
                observed.append((appearance, obs))
                if obs["overflow"]:
                    issues.append(
                        f"{label}[{index}]: naturalQuantityWidth {obs['naturalWidth']:.2f} "
                        f"exceeds available {obs['availableWidth']:.2f}")

    # --- identical corresponding actual quantity/geometry/core labels ------
    light = {f["sample"]: f for f in by_appearance["light"]}
    dark = {f["sample"]: f for f in by_appearance["dark"]}
    for sample in SAMPLES:
        lt, dt = light[sample]["tiles"], dark[sample]["tiles"]
        assert len(lt) == len(dt), f"{sample}: tile count differs across appearances"
        for index, (a, b) in enumerate(zip(lt, dt)):
            for key in ("id", "title", "kind", "subtitle", "quantity", "quantityText",
                        "stale", "ended", "shelf", "drawing", "paused",
                        "accessibility", "accessibilityValue", "tooltip",
                        "naturalQuantityWidth", "partHidden", "partQuantity",
                        "layerChildren", "renderedQuantityText", "renderedQuantityWidth", "quantityAvailableWidth"):
                if key in a or key in b:
                    assert a.get(key) == b.get(key), \
                        f"{sample}[{index}]: {key} differs across appearances: {a.get(key)!r} != {b.get(key)!r}"
            assert a.get("frame") == b.get("frame"), \
                f"{sample}[{index}]: tile geometry differs across appearances"

    # --- renderer.json ------------------------------------------------------
    renderer = json.loads(renderer_path.read_text())
    assert renderer.get("swiftLanguageVersion") == 6, "renderer swiftLanguageVersion must be 6"
    assert renderer.get("strictConcurrency") is True, "renderer strictConcurrency must be true"
    assert renderer.get("warningsAsErrors") is True, "renderer warningsAsErrors must be true"
    assert renderer.get("optimized") is False, "renderer optimized must be false"

    # --- sources.json: exactly 518 entries, SHA256 matches current disk ----
    sources = json.loads(sources_path.read_text())
    assert isinstance(sources, dict) and len(sources) == SOURCE_COUNT, \
        f"sources.json must contain {SOURCE_COUNT} entries got {len(sources)}"
    for name, digest in sources.items():
        local = root / name
        assert local.is_file(), f"missing local source: {name}"
        actual = hashlib.sha256(local.read_bytes()).hexdigest()
        assert actual == digest, f"source drift for {name}: {actual} != {digest}"

    # --- report per-state observations; overflow is an issue, not a pass ----
    for appearance, obs in observed:
        print(json.dumps({
            "frame": obs["label"],
            "observation": ("renderedWidth_exceeds_available" if obs["overflow"]
                            else "renderedWidth_within_available"),
            "renderedText": obs["renderedText"], "renderedWidth": obs["renderedWidth"],
            "naturalWidth": obs["naturalWidth"],
            "availableWidth": obs["availableWidth"],
            "quantity": obs["quantity"],
            "quantityText": obs["quantityText"],
            "cache_static_only": "schema_checked_visual_by_main",
            "hardware": "not_run",
            "compositor": "not_run",
        }, sort_keys=True))

    status = "design_review_required" if issues else "pass_static_schema_visual_inconclusive"
    print(json.dumps({
        "status": status,
        "frames": len(frames),
        "tiles_observed": len(observed),
        "sources_sha256": len(sources),
        "schema_identity_containment": "checked",
        "renderedWidth_overflow_issues": issues,
        "quantity_meaning_draw_amount": "not_asserted",
        "cache_static_only": "schema_checked_visual_by_main",
        "hardware": "not_run",
        "compositor": "not_run",
        "renderedWidth_overflow_is_issue": True,
        "main_decision": "rendered glyph overflow is reported for design review, not failed here",
    }, sort_keys=True))


# Prove this file parses as valid Python before trusting it as a consumer.
# This check does not exercise the code paths above.
ast.parse(Path(__file__).read_text())
main()
