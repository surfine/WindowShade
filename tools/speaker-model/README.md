# Speaker model (voice match for face unlock, experimental)

Converts the WeSpeaker ResNet34 VoxCeleb speaker-embedding network to Core ML and records the parity check.
The weights are **not in git**. They live in `/Users/aaron/Documents/WindowShade-models/speaker/` and
`prototype/build.sh` compiles `SpeakerEmbedding.mlpackage` from there into
`WindowShade.app/Contents/Resources/SpeakerEmbedding.mlmodelc` when it is present. When it is absent the build
skips it, `LazySpeakerVerifier` stays unavailable and the voice check fails closed (the microphone never opens).
Override the folder with `WINDOWSHADE_SPEAKER_MODEL_DIR`.

## Downloads (approved: decisions 76, 78, 80)

All into `/Users/aaron/Documents/WindowShade-models/speaker/` (outside the repo). Nothing else is downloaded.

| File | URL | Bytes | SHA-256 |
| --- | --- | --- | --- |
| `voxceleb_resnet34.onnx` | https://huggingface.co/Wespeaker/wespeaker-voxceleb-resnet34/resolve/main/voxceleb_resnet34.onnx | 26,534,127 | `9fea6516d7ad6bf0a76c7689f5a49b65d330fad6dde96c91bb4435ffbfe056a1` |
| `avg_model.pt` | https://huggingface.co/Wespeaker/wespeaker-voxceleb-resnet34/resolve/main/avg_model.pt | 45,053,131 | `ac00dd664205fdec58e5c6768b1dfbb732225a1e69486f89461e5f88d39d8d22` |
| `config.yaml` | https://huggingface.co/Wespeaker/wespeaker-voxceleb-resnet34/resolve/main/config.yaml | 1,536 | `10d328c36178263b787ded901d9290ead35124f876edba7e78bbf423208496f5` |
| `wespeaker-src/` | `git clone --depth 1 https://github.com/wenet-e2e/wespeaker` | commit `9fecd6cb4f47475d01761d87c826298dff4ef18c` | |

(The ONNX file is kept for reference; the conversion uses `avg_model.pt` + `config.yaml` + the `resnet.py` source.)

## Reproduce

```bash
M=/Users/aaron/Documents/WindowShade-models
mkdir -p $M/speaker && cd $M/speaker
B=https://huggingface.co/Wespeaker/wespeaker-voxceleb-resnet34/resolve/main
curl -fLO $B/voxceleb_resnet34.onnx && curl -fLO $B/avg_model.pt && curl -fLO $B/config.yaml
shasum -a 256 voxceleb_resnet34.onnx avg_model.pt config.yaml     # compare with the table
git clone --depth 1 https://github.com/wenet-e2e/wespeaker wespeaker-src
uv venv $M/venv --python 3.12
uv pip install --python $M/venv/bin/python torch coremltools onnx torchaudio numpy pyyaml
cd <repo> && $M/venv/bin/python tools/speaker-model/convert.py     # writes SpeakerEmbedding.mlpackage + tests/fixtures/speaker-fbank-reference.json
tests/run-speaker-verification-tests.sh                             # Swift fbank vs reference, enrolment, verifier, Core ML end to end
```

Versions used: torch 2.15.0, torchaudio 2.11.1, coremltools (see `pip.log` next to the venv), Python 3.12.

## Model contract

- Input `fbank`: `[1, 300, 80]` float32 = 300 frames of Kaldi fbank (80 mel, 25 ms / 10 ms, Hamming, no dither,
  int16 scale, pre-emphasis 0.97, 20 Hz to 8 kHz) after per-utterance CMN. 300 frames = 3.015 s of 16 kHz mono.
- Output `embedding`: `[256]` float32. Compare by cosine.
- FP16 `mlprogram`, minimum macOS 15, compute units `cpuAndNeuralEngine`.
- Fixed window, not a flexible shape: statistics pooling over a variable length does not run well on the Neural Engine.
  `SpeakerFbank.windows` tiles shorter audio to 300 frames and slides over longer audio (hop 150, at most 6 windows);
  the window embeddings are averaged and re-normalised. Silence at both ends is trimmed first
  (`SpeakerSpeechTrim`), and less than 1.2 s of speech counts as "unavailable", not "different".

## Measured here (this Mac, 2026-10-31)

Parity, torch (FP32) vs Core ML (FP16), cosine of the 256-d embeddings:

| Input | Cosine |
| --- | --- |
| synthetic tone + noise, kinds 0 / 1 / 2 | 0.999974 / 0.999967 / 0.999979 |
| random-normal features, 3 seeds | 0.999973 / 0.999976 / 0.999973 |

Minimum 0.999967 (requirement was >= 0.999). The Swift front end matches torchaudio `kaldi.fbank` to a max absolute
difference of 1.9e-4 (log-mel) on the fixture waveform, and the full Swift path (Swift fbank, Core ML) against the torch
embedding gives cosine 0.999967.

Latency of one 3 s window:

| Where | Compute units | Median | p90 |
| --- | --- | --- | --- |
| Python `coremltools` `predict` (includes Python overhead) | CPU + ANE | 15.4 ms | 60.1 ms |
| Python | ALL | 9.1 ms | 69.0 ms |
| Python | CPU only | 699 ms | 1090 ms |
| Swift, in process (`tests/run-speaker-verification-tests.sh`) | CPU + ANE | about 3 ms | about 3-30 ms |

The Swift fbank for 3 s takes under 1 ms (-O). First model load can take seconds (Neural Engine compile), which is why
`LazySpeakerVerifier` loads it on a background thread and reports "unavailable" until it is ready.

## Accuracy: what is and is not known

The WeSpeaker README reports EER 0.867 % on VoxCeleb1-O-clean for ResNet34-TSTP-emb256 (cosine, no AS-norm, the
mean of vox2_dev subtracted). That is a **long-utterance** number on celebrity interview audio. It says nothing yet
about a three-word phrase from a MacBook microphone in a quiet room, a noisy room, another person, or a replayed
recording. `SpeakerVerification.provisionalCosineThreshold` (0.55) and `provisionalEnrolmentConsistency` (0.35) are
provisional and must be calibrated on device before anyone believes a number. Until then the check only lifts a
near-threshold face score and never unlocks anything by itself (`FaceAutofill.decide` enforces that).

## Licenses and attribution

- WeSpeaker code: Apache License 2.0 (`prototype/Vendor/WeSpeaker/LICENSE`).
- Weights: the WeSpeaker pretrained-model notice says models trained on VoxCeleb follow the dataset licence,
  Creative Commons Attribution 4.0 International. Attribution text: `prototype/Vendor/WeSpeaker/ATTRIBUTION.txt`
  (VoxCeleb2: Chung, Nagrani, Zisserman, Interspeech 2018; VoxCeleb1: Nagrani, Chung, Zisserman, Interspeech 2017;
  WeSpeaker: Wang et al., ICASSP 2023). `build.sh` appends both files to `Contents/Resources/THIRD-PARTY-LICENSES.txt`
  only when the model is bundled; the repo-level table is `docs/THIRD-PARTY-LICENSES.md`.
- CC BY 4.0 on weights trained from a dataset is the upstream project's own reading; this is not legal advice.

## Privacy

Only a 256-number voice feature (never audio) is stored, in the device-only, non-syncing keychain
(`VoiceprintKeychainStore`). Audio lives in memory for the length of one challenge (at most 12 s), is handed to the
verifier once, and is dropped. Recognition of the spoken phrase uses `SFSpeechRecognizer` with
`requiresOnDeviceRecognition = true`; if on-device recognition is unavailable the challenge fails closed.
