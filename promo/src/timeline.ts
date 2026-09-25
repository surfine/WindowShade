// One cue sheet for picture and sound. Scenes read their local frames from here, and
// scripts/audio.ts reads the same numbers to place the music, sound effects and typing clicks.
// Plain data only: no imports, so Node can run the audio script straight from this file.

export const FPS = 60;
export const BEAT = 30; // 120 bpm
export const BAR = BEAT * 4;
export const WIDTH = 1920;
export const HEIGHT = 1080;

export const SCENES = [
  { id: "Opener", bars: 3 },
  { id: "Ways", bars: 3 },
  { id: "DoubleClick", bars: 2 },
  { id: "History", bars: 2 },
  { id: "Glance", bars: 2 },
  { id: "Gestures", bars: 6 },
  { id: "More", bars: 2 },
  { id: "End", bars: 2 },
] as const;

export type SceneId = (typeof SCENES)[number]["id"];

export const sceneFrames = (id: SceneId) => SCENES.find((s) => s.id === id)!.bars * BAR;
export const sceneStart = (id: SceneId) => {
  let at = 0;
  for (const s of SCENES) {
    if (s.id === id) return at;
    at += s.bars * BAR;
  }
  throw new Error(id);
};
export const TOTAL = SCENES.reduce((n, s) => n + s.bars * BAR, 0);

// Typed lines: one character every `rate` frames, and one soft key click each.
export type Typed = { at: number; text: string; rate?: number };
export const typedFrames = (t: Typed) => [...t.text].length * (t.rate ?? 4);

// ---- Scene cues (local frames) ----

export const OPENER = {
  lineA: { at: 8, text: "窗口一多，", rate: 4 } as Typed,
  pile: [36, 46, 56, 64, 72, 78, 84, 90, 96],
  lineB: { at: 104, text: "桌面就满了。", rate: 4 } as Typed,
  black: 180,
  lineC: { at: 190, text: "先别急着关。", rate: 5 } as Typed,
  morph: 300, // caret becomes a bar, the bar opens into the next scene
};

export const WAYS = {
  cards: [6, 12, 18],
  close: 54,
  minimize: 120,
  shade: 186,
  focus: 260,
};

export const DOUBLE = {
  clicks: [44, 52],
  roll: 56,
  swap: 130,
  clicksBack: [134, 142],
  unroll: 146,
};

export const HISTORY = {
  rows: [36, 56, 76, 96],
  focus: 150,
};

export const GLANCE = {
  arrive: 44,
  open: 57, // the card appears 0.22 s after the pointer stops
  second: 130,
  leave: 190,
};

// Gestures: one bar of black title, then the desk.
export const GESTURES = {
  line: { at: 8, text: "在标题栏上，用两根手指。", rate: 3 } as Typed,
  desk: 120,
  // [fingers down, release]; progress runs between them
  shade: { down: 150, release: 206 },
  expand: { down: 244, release: 292 },
  fill: { down: 322, release: 370 },
  left: { down: 410, release: 452 },
  right: { down: 474, release: 516 },
  cancel: { down: 546, peak: 580, back: 610 },
  wheel: { swap: 628, notches: [646, 658, 670], commit: 680 },
};

export const MORE = {
  cards: [12, 24, 36],
  keys: [70, 120, 170],
};

export const END = {
  icon: 4,
  word: 30,
  tagline: 60,
  cta: 100,
  facts: 120,
};

// ---- Sound effects (global frames) ----

export type Sfx = { at: number; kind: string; gain?: number; pitch?: number };

const typedClicks = (scene: SceneId, t: Typed, gain = 0.28): Sfx[] =>
  [...t.text].map((ch, i) => ({
    at: sceneStart(scene) + t.at + i * (t.rate ?? 4),
    kind: /[，。、：；]/.test(ch) ? "keySoft" : "key",
    gain,
    pitch: 1 + ((i * 37) % 7) / 40,
  }));

export const sfx = (): Sfx[] => {
  const s = (id: SceneId) => sceneStart(id);
  const list: Sfx[] = [];
  const add = (scene: SceneId, at: number, kind: string, gain = 1, pitch = 1) => list.push({ at: s(scene) + at, kind, gain, pitch });

  list.push(...typedClicks("Opener", OPENER.lineA));
  OPENER.pile.forEach((f, i) => add("Opener", f, "pop", 0.5 + i * 0.04, 1 + i * 0.05));
  list.push(...typedClicks("Opener", OPENER.lineB));
  add("Opener", OPENER.black, "cut", 0.8);
  list.push(...typedClicks("Opener", OPENER.lineC, 0.4));
  add("Opener", OPENER.morph + 30, "whoosh", 0.7);

  WAYS.cards.forEach((f, i) => add("Ways", f, "pop", 0.45, 1 + i * 0.08));
  add("Ways", WAYS.close, "close", 0.8);
  add("Ways", WAYS.minimize, "minimize", 0.8);
  add("Ways", WAYS.shade, "click", 0.9);
  add("Ways", WAYS.shade + 8, "click", 0.9);
  add("Ways", WAYS.shade + 10, "rollUp", 0.9);
  add("Ways", WAYS.focus, "whoosh", 0.5);

  DOUBLE.clicks.forEach((f) => add("DoubleClick", f, "click"));
  add("DoubleClick", DOUBLE.roll, "rollUp");
  DOUBLE.clicksBack.forEach((f) => add("DoubleClick", f, "click"));
  add("DoubleClick", DOUBLE.unroll, "rollDown");

  HISTORY.rows.forEach((f, i) => add("History", f, "thock", 0.8, [0.8, 0.9, 0.7, 1.2][i]));
  add("History", HISTORY.focus, "whoosh", 0.5);

  add("Glance", GLANCE.open, "glanceOpen");
  add("Glance", GLANCE.leave + 5, "glanceClose", 0.7);

  list.push(...typedClicks("Gestures", GESTURES.line, 0.4));
  add("Gestures", GESTURES.desk, "whoosh", 0.6);
  for (const g of [GESTURES.shade, GESTURES.expand, GESTURES.fill, GESTURES.left, GESTURES.right]) {
    add("Gestures", g.down, "touch", 0.5);
    add("Gestures", g.release - 12, "arm", 0.9);
  }
  add("Gestures", GESTURES.shade.release, "rollUp", 0.8);
  add("Gestures", GESTURES.expand.release, "rollDown", 0.8);
  add("Gestures", GESTURES.fill.release, "whoosh", 0.45);
  add("Gestures", GESTURES.left.release, "whoosh", 0.4);
  add("Gestures", GESTURES.right.release, "whoosh", 0.4);
  add("Gestures", GESTURES.cancel.down, "touch", 0.5);
  add("Gestures", GESTURES.cancel.back, "cancel", 0.6);
  add("Gestures", GESTURES.wheel.swap, "pop", 0.5);
  GESTURES.wheel.notches.forEach((f, i) => add("Gestures", f, "notch", 0.9, 1 + i * 0.1));
  add("Gestures", GESTURES.wheel.notches[2] + 1, "arm", 0.9);
  add("Gestures", GESTURES.wheel.commit, "whoosh", 0.45);

  MORE.cards.forEach((f, i) => add("More", f, "pop", 0.5, 1 + i * 0.08));
  MORE.keys.forEach((f) => {
    add("More", f, "keycap", 0.9);
    add("More", f + 6, "keycap", 0.8, 1.1);
    add("More", f + 12, "keycap", 0.8, 0.95);
  });

  add("End", END.icon, "chime", 0.9);
  add("End", END.cta, "pop", 0.4, 1.3);
  return list.sort((a, b) => a.at - b.at);
};
