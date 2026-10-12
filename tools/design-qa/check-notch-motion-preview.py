#!/usr/bin/env python3
"""Consumer for render-native-surfaces.sh --swift6 output of NotchMotionPreview.swift.

Reads ONLY ABS_OUTPUT/frames.json, sources.json, renderer.json plus the local
sources named by sources.json (for SHA256). It never touches UI, product code,
the network, permissions or any other source.

What this proves: control-path structure in emitted JSON (stage ordering, model
geometry/tile identity/quantity bookkeeping, callback counts, main-thread flags)
plus the fact that frames.json/sources.json/renderer.json are internally
consistent with current on-disk sources. What it cannot prove: that any animation
actually ran, that the visual compositor produced motion, or anything about real
hardware, presentation timing or product lifecycle. `presentation` and `cacheOnly`
are recorded data, not evidence of real motion. File existence and a clean
ast.parse of this script are NOT behavioural evidence.
"""
import ast, hashlib, json, math, sys
from pathlib import Path

STAGES = ["initial", "open-start", "open-settled", "same-id", "replace-id",
          "close-before-interrupt", "reopened", "closed"]
TRANSITION_STAGES = {"open-start", "close-before-interrupt"}
# stage -> exact per-mode callback completion key that must occur
EXPECT_ONE = {"initial", "open", "same-id", "replace-id", "reopen", "close-final"}
# stage -> callback key that must NOT fire in regular mode
EXPECT_ZERO_REGULAR_ONLY = {"close-interrupted"}

MODES = {"regular": False, "reduced": True}
COMPACT = (185, 33.5)
EXPANDED_W = 305
EXPANDED_H = 175.5
CENTER_X = 400
TOP_Y = 400


def finite_nonnegative(value, label):
    assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{label}: not a number: {value!r}"
    assert math.isfinite(value), f"{label}: not finite: {value!r}"
    assert value >= 0, f"{label}: negative: {value!r}"
    return value


def finite(value, label):
    assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{label}: not a number: {value!r}"
    assert math.isfinite(value), f"{label}: not finite: {value!r}"
    return value


def check_frame_common(frame, mode, stage):
    label = f"{mode}-{stage}"
    for key, expected in (("active", False), ("visible", False), ("mainThread", True), ("cacheOnly", True)):
        assert frame.get(key) is expected, f"{label}: {key} expected {expected!r} got {frame.get(key)!r}"
    assert frame.get("alpha") == 0, f"{label}: alpha expected 0 got {frame.get('alpha')!r}"
    assert frame.get("model") is not None and isinstance(frame["model"], dict), f"{label}: missing model box"
    for dim in ("x", "y", "width", "height"):
        assert dim in frame["model"], f"{label}: model missing {dim}"
        finite(frame["model"][dim], f"{label}.model.{dim}")
    assert "presentation" in frame, f"{label}: missing presentation field"
    assert isinstance(frame.get("animations"), list), f"{label}: animations must be a list"
    for anim in frame["animations"]:
        assert set(("key", "duration", "class")) <= set(anim), f"{label}: animation missing keys: {anim!r}"
        assert isinstance(anim["key"], str) and anim["class"], f"{label}: bad animation id: {anim!r}"
        finite_nonnegative(anim["duration"], f"{label}.animations[{anim['key']}].duration")
    assert isinstance(frame.get("pendingExit"), bool), f"{label}: pendingExit must be bool"
    for key, kind in (("tileIDs", list), ("tileIdentities", list), ("tileQuantities", list)):
        assert isinstance(frame.get(key), kind), f"{label}: {key} must be a list"
    assert len(frame["tileIDs"]) == len(frame["tileIdentities"]) == len(frame["tileQuantities"]), \
        f"{label}: tile arrays length mismatch"
    for tid in frame["tileIDs"]:
        assert isinstance(tid, int) and not isinstance(tid, bool), f"{label}: tile id not an int: {tid!r}"
    for ident in frame["tileIdentities"]:
        assert isinstance(ident, str) and ident, f"{label}: tile identity not a string: {ident!r}"
    for q in frame["tileQuantities"]:
        assert set(q) == {"completed", "total"}, f"{label}: tile quantity shape: {q!r}"
        finite_nonnegative(q["completed"], f"{label}.quantity.completed")
        finite_nonnegative(q["total"], f"{label}.quantity.total")
    assert "currentIdentity" in frame, f"{label}: missing currentIdentity"


def check_model_rect(frame, mode, stage, width, height):
    label = f"{mode}-{stage}"
    model = frame["model"]
    assert model["width"] == width, f"{label}: model width expected {width} got {model['width']}"
    assert model["height"] == height, f"{label}: model height expected {height} got {model['height']}"
    cx = model["x"] + model["width"] / 2
    assert cx == CENTER_X, f"{label}: model centre x expected {CENTER_X} got {cx}"
    assert model["y"] + model["height"] == TOP_Y, f"{label}: model top edge expected {TOP_Y} got {model['y'] + model['height']}"


def main():
    assert len(sys.argv) == 2, "usage: check-notch-motion-preview.py ABS_OUTPUT"
    out = Path(sys.argv[1]).resolve()
    root = Path(__file__).resolve().parents[2]

    frames_path = out / "frames.json"
    sources_path = out / "sources.json"
    renderer_path = out / "renderer.json"
    for required in (frames_path, sources_path, renderer_path):
        assert required.is_file(), f"missing required output: {required.name}"

    report = json.loads(frames_path.read_text())
    frames = report.get("frames")
    callbacks = report.get("callbacks")
    counts = report.get("counts")
    assert isinstance(frames, list), "frames must be a list"
    assert isinstance(callbacks, list), "callbacks must be a list"
    assert isinstance(counts, dict), "counts must be a dict"

    # --- report-level schema -------------------------------------------------
    assert report.get("swiftLanguageVersion") == 6, "swiftLanguageVersion must be 6"
    assert report.get("productEntry") is False, "productEntry must be false"
    for key in ("realSources", "globalInputEvents", "windowActions"):
        assert report.get(key) == 0, f"{key} must be 0 got {report.get(key)!r}"
    assert report.get("mainThread") is True, "report mainThread must be true"
    assert report.get("status") == "completed_callbacks_static_cache_only", \
        f"status must be completed_callbacks_static_cache_only got {report.get('status')!r}"

    assert report.get("overrideRestored") is True, "process-local reduced override not restored"

    # --- frames: 16 total, 8 per mode, one per stage, ordered ---------------
    assert len(frames) == 16, f"expected 16 frames got {len(frames)}"
    by_mode = {}
    for frame in frames:
        name = frame.get("name")
        assert isinstance(name, str) and "-" in name, f"bad frame name: {name!r}"
        mode, stage = name.split("-", 1)
        assert mode in MODES, f"unexpected mode in frame name: {name!r}"
        assert frame.get("stage") == stage, f"{name}: stage field mismatch"
        assert frame.get("reduced") is MODES[mode], f"{name}: reduced flag mismatch"
        by_mode.setdefault(mode, []).append(frame)
    for mode in MODES:
        mode_frames = by_mode.get(mode, [])
        assert len(mode_frames) == 8, f"{mode}: expected 8 frames got {len(mode_frames)}"
        assert [f["stage"] for f in mode_frames] == STAGES, \
            f"{mode}: stage order/sequence mismatch: {[f['stage'] for f in mode_frames]}"

    # --- per-frame checks ----------------------------------------------------
    for mode in MODES:
        for frame in by_mode[mode]:
            stage = frame["stage"]
            check_frame_common(frame, mode, stage)
            if stage in ("initial", "closed") or (mode == "reduced" and stage == "close-before-interrupt"):
                check_model_rect(frame, mode, stage, *COMPACT)
            else:
                check_model_rect(frame, mode, stage, EXPANDED_W, EXPANDED_H)

        # tile identity / quantity expectations
        exp = {
            "initial": (set(), []),
            "open-start": (None, None),   # transition: presentation/tiles not asserted
            "open-settled": ({900}, [{"completed": 2, "total": 9}]),
            "same-id": ({900}, [{"completed": 3, "total": 9}]),
            "replace-id": ({901}, [{"completed": 4, "total": 9}]),
            "reopened": ({901}, [{"completed": 4, "total": 9}]),
            "closed": (set(), []),
        }
        for frame in by_mode[mode]:
            stage = frame["stage"]
            if stage in ("open-start", "close-before-interrupt"):
                # transition stages: do not assert tile visibility or presentation
                assert "presentation" in frame, f"{mode}-{stage}: presentation field must exist"
                continue
            expected_ids, expected_q = exp[stage]
            assert set(frame["tileIDs"]) == expected_ids, \
                f"{mode}-{stage}: tile ids expected {sorted(expected_ids)} got {sorted(frame['tileIDs'])}"
            assert frame["tileQuantities"] == expected_q, \
                f"{mode}-{stage}: quantities expected {expected_q} got {frame['tileQuantities']}"
            if expected_ids:
                assert frame["currentIdentity"] not in (None,), f"{mode}-{stage}: currentIdentity null with tiles present"

        # same-id: the retained tile must reuse the same TileIdentity object
        same = next(f for f in by_mode[mode] if f["stage"] == "same-id")
        opened = next(f for f in by_mode[mode] if f["stage"] == "open-settled")
        assert len(same["tileIdentities"]) == 1 and len(opened["tileIdentities"]) == 1, \
            f"{mode}: expected exactly one tile identity for same-id comparison"
        assert same["tileIdentities"][0] == opened["tileIdentities"][0], \
            f"{mode}-same-id: TileIdentity changed across same-id update"
        assert same["currentIdentity"] == opened["currentIdentity"], \
            f"{mode}-same-id: currentIdentity changed across same-id update"

        # replace-id / reopened: identity content must switch to 901
        repl = next(f for f in by_mode[mode] if f["stage"] == "replace-id")
        reop = next(f for f in by_mode[mode] if f["stage"] == "reopened")
        assert repl["tileIDs"] == [901] and reop["tileIDs"] == [901], f"{mode}: replace/reopen must show id 901"

        # close-before-interrupt must reflect the interruption contract exactly
        before = next(f for f in by_mode[mode] if f["stage"] == "close-before-interrupt")
        if mode == "regular":
            check_model_rect(before, mode, "close-before-interrupt", EXPANDED_W, EXPANDED_H)
            assert before["pendingExit"] is True, "regular close-before-interrupt: pendingExit must stay true"
        else:
            check_model_rect(before, mode, "close-before-interrupt", *COMPACT)
            assert before["pendingExit"] is False, "reduced close-before-interrupt: pendingExit must be false"

        # final stage must have no pending exit
        closed = next(f for f in by_mode[mode] if f["stage"] == "closed")
        assert closed["pendingExit"] is False, f"{mode}-closed: pendingExit must be false"

    # --- counts: exact completions ------------------------------------------
    for mode in MODES:
        for key in EXPECT_ONE:
            k = f"{mode}-{key}"
            assert k in counts, f"missing callback count: {k}"
            assert counts[k] == 1, f"{k}: completion count expected 1 got {counts.get(k)!r}"
        for key in EXPECT_ZERO_REGULAR_ONLY:
            k = f"{mode}-{key}"
            if mode == "regular":
                assert counts.get(k, 0) == 0, f"{k}: regular interrupted close must not complete (got {counts.get(k)!r})"
            else:
                assert counts.get(k, 0) in (0, 1), f"{k}: reduced must be 0 or 1 (got {counts.get(k)!r})"
        # no count may exceed one
        for k, v in counts.items():
            if k.startswith(mode + "-"):
                assert v <= 1, f"count for {k} exceeds 1: {v!r}"

    # --- callbacks: all main-thread, consistent with counts -----------------
    callback_tally = {}
    for cb in callbacks:
        assert set(("name", "mainThread", "time")) <= set(cb), f"callback missing keys: {cb!r}"
        assert cb["mainThread"] is True, f"callback {cb['name']} not on main thread"
        finite_nonnegative(cb["time"], f"callback {cb['name']}.time")
        callback_tally[cb["name"]] = callback_tally.get(cb["name"], 0) + 1
    assert callback_tally == counts, f"callbacks tally {callback_tally} != counts {counts}"

    # --- renderer.json -------------------------------------------------------
    renderer = json.loads(renderer_path.read_text())
    assert renderer.get("swiftLanguageVersion") == 6, "renderer swiftLanguageVersion must be 6"
    assert renderer.get("strictConcurrency") is True, "renderer strictConcurrency must be true"
    assert renderer.get("warningsAsErrors") is True, "renderer warningsAsErrors must be true"
    assert renderer.get("optimized") is False, "renderer optimized must be false"

    # --- sources.json: 518 entries, each SHA256 matches current source ------
    sources = json.loads(sources_path.read_text())
    assert isinstance(sources, dict) and len(sources) == 518, \
        f"sources.json must contain 518 entries got {len(sources)}"
    for name, digest in sources.items():
        local = root / name
        assert local.is_file(), f"missing local source: {name}"
        actual = hashlib.sha256(local.read_bytes()).hexdigest()
        assert actual == digest, f"source drift for {name}: {actual} != {digest}"

    print(json.dumps({
        "status": "pass_control_path_visual_inconclusive",
        "frames": len(frames),
        "callbacks": len(callbacks),
        "sources_sha256": len(sources),
        "geometry_state_control_path": "checked",
        "presentation_real_motion": "inconclusive",
        "cache_only_real_motion": "inconclusive",
        "visual_compositor": "untested",
        "hardware": "untested",
        "product_lifecycle": "untested",
    }))


# Prove this file parses as valid Python before trusting it as a consumer.
# This check does not exercise the code paths above.
ast.parse(Path(__file__).read_text())
main()
