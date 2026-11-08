import { Config } from '@remotion/cli/config';

Config.setVideoImageFormat('jpeg');
Config.setOverwriteOutput(true);
Config.setConcurrency(4);
// GPU 路径：ANGLE（Metal）画 three.js；编码在渲染命令里用 --hardware-acceleration=required（VideoToolbox）。
Config.setChromiumOpenGlRenderer('angle');
