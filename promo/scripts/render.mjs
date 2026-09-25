// Render the film in chunks (so temporary frames never need more than ~150 MB of disk),
// join the chunks without re-encoding, then lay the soundtrack under them.
//   node scripts/render.mjs [out.mp4] [scale] [composition]
import { bundle } from "@remotion/bundler";
import { renderMedia, selectComposition } from "@remotion/renderer";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const out = path.resolve(process.argv[2] ?? "out/windowshade-promo.mp4");
const scale = Number(process.argv[3] ?? 1);
const id = process.argv[4] ?? "Promo";
const CHUNK = 480;
const work = path.join(path.dirname(out), `.chunks-${id}`);
fs.mkdirSync(work, { recursive: true });

const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
const composition = await selectComposition({ serveUrl, id });
const parts = [];
for (let from = 0; from < composition.durationInFrames; from += CHUNK) {
  const to = Math.min(composition.durationInFrames, from + CHUNK) - 1;
  const file = path.join(work, `part-${String(from).padStart(5, "0")}.mp4`);
  parts.push(file);
  if (fs.existsSync(file)) continue; // resume after an interruption
  await renderMedia({
    composition,
    serveUrl,
    codec: "h264",
    crf: 16,
    x264Preset: "slow",
    pixelFormat: "yuv420p",
    muted: true,
    scale,
    frameRange: [from, to],
    outputLocation: file + ".tmp.mp4",
    concurrency: 8,
  });
  fs.renameSync(file + ".tmp.mp4", file);
  console.log(`frames ${from}-${to} done`);
}

const list = path.join(work, "list.txt");
fs.writeFileSync(list, parts.map((p) => `file '${p}'`).join("\n"));
const audio = path.resolve("public/soundtrack.wav");
const args = ["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", list];
if (fs.existsSync(audio)) args.push("-i", audio, "-map", "0:v", "-map", "1:a", "-c:a", "aac", "-b:a", "256k", "-shortest");
args.push("-c:v", "copy", "-movflags", "+faststart", out);
execFileSync("ffmpeg", args, { stdio: "inherit" });
fs.rmSync(work, { recursive: true, force: true });
console.log(`wrote ${out} (${(fs.statSync(out).size / 1e6).toFixed(1)} MB)`);
