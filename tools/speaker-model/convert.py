#!/usr/bin/env python3
"""WeSpeaker ResNet34 (VoxCeleb) -> Core ML, plus fbank reference fixtures and a parity/latency check.

Run with the venv that has torch/coremltools (see README.md):
  /Users/aaron/Documents/WindowShade-models/venv/bin/python tools/speaker-model/convert.py

Nothing here records or reads real people's audio: every waveform is synthetic (formula below, which the
Swift test re-implements bit for bit) so the fixtures contain no voice data.
"""
import argparse, hashlib, json, math, os, sys, time

import numpy as np
import torch
import torchaudio.compliance.kaldi as kaldi
import yaml

MODELS = os.environ.get("WS_MODELS_DIR", "/Users/aaron/Documents/WindowShade-models/speaker")
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FRAMES = 300          # fixed Core ML window: 25 ms + 299 * 10 ms = 3.015 s of 16 kHz audio
FEAT = 80
EMBED = 256
SAMPLE_RATE = 16000


def synth(kind: int, n: int) -> np.ndarray:
    """Deterministic synthetic int16-range waveform; the Swift test uses the same formula.
    kind selects the tones; noise is a 32-bit LCG so there is no library RNG dependency."""
    f0, f1, am = [(220.0, 1130.0, 3.0), (140.0, 2400.0, 5.0), (330.0, 700.0, 2.0)][kind % 3]
    state = np.uint32(12345 + kind)
    out = np.zeros(n, dtype=np.int16)
    s = int(state)
    for i in range(n):
        s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
        noise = (((s >> 16) & 0x7FFF) - 16384) * 0.25
        t = i / SAMPLE_RATE
        v = 6000.0 * math.sin(2 * math.pi * f0 * t) \
            + 3000.0 * math.sin(2 * math.pi * f1 * t + math.sin(2 * math.pi * am * t)) + noise
        out[i] = int(math.floor(v + 0.5))
    return out


def fbank(pcm_int16: np.ndarray) -> torch.Tensor:
    """WeSpeaker inference front end: Kaldi fbank 80, 25/10 ms, hamming, no dither, int16 scale, then CMN."""
    wav = torch.from_numpy(pcm_int16.astype(np.float32)).unsqueeze(0)
    feat = kaldi.fbank(wav, num_mel_bins=FEAT, frame_length=25, frame_shift=10, dither=0.0,
                       sample_frequency=SAMPLE_RATE, window_type="hamming", use_energy=False)
    return feat


def window300(feat_cmn: torch.Tensor) -> torch.Tensor:
    """Pad/crop the CMN'd features to the fixed Core ML window: tile if short, centre-crop if long."""
    t = feat_cmn.shape[0]
    if t < FRAMES:
        reps = -(-FRAMES // t)
        feat_cmn = feat_cmn.repeat(reps, 1)[:FRAMES]
    else:
        start = (t - FRAMES) // 2
        feat_cmn = feat_cmn[start:start + FRAMES]
    return feat_cmn


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def cos(a, b):
    a = np.asarray(a, dtype=np.float64).ravel(); b = np.asarray(b, dtype=np.float64).ravel()
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MODELS, "SpeakerEmbedding.mlpackage"))
    ap.add_argument("--fixtures", default=os.path.join(REPO, "tests", "fixtures", "speaker-fbank-reference.json"))
    args = ap.parse_args()

    # wespeaker/__init__.py drags in the CLI (silero_vad, ...). We only need the model code, so register
    # the package without running its __init__.
    import types
    src = os.path.join(MODELS, "wespeaker-src")
    pkg = types.ModuleType("wespeaker"); pkg.__path__ = [os.path.join(src, "wespeaker")]
    sys.modules["wespeaker"] = pkg
    sys.path.insert(0, src)
    import wespeaker.models.resnet as resnet_module  # speaker_model.py imports every architecture (and s3prl etc.)

    cfg = yaml.safe_load(open(os.path.join(MODELS, "config.yaml")))
    model = getattr(resnet_module, cfg["model"])(**cfg["model_args"])
    state = torch.load(os.path.join(MODELS, "avg_model.pt"), map_location="cpu", weights_only=True)
    state = {k: v for k, v in state.items() if not k.startswith("projection.")}
    missing = model.load_state_dict(state, strict=True)
    model.eval()

    def torch_embed(window):  # window: (300, 80)
        with torch.no_grad():
            out = model(window.unsqueeze(0))
            out = out[-1] if isinstance(out, tuple) else out
        return out[0].numpy()

    # ---- Core ML conversion (fixed 300-frame window, FP16) ----
    import coremltools as ct

    class Wrapper(torch.nn.Module):
        def __init__(self, m):
            super().__init__(); self.m = m
        def forward(self, x):
            out = self.m(x)
            out = out[-1] if isinstance(out, tuple) else out
            return out

    wrapped = Wrapper(model).eval()
    example = torch.randn(1, FRAMES, FEAT)
    traced = torch.jit.trace(wrapped, example)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="fbank", shape=(1, FRAMES, FEAT), dtype=np.float32)],
        outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS15,
        compute_units=ct.ComputeUnit.ALL,
    )
    mlmodel.short_description = "WeSpeaker ResNet34 (VoxCeleb) speaker embedding, 300 fbank frames -> 256-d"
    mlmodel.author = "Wespeaker (Apache-2.0); weights trained on VoxCeleb2 (CC BY 4.0 annotations)"
    mlmodel.license = "Code Apache-2.0; weights follow VoxCeleb (CC BY 4.0). See tools/speaker-model/README.md"
    if os.path.exists(args.out):
        import shutil; shutil.rmtree(args.out)
    mlmodel.save(args.out)

    # ---- parity ----
    report = {"onnx_sha256": sha256(os.path.join(MODELS, "voxceleb_resnet34.onnx")),
              "avg_model_sha256": sha256(os.path.join(MODELS, "avg_model.pt")), "parity": [], "latency": {}}
    reload = ct.models.MLModel(args.out, compute_units=ct.ComputeUnit.CPU_AND_NE)
    embeds = []
    for kind in range(3):
        pcm = synth(kind, SAMPLE_RATE * 3 + 240)  # 3.015 s -> exactly 300 frames
        feat = fbank(pcm); feat = feat - feat.mean(dim=0)
        w = window300(feat)
        e_t = torch_embed(w)
        e_c = reload.predict({"fbank": w.numpy()[None]})["embedding"][0]
        report["parity"].append({"kind": kind, "frames": int(feat.shape[0]), "cosine_torch_vs_coreml": cos(e_t, e_c)})
        embeds.append(e_c)
    # random normal features too (not just tones)
    g = torch.Generator().manual_seed(7)
    for i in range(3):
        w = torch.randn(FRAMES, FEAT, generator=g) * 2.0
        e_t = torch_embed(w); e_c = reload.predict({"fbank": w.numpy()[None]})["embedding"][0]
        report["parity"].append({"kind": f"randn{i}", "cosine_torch_vs_coreml": cos(e_t, e_c)})
    report["parity_min"] = min(p["cosine_torch_vs_coreml"] for p in report["parity"])

    # ---- latency (CPU+ANE, one 3 s window) ----
    w = window300(fbank(synth(0, SAMPLE_RATE * 3 + 240)) - fbank(synth(0, SAMPLE_RATE * 3 + 240)).mean(dim=0)).numpy()[None]
    for name, units in [("cpu_and_ne", ct.ComputeUnit.CPU_AND_NE), ("all", ct.ComputeUnit.ALL), ("cpu_only", ct.ComputeUnit.CPU_ONLY)]:
        m = ct.models.MLModel(args.out, compute_units=units)
        for _ in range(3): m.predict({"fbank": w})
        ts = []
        for _ in range(30):
            t0 = time.perf_counter(); m.predict({"fbank": w}); ts.append((time.perf_counter() - t0) * 1000)
        ts.sort()
        report["latency"][name] = {"median_ms": round(ts[len(ts) // 2], 2), "p90_ms": round(ts[int(len(ts) * 0.9)], 2)}

    # ---- fixtures for the Swift tests (synthetic only) ----
    n_short = 9600  # 0.6 s -> 58 frames
    pcm = synth(0, n_short)
    ff = fbank(pcm)
    pcm3 = synth(1, SAMPLE_RATE * 3 + 240)
    f3 = fbank(pcm3); f3c = f3 - f3.mean(dim=0)
    e3_t = torch_embed(window300(f3c))
    e3_c = reload.predict({"fbank": window300(f3c).numpy()[None]})["embedding"][0]
    fixtures = {
        "note": "Synthetic waveforms only (no real voices). Regenerate with tools/speaker-model/convert.py.",
        "synthFormula": "x[i]=floor(6000*sin(2pi*f0*t)+3000*sin(2pi*f1*t+sin(2pi*am*t))+noise+0.5), t=i/16000, "
                        "noise=(((s>>16)&0x7FFF)-16384)*0.25, s=(s*1664525+1013904223) mod 2^32 starting at 12345+kind; "
                        "(f0,f1,am) by kind%3: (220,1130,3),(140,2400,5),(330,700,2)",
        "fbank": {"kind": 0, "samples": n_short, "frames": int(ff.shape[0]), "bins": FEAT,
                  "values": [[round(float(v), 4) for v in row] for row in ff]},
        "embedding": {"kind": 1, "samples": SAMPLE_RATE * 3 + 240, "frames": int(f3.shape[0]),
                      "torch": [round(float(v), 5) for v in e3_t], "coreml": [round(float(v), 5) for v in e3_c]},
    }
    os.makedirs(os.path.dirname(args.fixtures), exist_ok=True)
    json.dump(fixtures, open(args.fixtures, "w"), separators=(",", ":"))
    report["mlpackage"] = args.out
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
