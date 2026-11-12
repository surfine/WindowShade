# Face model (identity match for face unlock, experimental)

Converts the AdaFace IR-101 network trained on WebFace12M to Core ML and records the parity check.
Decision 116 (2026-11-12) chose this model for all three levels of 「認出你」.

The weights are **not in git and not in the app bundle**. They live in
`/Users/aaron/Documents/WindowShade-models/face/` (override with `WS_FACE_MODEL_DIR`).

## Licence status

- Code of AdaFace: MIT (github.com/mk-minchul/AdaFace).
- Weights: the model card carries no licence. It says: "Please cite the orignal paper and follow the license
  of the training dataset." The training set is a WebFace260M subset, released for research use.
- WindowShade is free and non-commercial. Anyone who uses this model does so under those terms.
- Paper to cite: Kim, Jain, Liu. "AdaFace: Quality Adaptive Margin for Face Recognition." CVPR 2022.
  arXiv:2204.00964.

## Ready-made package (decision 117)

The converted FP16 package is published for users as a release that is not an app version:
https://github.com/surfine/WindowShade/releases/tag/face-model-1
(`FaceEmbedding.mlpackage.zip`, 121,226,564 bytes, SHA-256
`174380b77aca0869a302461ccbddf146095bb6ee93c284f8f27a32278de1ff79`). It is not marked Latest, so
`releases/latest` and `scripts/release-gate.sh` still resolve to the app.

## Download of the original weights (approved 2026-11-12)

Into `/Users/aaron/Documents/WindowShade-models/face/adaface_ir101_webface12m/download/`. Nothing else is needed.

| File | URL | Bytes | SHA-256 |
| --- | --- | --- | --- |
| `model.safetensors` | https://huggingface.co/minchul/cvlface_adaface_ir101_webface12m/resolve/main/model.safetensors | 260,980,552 | `2ea535a43877bd3de8091903935c783ce335be66a9f8917fae9a7a18ae4bbf56` |

`convert.py` checks the size and the hash before it converts. The author's Python files in that repository
are not needed: the script states the same network itself and reads only the tensor file.

## Reproduce

```bash
M=/Users/aaron/Documents/WindowShade-models
D=$M/face/adaface_ir101_webface12m/download
mkdir -p $D
curl -fL https://huggingface.co/minchul/cvlface_adaface_ir101_webface12m/resolve/main/model.safetensors -o $D/model.safetensors
$M/venv/bin/python -I tools/face-model/convert.py
```

The venv is the one from `tools/speaker-model/README.md` (torch, coremltools, numpy).
The script writes `FaceEmbedding.mlpackage` (FP16), `FaceEmbedding-fp32.mlpackage` (reference) and
`FaceEmbedding.report.json` next to the download folder.

## Model contract

- Input `face`: `[1, 3, 112, 112]` float32, RGB, values 0 to 255. The face must already be aligned with the
  standard five-point ArcFace template. The model applies `x / 127.5 - 1` itself.
- Output `embedding`: `[1, 512]` float32, L2-normalised. Compare by cosine.
- `mlprogram`, minimum macOS 15.

## Measured here (this Mac, 2026-11-12)

| | FP16 | FP32 |
| --- | --- | --- |
| Package size | 130.6 MB | 260.9 MB |
| Minimum cosine against torch FP32, 12 synthetic inputs | 0.999347 | 1.000000 |
| Time per face, compute units `all`, mean of 20 | 18.65 ms | 79.29 ms |

Parameters loaded: 65,150,912, with strict key matching.

Not measured yet: accuracy on real faces, the false-accept rate, and the match threshold. The parity inputs
are synthetic (noise, gradients, a skin-toned oval), so they prove that the conversion is faithful, not that
the model recognises people. Those numbers come from the calibration step (`tools/face-calibration`).
The Swift backend that calls this model is not written yet.
