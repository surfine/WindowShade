// Synthesizes the promo soundtrack from the cue sheet in src/timeline.ts:
// music (D major, 120 bpm, one chord per bar) plus every sound effect on its frame.
// No dependencies. Writes public/soundtrack.wav (48 kHz, 16-bit, stereo).
//   node scripts/audio.ts
import fs from "node:fs";
import { BAR, FPS, OPENER, SCENES, TOTAL, sceneStart, sfx } from "../src/timeline.ts";
import type { SceneId } from "../src/timeline.ts";

const RATE = 48000;
const N = Math.round((TOTAL / FPS) * RATE);
const SPF = RATE / FPS; // samples per video frame
const BAR_S = (BAR / FPS) * RATE; // samples per bar
const BARS = SCENES.reduce((n, s) => n + s.bars, 0);
const TAU = Math.PI * 2;

// ---------------------------------------------------------------- buses

type Bus = { L: Float32Array; R: Float32Array };
const bus = (): Bus => ({ L: new Float32Array(N), R: new Float32Array(N) });
const music = bus();
const effects = bus();
const send = bus(); // reverb send

/** Equal-power pan: -1 left … 1 right. */
const panLR = (pan: number): [number, number] => [Math.cos(((pan + 1) * Math.PI) / 4), Math.sin(((pan + 1) * Math.PI) / 4)];

function put(b: Bus, i: number, v: number, l: number, r: number) {
  if (i < 0 || i >= N) return;
  b.L[i] += v * l;
  b.R[i] += v * r;
}

// Deterministic noise, so every run writes the same file.
let seed = 0x5eed5a3a;
const rnd = () => {
  seed = (seed + 0x6d2b79f5) >>> 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const noise = () => rnd() * 2 - 1;

// ---------------------------------------------------------------- building blocks

type ToneOpts = { dur: number; f0: number; f1?: number; amp: number; attack?: number; decay: number; pan?: number; harm2?: number; wet?: number };

/** Sine with an exponential pitch glide and an attack / exponential-decay envelope. */
function tone(b: Bus, at: number, o: ToneOpts) {
  const len = Math.round(o.dur * RATE);
  const [l, r] = panLR(o.pan ?? 0);
  const f1 = o.f1 ?? o.f0;
  const att = (o.attack ?? 0.002) * RATE;
  const h2 = o.harm2 ?? 0;
  let ph = 0;
  for (let i = 0; i < len; i++) {
    const f = o.f0 * Math.pow(f1 / o.f0, i / len);
    ph += (TAU * f) / RATE;
    const e = Math.min(1, i / att) * Math.exp(-i / (o.decay * RATE)) * Math.min(1, (len - i) / (0.004 * RATE));
    const v = (Math.sin(ph) + h2 * Math.sin(2 * ph)) * o.amp * e;
    put(b, at + i, v, l, r);
    if (o.wet) put(send, at + i, v * o.wet, l, r);
  }
}

type HissOpts = {
  dur: number;
  f0: number;
  f1?: number;
  q?: number;
  amp: number;
  shape: "bell" | "decay";
  decay?: number;
  pan0?: number;
  pan1?: number;
  am?: number;
  wet?: number;
  high?: boolean;
};

/** Noise through a state-variable filter whose center glides f0 → f1 (bandpass, or highpass). */
function hiss(b: Bus, at: number, o: HissOpts) {
  const len = Math.round(o.dur * RATE);
  const f1 = o.f1 ?? o.f0;
  const damp = 1 / (o.q ?? 1.2);
  const p0 = o.pan0 ?? 0;
  const p1 = o.pan1 ?? p0;
  let low = 0;
  let band = 0;
  for (let i = 0; i < len; i++) {
    const x = i / len;
    const fc = o.f0 * Math.pow(f1 / o.f0, x);
    const f = 2 * Math.sin((Math.PI * Math.min(fc, RATE / 6)) / RATE);
    const high = noise() - low - damp * band;
    band += f * high;
    low += f * band;
    const e = o.shape === "bell" ? Math.pow(Math.sin(Math.PI * x), 1.6) : Math.min(1, i / (0.001 * RATE)) * Math.exp(-i / ((o.decay ?? 0.05) * RATE));
    const am = o.am ? 0.8 + 0.2 * Math.sin((TAU * o.am * i) / RATE) : 1;
    const [l, r] = panLR(p0 + (p1 - p0) * x);
    const v = (o.high ? high * 0.5 : band) * o.amp * e * am;
    put(b, at + i, v, l, r);
    if (o.wet) put(send, at + i, v * o.wet, l, r);
  }
}

// ---------------------------------------------------------------- instruments

const hz = (midi: number) => 440 * Math.pow(2, (midi - 69) / 12);
// Dmaj9 · Bm9 · Gmaj9 · A6sus, one per bar
const CHORDS = [
  [62, 66, 69, 73, 76],
  [59, 62, 66, 69, 73],
  [55, 59, 62, 66, 69],
  [57, 62, 64, 66, 69],
];
const ROOTS = [38, 35, 31, 33];

/** Karplus–Strong string. `dark` dulls the loop filter for the history bars. */
function pluck(at: number, freq: number, amp: number, pan: number, dark = false) {
  const period = Math.max(2, Math.round(RATE / freq));
  const buf = new Float32Array(period);
  for (let i = 0; i < period; i++) buf[i] = noise();
  const len = Math.round(1.6 * RATE);
  const [l, r] = panLR(pan);
  const loss = dark ? 0.992 : 0.996;
  let idx = 0;
  let prev = 0;
  for (let i = 0; i < len; i++) {
    const cur = buf[idx];
    const nxt = buf[idx + 1 === period ? 0 : idx + 1];
    buf[idx] = (dark ? (cur + nxt + prev) / 3 : (cur + nxt) * 0.5) * loss;
    prev = cur;
    idx = idx + 1 === period ? 0 : idx + 1;
    const v = cur * amp * Math.min(1, i / 24);
    put(music, at + i, v, l, r);
    put(send, at + i, v * 0.5, l, r);
  }
}

/** Band-limited saw (8 harmonics) as a lookup table, shared by every pad voice. */
const TABLE = 2048;
const SAW = new Float32Array(TABLE + 1);
for (let i = 0; i <= TABLE; i++) for (let h = 1; h <= 8; h++) SAW[i] += Math.sin((TAU * h * i) / TABLE) / h;

/** Three detuned saws per note, a gentle lowpass, slow attack and release. */
function pad(at: number, notes: number[], seconds: number, amp: number) {
  const len = Math.round(seconds * RATE);
  const raw = new Float32Array(len);
  for (const n of notes) {
    for (const cents of [-6, 0, 6]) {
      const inc = (hz(n) * Math.pow(2, cents / 1200) * TABLE) / RATE;
      let ph = rnd() * TABLE;
      for (let i = 0; i < len; i++) {
        const k = ph | 0;
        raw[i] += SAW[k] + (SAW[k + 1] - SAW[k]) * (ph - k);
        ph += inc;
        if (ph >= TABLE) ph -= TABLE;
      }
    }
  }
  const a = Math.exp((-TAU * 1400) / RATE);
  const g = amp / (notes.length * 3);
  const attack = 0.35 * RATE;
  const release = 0.6 * RATE;
  let y = 0;
  for (let i = 0; i < len; i++) {
    y = (1 - a) * raw[i] + a * y;
    const v = y * g * Math.min(1, i / attack) * Math.min(1, (len - i) / release);
    put(music, at + i, v, 0.92, 0.92);
    put(send, at + i, v * 0.6, 0.92, 0.92);
  }
}

function kick(at: number) {
  const len = Math.round(0.35 * RATE);
  let ph = 0;
  for (let i = 0; i < len; i++) {
    const t = i / RATE;
    ph += (TAU * (45 + 65 * Math.exp(-t / 0.035))) / RATE;
    const click = i < 144 ? noise() * 0.08 * (1 - i / 144) : 0;
    put(music, at + i, Math.sin(ph) * Math.exp(-t / 0.2) * Math.min(1, i / 48) * 0.55 + click, 0.707, 0.707);
  }
}
const clap = (at: number) => hiss(music, at, { dur: 0.2, f0: 1500, q: 1.4, amp: 0.2, shape: "decay", decay: 0.06, wet: 0.5 });
const hat = (at: number, open: boolean, amp: number) =>
  hiss(music, at, { dur: open ? 0.25 : 0.06, f0: 9000, q: 0.8, amp: 0.05 * amp, shape: "decay", decay: open ? 0.09 : 0.02, high: true, pan0: 0.25 });

// ---------------------------------------------------------------- arrangement

// Sections follow the scenes, so the music changes when the picture does.
const barOf = (id: SceneId) => sceneStart(id) / BAR;
const HISTORY_BARS = [barOf("History"), barOf("Glance")];
const GESTURE_BAR = barOf("Gestures");
const END_BAR = barOf("End");
const GROOVE_BAR = barOf("Ways");
const BLACK_S = (sceneStart("Opener") + OPENER.black) * SPF; // cut to black, mid-bar

type Part = { pad: number; pluck: number; drums: boolean; bass: boolean; clap: boolean; dark: boolean; sparkle: boolean };
function part(bar: number): Part {
  const p: Part = { pad: 1, pluck: 1, drums: true, bass: true, clap: true, dark: false, sparkle: false };
  const quiet = { drums: false, bass: false, clap: false };
  if (bar < GROOVE_BAR) return { ...p, ...quiet, pluck: 0.8 }; // windows pile up (cut short by the black)
  if (bar >= HISTORY_BARS[0] && bar < HISTORY_BARS[1]) return { ...p, dark: true, clap: false, pluck: 0.8 };
  if (bar === GESTURE_BAR) return { ...p, ...quiet, pad: 0.7, pluck: 0 }; // title card + riser
  if (bar > GESTURE_BAR && bar < barOf("More")) return { ...p, sparkle: true };
  if (bar >= END_BAR) return { ...p, ...quiet, pad: 0, pluck: bar === END_BAR ? 0.9 : 0 };
  return p;
}

const ARP = [0, 4, 2, 4, 1, 4, 2, 4];
const eighth = BAR_S / 8;
for (let bar = 0; bar < BARS; bar++) {
  const at = Math.round(bar * BAR_S);
  const ch = bar >= END_BAR ? CHORDS[0] : CHORDS[bar % 4];
  const root = bar >= END_BAR ? ROOTS[0] : ROOTS[bar % 4];
  const p = part(bar);
  // Before the groove, nothing may sound past the cut to black.
  const before = (i: number) => bar >= GROOVE_BAR || at + i < BLACK_S;

  if (bar === END_BAR) pad(at, ch, (BARS - END_BAR) * (BAR / FPS), 0.34); // final chord holds to the end
  if (p.pad > 0 && bar >= GROOVE_BAR) pad(at, ch, BAR / FPS + 0.1, 0.3 * p.pad);
  if (p.pad > 0 && bar < GROOVE_BAR && at < BLACK_S) pad(at, ch, Math.min(BAR_S, BLACK_S - at) / RATE, 0.3 * p.pad);

  if (p.pluck > 0) {
    for (let k = 0; k < 8; k++) {
      if (!before(k * eighth)) continue;
      const n = ch[ARP[k]] + (k % 4 === 2 ? 12 : 0);
      pluck(Math.round(at + k * eighth), hz(n), (0.24 + 0.05 * rnd()) * p.pluck * (k % 2 ? 0.8 : 1), k % 2 ? 0.3 : -0.3, p.dark);
    }
  }
  if (p.sparkle) {
    for (let k = 0; k < 16; k++) pluck(Math.round(at + (k * eighth) / 2), hz(ch[k % 5] + 12), 0.06, k % 2 ? 0.45 : -0.45);
  }
  if (p.bass) {
    tone(music, at, { dur: 0.5, f0: hz(root), amp: 0.36, attack: 0.005, decay: 0.3, harm2: 0.25 });
    tone(music, Math.round(at + 3 * eighth), { dur: 0.4, f0: hz(root), amp: 0.26, attack: 0.005, decay: 0.25, harm2: 0.25 });
  }
  if (p.drums) {
    kick(at);
    kick(Math.round(at + BAR_S / 2));
    if (p.clap) {
      clap(Math.round(at + BAR_S / 4));
      clap(Math.round(at + (3 * BAR_S) / 4));
    }
    for (let k = 0; k < 8; k++) hat(Math.round(at + (k + 0.5) * eighth), k === 7 && bar % 4 === 3, p.dark ? 0.5 : 1);
  }
  if (bar === GESTURE_BAR) hiss(music, at, { dur: BAR / FPS, f0: 300, f1: 6000, q: 0.9, amp: 0.55, shape: "bell", pan0: -0.3, pan1: 0.3, wet: 0.4 });
}

// Under "先别急着关": a low, sparse chord from the cut to black until the groove.
{
  const at = Math.round(BLACK_S);
  const seconds = (GROOVE_BAR * BAR_S - BLACK_S) / RATE;
  pad(at, [50, 57, 62], seconds + 0.1, 0.26);
  tone(music, at, { dur: seconds, f0: hz(38), amp: 0.16, attack: 0.4, decay: 6 });
}

// ---------------------------------------------------------------- sound effects

const ducks: number[] = [];
for (const e of sfx()) {
  const at = Math.round(e.at * SPF);
  const g = e.gain ?? 1;
  const p = e.pitch ?? 1;
  const b = effects;
  switch (e.kind) {
    case "key":
    case "keySoft": {
      const soft = e.kind === "keySoft" ? 0.6 : 1;
      hiss(b, at, { dur: 0.012, f0: 3000 * p, q: 1.5, amp: 0.5 * g * soft, shape: "decay", decay: 0.003 });
      tone(b, at, { dur: 0.04, f0: 900 * p * soft, amp: 0.12 * g * soft, decay: 0.012 });
      break;
    }
    case "pop":
      tone(b, at, { dur: 0.12, f0: 520 * p, f1: 880 * p, amp: 0.3 * g, decay: 0.04, pan: 0.1, wet: 0.2 });
      break;
    case "cut":
      tone(b, at, { dur: 0.6, f0: 70, f1: 50, amp: 0.3 * g, decay: 0.25 });
      hiss(b, at, { dur: 0.08, f0: 800, q: 0.7, amp: 0.4 * g, shape: "decay", decay: 0.02 });
      ducks.push(at);
      break;
    case "whoosh":
      hiss(b, at, { dur: 0.45, f0: 400 * p, f1: 3000 * p, q: 1.6, amp: 0.55 * g, shape: "bell", pan0: -0.6, pan1: 0.6, wet: 0.3 });
      break;
    case "close":
      hiss(b, at, { dur: 0.14, f0: 700, f1: 300, q: 0.8, amp: 0.35 * g, shape: "decay", decay: 0.05 });
      tone(b, at, { dur: 0.14, f0: 300, f1: 150, amp: 0.2 * g, decay: 0.05 });
      break;
    case "minimize":
      hiss(b, at, { dur: 0.36, f0: 2500, f1: 300, q: 1.6, amp: 0.5 * g, shape: "bell", wet: 0.25 });
      break;
    case "click":
      hiss(b, at, { dur: 0.006, f0: 4000, q: 0.8, amp: 0.6 * g, shape: "decay", decay: 0.0015 });
      tone(b, at, { dur: 0.03, f0: 3200 * p, amp: 0.16 * g, decay: 0.006 });
      break;
    case "rollUp":
    case "rollDown": {
      const up = e.kind === "rollUp";
      hiss(b, at, { dur: 0.45, f0: (up ? 600 : 2400) * p, f1: (up ? 2400 : 600) * p, q: 1.8, amp: 0.55 * g, shape: "bell", am: 45, wet: 0.25 });
      break;
    }
    case "thock":
      tone(b, at, { dur: 0.3, f0: 180 * p, amp: 0.5 * g, decay: 0.08, wet: 0.3 });
      tone(b, at, { dur: 0.2, f0: 540 * p, amp: 0.18 * g, decay: 0.04, wet: 0.3 });
      break;
    case "glanceOpen":
    case "glanceClose": {
      const open = e.kind === "glanceOpen";
      tone(b, at, { dur: 0.14, f0: open ? 500 : 820, f1: open ? 820 : 500, amp: (open ? 0.24 : 0.16) * g, decay: 0.06, wet: 0.35 });
      hiss(b, at, { dur: 0.16, f0: open ? 2000 : 4000, f1: open ? 4000 : 2000, q: 1, amp: 0.1 * g, shape: "bell" });
      break;
    }
    case "touch":
      tone(b, at, { dur: 0.06, f0: 140, amp: 0.3 * g, decay: 0.018 });
      break;
    case "arm":
      tone(b, at, { dur: 0.06, f0: 160, amp: 0.55 * g, decay: 0.02 });
      tone(b, at, { dur: 0.03, f0: 1800, amp: 0.14 * g, decay: 0.008 });
      break;
    case "cancel":
      tone(b, at, { dur: 0.07, f0: 700, amp: 0.16 * g, decay: 0.03 });
      tone(b, at + Math.round(0.08 * RATE), { dur: 0.1, f0: 520, amp: 0.16 * g, decay: 0.04 });
      break;
    case "notch":
      hiss(b, at, { dur: 0.004, f0: 4500 * p, q: 1, amp: 0.5 * g, shape: "decay", decay: 0.001 });
      tone(b, at, { dur: 0.02, f0: 400 * p, amp: 0.22 * g, decay: 0.006 });
      break;
    case "keycap":
      hiss(b, at, { dur: 0.012, f0: 2000 * p, q: 1.2, amp: 0.5 * g, shape: "decay", decay: 0.004 });
      tone(b, at, { dur: 0.04, f0: 1100 * p, amp: 0.14 * g, decay: 0.01 });
      break;
    case "chime":
      // FM bell: modulator at 3.5 × the carrier, its depth fading out; plus the octave below.
      for (const [carrier, amp] of [
        [1174.66 * p, 0.28 * g],
        [587.33 * p, 0.14 * g],
      ]) {
        const len = Math.round(2.4 * RATE);
        let cph = 0;
        let mph = 0;
        for (let i = 0; i < len; i++) {
          const t = i / RATE;
          mph += (TAU * carrier * 3.5) / RATE;
          cph += (TAU * carrier) / RATE + Math.sin(mph) * 3 * Math.exp(-t / 0.35) * ((TAU * carrier * 3.5) / RATE);
          const v = Math.sin(cph) * amp * Math.min(1, t / 0.003) * Math.exp(-t / 0.6);
          put(b, at + i, v, 0.75, 0.66);
          put(send, at + i, v * 0.7, 0.75, 0.66);
        }
      }
      break;
    default:
      console.warn(`skipped unknown sound "${e.kind}" at frame ${e.at}`);
  }
}

// ---------------------------------------------------------------- mix

const peak = (b: Bus) => {
  let m = 0;
  for (let i = 0; i < N; i++) m = Math.max(m, Math.abs(b.L[i]), Math.abs(b.R[i]));
  return m || 1;
};

// Duck the music under the cut to black.
for (const at of ducks) {
  const len = Math.round(0.6 * RATE);
  const floor = Math.pow(10, -8 / 20);
  for (let i = 0; i < len && at + i < N; i++) {
    const x = i / len;
    const g = 1 - (1 - floor) * Math.min(1, x / 0.05) * Math.min(1, (1 - x) / 0.5);
    music.L[at + i] *= g;
    music.R[at + i] *= g;
  }
}

/** Schroeder reverb: four damped combs in parallel, then two allpasses. */
function reverb(input: Float32Array, spread: number) {
  const out = new Float32Array(N);
  const combs = [29.7, 37.1, 41.1, 43.7].map((ms) => ({ buf: new Float32Array(Math.round(((ms + spread) / 1000) * RATE)), pos: 0, lp: 0 }));
  const aps = [5.0, 1.7].map((ms) => ({ buf: new Float32Array(Math.round(((ms + spread / 4) / 1000) * RATE)), pos: 0 }));
  for (let i = 0; i < N; i++) {
    const x = input[i];
    let acc = 0;
    for (const c of combs) {
      const y = c.buf[c.pos];
      c.lp = y * 0.7 + c.lp * 0.3;
      c.buf[c.pos] = x + c.lp * 0.8;
      c.pos = c.pos + 1 === c.buf.length ? 0 : c.pos + 1;
      acc += y;
    }
    let y = acc / 4;
    for (const a of aps) {
      const d = a.buf[a.pos];
      a.buf[a.pos] = y + d * 0.7;
      a.pos = a.pos + 1 === a.buf.length ? 0 : a.pos + 1;
      y = d - y * 0.7;
    }
    out[i] = y;
  }
  return out;
}
const wetL = reverb(send.L, 0);
const wetR = reverb(send.R, 1.6);

// Music bed near -12 dBFS, effects near -6 dBFS, soft limit, then peak at -1 dBFS.
const musicGain = Math.pow(10, -12 / 20) / peak(music);
const fxGain = Math.pow(10, -6 / 20) / peak(effects);
const out = bus();
const fadeIn = 0.3 * RATE;
const fadeOut = 1.5 * RATE;
for (let i = 0; i < N; i++) {
  const f = Math.min(1, i / fadeIn, (N - i) / fadeOut);
  out.L[i] = Math.tanh((music.L[i] * musicGain + effects.L[i] * fxGain + wetL[i] * musicGain * 0.35) * 1.9) * f;
  out.R[i] = Math.tanh((music.R[i] * musicGain + effects.R[i] * fxGain + wetR[i] * musicGain * 0.35) * 1.9) * f;
}
const norm = Math.pow(10, -1 / 20) / peak(out);

// ---------------------------------------------------------------- WAV

const pcm = new Int16Array(N * 2);
for (let i = 0; i < N; i++) {
  pcm[2 * i] = Math.round(Math.max(-1, Math.min(1, out.L[i] * norm)) * 32767);
  pcm[2 * i + 1] = Math.round(Math.max(-1, Math.min(1, out.R[i] * norm)) * 32767);
}
const header = Buffer.alloc(44);
header.write("RIFF", 0);
header.writeUInt32LE(36 + pcm.byteLength, 4);
header.write("WAVE", 8);
header.write("fmt ", 12);
header.writeUInt32LE(16, 16);
header.writeUInt16LE(1, 20);
header.writeUInt16LE(2, 22);
header.writeUInt32LE(RATE, 24);
header.writeUInt32LE(RATE * 4, 28);
header.writeUInt16LE(4, 32);
header.writeUInt16LE(16, 34);
header.write("data", 36);
header.writeUInt32LE(pcm.byteLength, 40);
fs.mkdirSync("public", { recursive: true });
fs.writeFileSync("public/soundtrack.wav", Buffer.concat([header, Buffer.from(pcm.buffer)]));
console.log(`public/soundtrack.wav · ${(N / RATE).toFixed(2)} s · ${sfx().length} sounds · ${BARS} bars`);
