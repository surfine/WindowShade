// Render a handful of frames for review: node scripts/stills.mjs out-dir frame frame ...
// COMP=PromoVertical renders the 9:16 cut.
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import path from "node:path";

const [out, ...frames] = process.argv.slice(2);
const scale = Number(process.env.SCALE ?? 0.5);
const quality = Number(process.env.Q ?? 80);
const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
const composition = await selectComposition({ serveUrl, id: process.env.COMP ?? "Promo" });
for (const f of frames.map(Number)) {
  await renderStill({
    composition,
    serveUrl,
    frame: f,
    output: path.join(out, `f${String(f).padStart(4, "0")}.jpg`),
    imageFormat: "jpeg",
    jpegQuality: quality,
    scale,
    chromiumOptions: { gl: "angle" },
  });
  process.stdout.write(`${f} `);
}
console.log();
