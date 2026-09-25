// Render the three covers as PNG: node scripts/covers.mjs [out-dir]
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import { execFileSync } from "node:child_process";
import path from "node:path";

const out = path.resolve(process.argv[2] ?? "out/covers");
const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
for (const [id, file] of [
  ["CoverBilibili", "bilibili-1920x1080.png"],
  ["CoverYouTube", "youtube-1920x1080.png"],
  ["CoverXiaohongshu", "xiaohongshu-1080x1440.png"],
]) {
  const composition = await selectComposition({ serveUrl, id });
  await renderStill({ composition, serveUrl, output: path.join(out, file), imageFormat: "png" });
  console.log(path.join(out, file));
}
// YouTube caps thumbnails at 2 MB; a JPEG keeps it well under.
execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-i", path.join(out, "youtube-1920x1080.png"), "-q:v", "2", path.join(out, "youtube-1920x1080.jpg")]);
