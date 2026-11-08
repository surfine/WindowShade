// A/B bench for the 4K render path: same 120 frames, three encode/browser configs.
//   node scripts/bench-gpu.mjs
// Frames 2880-2999 cover the four blurred Glass cards — the most expensive stretch.
import { bundle } from "@remotion/bundler";
import { renderMedia, selectComposition } from "@remotion/renderer";
import path from "node:path";
import fs from "node:fs";

const out = "/tmp/ws-bench";
fs.mkdirSync(out, { recursive: true });
const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
const composition = await selectComposition({ serveUrl, id: "Promo" });

const configs = [
  { name: "A-cpu-x264-crf16", opts: {} },
  { name: "B-gl-angle", opts: { chromiumOptions: { gl: "angle" } } },
  { name: "C-videotoolbox-40M", opts: { hardwareAcceleration: "if-possible", videoBitrate: "40M" } },
];

for (const { name, opts } of configs) {
  const file = path.join(out, `${name}.mp4`);
  fs.rmSync(file, { force: true });
  const t0 = process.hrtime.bigint();
  await renderMedia({
    composition,
    serveUrl,
    codec: "h264",
    crf: opts.videoBitrate ? undefined : 16,
    x264Preset: opts.videoBitrate ? undefined : "slow",
    pixelFormat: "yuv420p",
    muted: true,
    scale: 2,
    frameRange: [2880, 2999],
    outputLocation: file,
    concurrency: 8,
    ...opts,
  });
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  const bytes = fs.statSync(file).size;
  console.log(`${name}: ${(ms / 1000).toFixed(1)}s for 120 frames (${(ms / 120).toFixed(0)} ms/frame), ${(bytes / 1e6).toFixed(1)} MB`);
}
