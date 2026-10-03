import { AbsoluteFill } from 'remotion';

// 全片 126 秒，60 fps。各章由 src/scenes/ 下的组件组成，时间表见 BRIEF.md。
export const FILM_FRAMES = 126 * 60;

export const Film = () => <AbsoluteFill style={{ background: '#0B0D12' }} />;
