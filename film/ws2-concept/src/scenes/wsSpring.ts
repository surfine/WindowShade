export const SPRINGS = {calm:[.34,1],settle:[.38,1],expand:[.40,.92],bloom:[.42,.84],catch:[.40,.80],glide:[.42,.88],flyOut:[.38,.90],pull:[.36,.86],pop:[.30,.75],reduced:[.25,1],dolly:[1.6,1]} as const;
export type SpringName = keyof typeof SPRINGS;
export function wsSpring(frame:number,start:number,response:number,damping:number,fps=60,v0=0):number {
  if (![frame,start,response,damping,fps,v0].every(Number.isFinite) || response<=0 || damping<=0 || fps<=0) throw new Error('Invalid spring');
  const t=Math.max(0,(frame-start)/fps), w=2*Math.PI/response;
  if(damping>=1)return 1-(1+(w-v0)*t)*Math.exp(-w*t);
  const wd=w*Math.sqrt(1-damping*damping);
  return 1-Math.exp(-damping*w*t)*(Math.cos(wd*t)+((damping*w-v0)/wd)*Math.sin(wd*t));
}
export const springNamed=(f:number,s:number,name:SpringName)=>{const [response,damping]=SPRINGS[name];return wsSpring(f,s,response,damping);};
