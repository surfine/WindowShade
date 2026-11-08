import assert from 'node:assert/strict';
import {CHAPTERS,TOTAL,sceneSVG,notchGeometry,camera,frozenLocal} from '../src/picture.mjs';
let assertions=0;function check(v,m){assert.ok(v,m);assertions++;}
check(CHAPTERS.reduce((n,c)=>n+c.duration,0)===7560,'126 seconds at 60fps');
let at=0,holds=0;
for(const c of CHAPTERS){check(c.start===at,'no gap or overlap');at+=c.duration;check(c.holds.every(([a,b])=>a>=0&&b<=c.duration&&b>a),'valid hold range');for(const [a,b]of c.holds){holds+=b-a;check(frozenLocal(c,a)===frozenLocal(c,b-1),'element clock held');check(camera(c.start+a)===camera(c.start+b-1),'camera held');check(sceneSVG(c.start+a)===sceneSVG(c.start+b-1),'entire SVG held');check(sceneSVG(c.start+a,{portrait:true})===sceneSVG(c.start+b-1,{portrait:true}),'portrait entire SVG held');}}
check(holds/TOTAL>=.25,'>=25% scheduled true holds');
for(const c of CHAPTERS.slice(1)){check(JSON.stringify(notchGeometry(c.start-1))===JSON.stringify(notchGeometry(c.start)),'notch boundary exact');}
for(const f of [0,60,240,420,780,840,1230,1800,2400,2880,3480,3840,4260,4440,4800,5340,5880,6240,6600,6960,7260,7500,7559]){const a=sceneSVG(f),b=sceneSVG(f);check(a===b,'repeat seek deterministic');check(!/NaN|Infinity|undefined/.test(a),'finite SVG');}
console.log(JSON.stringify({status:'PASS',assertions,frames:TOTAL,seconds:TOTAL/60,scheduledHoldFrames:holds,scheduledHoldFraction:holds/TOTAL,warning:'Schedule tests are not pixel QA; real footage freezes must be checked again.'},null,2));
