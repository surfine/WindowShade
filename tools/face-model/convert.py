#!/usr/bin/env python3
"""AdaFace IR-101 (WebFace12M) -> Core ML, plus a parity and latency check.

Run with the venv that has torch/coremltools (see README.md):
  /Users/aaron/Documents/WindowShade-models/venv/bin/python -I tools/face-model/convert.py

The network below is a re-statement of the IR-101 backbone in the author's `models/iresnet/model.py`
(BasicBlockIR, 3/13/30/3 units, 112x112). It is written out here so that no downloaded Python is executed:
only `model.safetensors` (plain tensors) is read, with a hand-written parser, and loaded with strict key
matching. No image of a real person is read or written: parity inputs are synthetic.
"""
import argparse, hashlib, json, os, struct, sys, time

import numpy as np
import torch
import torch.nn as nn

MODELS = os.environ.get("WS_FACE_MODEL_DIR", "/Users/aaron/Documents/WindowShade-models/face")
SOURCE = os.path.join(MODELS, "adaface_ir101_webface12m", "download", "model.safetensors")
SOURCE_SHA256 = "2ea535a43877bd3de8091903935c783ce335be66a9f8917fae9a7a18ae4bbf56"
SOURCE_BYTES = 260_980_552
SIDE = 112
EMBED = 512
PREFIX = "model.net."


class BasicBlockIR(nn.Module):
    def __init__(self, in_channel, depth, stride):
        super().__init__()
        if in_channel == depth:
            self.shortcut_layer = nn.MaxPool2d(1, stride)
        else:
            self.shortcut_layer = nn.Sequential(
                nn.Conv2d(in_channel, depth, (1, 1), stride, bias=False), nn.BatchNorm2d(depth))
        self.res_layer = nn.Sequential(
            nn.BatchNorm2d(in_channel),
            nn.Conv2d(in_channel, depth, (3, 3), (1, 1), 1, bias=False),
            nn.BatchNorm2d(depth),
            nn.PReLU(depth),
            nn.Conv2d(depth, depth, (3, 3), stride, 1, bias=False),
            nn.BatchNorm2d(depth))

    def forward(self, x):
        return self.res_layer(x) + self.shortcut_layer(x)


class IR101(nn.Module):
    UNITS = [(64, 64, 3), (64, 128, 13), (128, 256, 30), (256, 512, 3)]

    def __init__(self):
        super().__init__()
        self.input_layer = nn.Sequential(nn.Conv2d(3, 64, (3, 3), 1, 1, bias=False), nn.BatchNorm2d(64), nn.PReLU(64))
        blocks = []
        for in_channel, depth, units in self.UNITS:
            blocks.append(BasicBlockIR(in_channel, depth, 2))
            blocks += [BasicBlockIR(depth, depth, 1) for _ in range(units - 1)]
        self.body = nn.Sequential(*blocks)
        self.output_layer = nn.Sequential(
            nn.BatchNorm2d(512), nn.Dropout(0.4), nn.Flatten(),
            nn.Linear(512 * 7 * 7, EMBED), nn.BatchNorm1d(EMBED, affine=False))

    def forward(self, x):
        return self.output_layer(self.body(self.input_layer(x)))


class Wrapped(nn.Module):
    """Input: RGB, 0...255, [1, 3, 112, 112]. Output: L2-normalised [1, 512]."""

    def __init__(self, net):
        super().__init__()
        self.net = net

    def forward(self, face):
        x = face / 127.5 - 1.0            # = ToTensor() then Normalize(0.5, 0.5)
        e = self.net(x)
        return e / torch.sqrt((e * e).sum(dim=1, keepdim=True) + 1e-12)


def read_safetensors(path):
    """Minimal safetensors reader: 8-byte little-endian header length, JSON header, raw little-endian data."""
    dtypes = {"F32": np.float32, "I64": np.int64}
    out = {}
    with open(path, "rb") as f:
        (n,) = struct.unpack("<Q", f.read(8))
        header = json.loads(f.read(n))
        base = 8 + n
        for name, info in header.items():
            if name == "__metadata__":
                continue
            start, end = info["data_offsets"]
            f.seek(base + start)
            raw = f.read(end - start)
            arr = np.frombuffer(raw, dtype=dtypes[info["dtype"]]).reshape(info["shape"])
            out[name] = torch.from_numpy(arr.copy())
    return out


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def tree_bytes(path):
    return sum(os.path.getsize(os.path.join(d, n)) for d, _, names in os.walk(path) for n in names)


def synthetic(kind, seed):
    """Deterministic test inputs, RGB 0...255, [1, 3, 112, 112]. kind 0: uniform noise; 1: smooth blobs
    (a crude skin-toned oval on a background, so activations are in a face-like range); 2: gradients."""
    rng = np.random.default_rng(seed)
    if kind == 0:
        img = rng.uniform(0, 255, (3, SIDE, SIDE))
    elif kind == 1:
        yy, xx = np.mgrid[0:SIDE, 0:SIDE].astype(np.float64)
        cx, cy = 56 + rng.uniform(-6, 6), 58 + rng.uniform(-6, 6)
        oval = np.exp(-(((xx - cx) / 30) ** 2 + ((yy - cy) / 40) ** 2) * 1.5)
        tone = np.array([200, 160, 135]) + rng.uniform(-30, 30, 3)
        back = rng.uniform(20, 120, 3)
        img = back[:, None, None] * (1 - oval) + tone[:, None, None] * oval
        for ex in (-14, 14):                                   # two dark spots where eyes would be
            img *= 1 - 0.6 * np.exp(-(((xx - cx - ex) / 5) ** 2 + ((yy - cy + 10) / 3) ** 2))
        img += rng.normal(0, 4, img.shape)
    else:
        yy, xx = np.mgrid[0:SIDE, 0:SIDE].astype(np.float64)
        a, b = rng.uniform(0.5, 2.5, 2)
        img = np.stack([xx * a, yy * b, (xx + yy) * 0.5 * (a + b) / 2]) % 255
    return np.clip(img, 0, 255).astype(np.float32)[None]


def cosine(a, b):
    a, b = a.reshape(-1).astype(np.float64), b.reshape(-1).astype(np.float64)
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-convert", action="store_true", help="only re-run parity on an existing package")
    args = ap.parse_args()

    if os.path.getsize(SOURCE) != SOURCE_BYTES or sha256(SOURCE) != SOURCE_SHA256:
        sys.exit("model.safetensors does not match the recorded size / SHA-256; refusing to convert")

    state = {k[len(PREFIX):]: v for k, v in read_safetensors(SOURCE).items() if k.startswith(PREFIX)}
    net = IR101()
    net.load_state_dict(state, strict=True)                    # any missing or unexpected key is an error
    model = Wrapped(net).eval()
    params = sum(p.numel() for p in net.parameters())

    import coremltools as ct
    out = {}
    example = torch.from_numpy(synthetic(1, 0))
    for name, precision in (("FaceEmbedding", ct.precision.FLOAT16), ("FaceEmbedding-fp32", ct.precision.FLOAT32)):
        path = os.path.join(MODELS, name + ".mlpackage")
        if not args.skip_convert:
            traced = torch.jit.trace(model, example, strict=True)
            ml = ct.convert(
                traced, convert_to="mlprogram", compute_precision=precision,
                minimum_deployment_target=ct.target.macOS15,
                inputs=[ct.TensorType(name="face", shape=(1, 3, SIDE, SIDE), dtype=np.float32)],
                outputs=[ct.TensorType(name="embedding", dtype=np.float32)])
            ml.author = "AdaFace IR-101 (WebFace12M) by Minchul Kim et al.; Core ML conversion for WindowShade"
            ml.license = "No licence statement on the weights. Model card: cite the paper and follow the licence of the training dataset (WebFace260M subset, research use)."
            ml.short_description = "Face identity embedding. Input: aligned 112x112 RGB face, 0...255. Output: L2-normalised 512-d."
            ml.version = "adaface-ir101-webface12m-" + SOURCE_SHA256[:12]
            if os.path.exists(path):
                import shutil; shutil.rmtree(path)
            ml.save(path)
        out[name] = ct.models.MLModel(path, compute_units=ct.ComputeUnit.ALL)

    rows, worst = [], {k: 1.0 for k in out}
    with torch.no_grad():
        for kind in (0, 1, 2):
            for seed in (1, 2, 3, 4):
                x = synthetic(kind, seed)
                ref = model(torch.from_numpy(x)).numpy()
                row = {"kind": kind, "seed": seed}
                for name, ml in out.items():
                    c = cosine(ref, ml.predict({"face": x})["embedding"])
                    row[name] = round(c, 6)
                    worst[name] = min(worst[name], c)
                rows.append(row)
        # Separation sanity check on synthetic inputs: different blobs must not collapse to one vector.
        embs = [model(torch.from_numpy(synthetic(1, s))).numpy() for s in range(10, 16)]
        cross = max(cosine(embs[i], embs[j]) for i in range(6) for j in range(i + 1, 6))

    x = synthetic(1, 99)
    lat = {}
    for name, ml in out.items():
        ml.predict({"face": x})
        t = time.perf_counter()
        for _ in range(20):
            ml.predict({"face": x})
        lat[name] = round((time.perf_counter() - t) / 20 * 1000, 2)

    report = {
        "source": {"file": "model.safetensors", "bytes": SOURCE_BYTES, "sha256": SOURCE_SHA256,
                   "repo": "huggingface.co/minchul/cvlface_adaface_ir101_webface12m"},
        "parameters": params,
        "packages": {n: {"bytes": tree_bytes(os.path.join(MODELS, n + ".mlpackage"))} for n in out},
        "parity_min_cosine_vs_torch_fp32": {k: round(v, 6) for k, v in worst.items()},
        "parity_rows": rows,
        "synthetic_cross_max_cosine": round(cross, 4),
        "latency_ms_per_face_compute_units_all": lat,
        "torch": torch.__version__, "coremltools": ct.__version__,
    }
    with open(os.path.join(MODELS, "FaceEmbedding.report.json"), "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps({k: v for k, v in report.items() if k != "parity_rows"}, indent=2))
    if min(worst.values()) < 0.999:
        sys.exit("parity below 0.999")


if __name__ == "__main__":
    main()
