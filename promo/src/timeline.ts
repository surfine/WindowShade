// One cue sheet for picture and sound. Scenes read their local frames from here, and
// scripts/audio.ts reads the same numbers to place the music, sound effects and typing clicks.
// Plain data only: no imports, so Node can run the audio script straight from this file.

export const FPS = 60;
export const BEAT = 30; // 120 bpm
export const BAR = BEAT * 4;
export const WIDTH = 1920;
export const HEIGHT = 1080;

export const SCENES = [
  { id: "Opener", bars: 4 },
  { id: "Ways", bars: 4 },
  { id: "DoubleClick", bars: 3 },
  { id: "History", bars: 3 },
  { id: "Glance", bars: 3 },
  { id: "Gestures", bars: 8 },
  { id: "More", bars: 3 },
  { id: "End", bars: 3 },
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
  lineA: { at: 12, text: "窗口一多，", rate: 5 } as Typed,
  pile: [60, 75, 90, 100, 110, 118, 126, 134, 142],
  lineB: { at: 150, text: "桌面就满了。", rate: 5 } as Typed,
  black: 240,
  lineC: { at: 256, text: "先别急着关。", rate: 6 } as Typed,
  morph: 420, // caret becomes a bar, the bar opens into the next scene
};

export const WAYS = {
  cards: [8, 16, 24],
  close: 90,
  minimize: 180,
  shade: 270,
  focus: 360,
};

export const DOUBLE = {
  clicks: [60, 70],
  roll: 74,
  swap: 180,
  clicksBack: [186, 196],
  unroll: 200,
};

export const HISTORY = {
  rows: [60, 90, 120, 150],
  focus: 240,
};

export const GLANCE = {
  arrive: 60,
  open: 73, // the card appears 0.22 s after the pointer stops
  second: 200,
  leave: 285,
};

// Gestures: one bar of black title, then the desk.
export const GESTURES = {
  line: { at: 10, text: "在标题栏上，用两根手指。", rate: 4 } as Typed,
  desk: 120,
  // [fingers down, release]; progress runs between them
  shade: { down: 150, release: 222 },
  expand: { down: 270, release: 330 },
  fill: { down: 380, release: 440 },
  left: { down: 520, release: 575 },
  right: { down: 620, release: 675 },
  cancel: { down: 740, peak: 790, back: 830 },
  wheel: { swap: 855, notches: [880, 895, 910], commit: 920 },
};

export const MORE = {
  cards: [30, 60, 90],
  keys: [130, 190, 250],
};

export const END = {
  icon: 6,
  word: 40,
  tagline: 90,
  cta: 150,
  facts: 180,
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
  const add = (scene: SceneId, at: number, kind: string, gain = 1, pitch = 1) =>
    list.push({ at: s(scene) + at, kind, gain, pitch });

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
