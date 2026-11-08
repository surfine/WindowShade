import {interpolate, spring} from 'remotion';

// motion-direction §2.2。mass 1，stiffness = (2π/response)²，damping = 4πζ/response。
export const springOf = (response: number, zeta: number) => ({
  mass: 1,
  stiffness: (2 * Math.PI / response) ** 2,
  damping: (4 * Math.PI * zeta) / response,
});

export const SPRING = {
  calm: springOf(0.34, 1),
  settle: springOf(0.38, 1),
  expand: springOf(0.4, 0.92),
  bloom: springOf(0.42, 0.84),
  catch: springOf(0.4, 0.8),
  glide: springOf(0.42, 0.88),
  flyOut: springOf(0.38, 0.9),
  pull: springOf(0.36, 0.86),
  pop: springOf(0.3, 0.75),
  dolly: springOf(1.6, 1),
} as const;

const clamp = {
  extrapolateLeft: 'clamp' as const,
  extrapolateRight: 'clamp' as const,
};

export const play = (
  frame: number,
  fps: number,
  at: number,
  config: {mass: number; stiffness: number; damping: number},
) => spring({frame, fps, delay: at, config});

export const ramp = (frame: number, start: number, seconds: number, fps: number) =>
  interpolate(
    frame,
    [start, start + Math.max(1, Math.round(seconds * fps))],
    [0, 1],
    clamp,
  );

/** calm 被踢一腳初速度。峰值約在 0.05 秒，返回 0–1。 */
export const impulse = (frame: number, fps: number, at: number) => {
  const t = (frame - at) / fps;
  if (t <= 0) return 0;
  const w = (2 * Math.PI) / 0.34;
  return Math.min(1, t * w * Math.E * Math.exp(-w * t));
};
