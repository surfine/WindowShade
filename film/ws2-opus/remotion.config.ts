import path from 'node:path';
import { Config } from '@remotion/cli/config';

Config.setVideoImageFormat('jpeg');
Config.setOverwriteOutput(true);
Config.setConcurrency(4);
Config.setChromiumOpenGlRenderer('angle');

// three / fiber 裝在 vendor，避免寫進主倉庫那份 symlink 的 node_modules。
const vendor = path.resolve(process.cwd(), 'vendor/node_modules');
Config.overrideWebpackConfig((current) => ({
  ...current,
  resolve: {
    ...current.resolve,
    modules: [vendor, ...(current.resolve?.modules ?? ['node_modules'])],
  },
}));
