// 未来版单独的入口：只打包这一部，渲染时不受同一个工程里其它片子半成品的影响。
import { registerRoot } from 'remotion';
import { FutureCompositions } from './compositions';

registerRoot(FutureCompositions);
