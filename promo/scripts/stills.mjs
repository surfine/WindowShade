// Render a handful of frames for review: node scripts/stills.mjs out-dir frame frame ...
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import path from "node:path";

const [out, ...frames] = process.argv.slice(2);
const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
const composition = await selectComposition({ serveUrl, id: "Promo" });
for (const f of frames.map(Number)) {
  await renderStill({ composition, serveUrl, frame: f, output: path.join(out, `f${String(f).padStart(4, "0")}.jpg`), imageFormat: "jpeg", jpegQuality: 80, scale: 0.5 });
  process.stdout.write(`${f} `);
}
console.log();
