import { Easing, interpolate, spring } from "remotion";
import { FPS } from "./timeline";

// Same palette as the website, so the film and the site read as one product.
export const C = {
  canvas: "#f4f5f7",
  dot: "rgba(20,26,38,.07)",
  ink: "#16181c",
  muted: "#6b7079",
  faint: "#9aa0a9",
  accent: "#245eea",
  black: "#0a0b0d",
  win: "#ffffff",
  bar: "#f5f5f7",
  winInk: "#24262b",
  winMuted: "#70747c",
  line: "rgba(0,0,0,.08)",
  blueSoft: "#e9effc",
  blueText: "#214884",
  wall: "radial-gradient(120% 90% at 0% 0%,#c9dbff 0%,transparent 58%),radial-gradient(90% 80% at 100% 0%,#f1d9ee 0%,transparent 62%),radial-gradient(120% 90% at 70% 110%,#ffe3c9 0%,transparent 62%),#e7eaf3",
};

export const FONT = '-apple-system, "SF Pro Display", "PingFang SC", "Helvetica Neue", sans-serif';
export const MONO = '"SF Mono", Menlo, "PingFang SC", monospace';
export const SERIF = '"Iowan Old Style", "Songti SC", STSong, serif';

export const easeOut = Easing.bezier(0.23, 1, 0.32, 1);
export const easeInOut = Easing.bezier(0.65, 0, 0.35, 1);
export const easeRoll = Easing.bezier(0.65, 0, 0.35, 1);

/** Clamped interpolate between two frames. */
export const tw = (frame: number, from: number, to: number, a = 0, b = 1, easing: (t: number) => number = easeOut) =>
  interpolate(frame, [from, to], [a, b], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing,
  });

/** A spring that starts at `at`; 0 → 1. */
export const pop = (frame: number, at: number, damping = 14, stiffness = 170, mass = 1) =>
  spring({ frame: frame - at, fps: FPS, config: { damping, stiffness, mass } });

/** A critically damped settle, for things that should not bounce. */
export const settle = (frame: number, at: number, duration = 30) =>
  spring({ frame: frame - at, fps: FPS, config: { damping: 200 }, durationInFrames: duration });

export const mix = (a: number, b: number, t: number) => a + (b - a) * t;
