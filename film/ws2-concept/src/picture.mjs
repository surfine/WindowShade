// Original WS2 composition. See shot-source-map.json for narrowly adapted motion formulas.
// This pure renderer is shared by the Remotion wrapper and the offline animatic runner.
export const FPS=60, TOTAL=7560;
export const CHAPTERS=[{"id": 0, "title": "开盖，认出你", "start": 0, "duration": 840, "holds": [[0, 60], [360, 420], [660, 780]], "shape": "expanded", "color": "#FFF4E0", "kind": "unlock"}, {"id": 1, "title": "刘海，活了", "start": 840, "duration": 960, "holds": [[180, 270], [420, 510], [660, 750]], "shape": "alert", "color": "#5FD38A", "kind": "footage"}, {"id": 2, "title": "看不见的，都在这里", "start": 1800, "duration": 1080, "holds": [[180, 240], [450, 510], [720, 780], [840, 960]], "shape": "expanded", "color": "#FFFFFF", "kind": "footage"}, {"id": 3, "title": "点一下，所有 App", "start": 2880, "duration": 960, "holds": [[180, 270], [420, 510], [660, 780]], "shape": "compact", "color": "#FFFFFF", "kind": "footage"}, {"id": 4, "title": "任何输入，同一套动作", "start": 3840, "duration": 600, "holds": [[120, 180], [330, 390], [450, 510]], "shape": "compact", "color": "#FFFFFF", "kind": "input"}, {"id": 5, "title": "画一笔，说一句", "start": 4440, "duration": 1440, "holds": [[180, 240], [480, 570], [780, 870], [1080, 1170], [1260, 1350]], "shape": "expanded", "color": "#E98BB2", "kind": "conduct"}, {"id": 6, "title": "长按，换一种用法", "start": 5880, "duration": 720, "holds": [[120, 180], [390, 510], [570, 630]], "shape": "expanded", "color": "#4AA3FF", "kind": "road"}, {"id": 7, "title": "专注时安静，走开就锁", "start": 6600, "duration": 360, "holds": [[90, 150], [240, 300]], "shape": "compact", "color": "#FF6B5E", "kind": "focus"}, {"id": 8, "title": "WindowShade 2", "start": 6960, "duration": 600, "holds": [[240, 420], [480, 600]], "shape": "quiet", "color": "#FFFFFF", "kind": "outro"}];
export const clamp=(x,a=0,b=1)=>Math.max(a,Math.min(b,x));
export const ease=(x)=>{x=clamp(x);return x<.5?4*x*x*x:1-Math.pow(-2*x+2,3)/2;};
export const lerp=(a,b,t)=>a+(b-a)*t;
export function spring(f,s,r=.4,d=.92){const t=Math.max(0,(f-s)/60),w=2*Math.PI/r;if(d>=1)return 1-(1+w*t)*Math.exp(-w*t);const wd=w*Math.sqrt(1-d*d);return 1-Math.exp(-d*w*t)*(Math.cos(wd*t)+d*w/wd*Math.sin(wd*t));}
export function chapterAt(frame){return CHAPTERS.find(c=>frame>=c.start&&frame<c.start+c.duration)??CHAPTERS[8];}
export function frozenLocal(c,local){let removed=0;for(const [a,b]of c.holds){if(local>=b)removed+=b-a;else if(local>=a){removed+=local-a;break;}}return local-removed;}
export function heldLocal(c,l){for(const [a,b]of c.holds)if(l>=a&&l<b)return a;return l;}
const esc=(s)=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
const text=(s,x,y,size=56,color='#F4F4F6',extra='')=>`<text x="${x}" y="${y}" text-anchor="middle" font-size="${size}" fill="${color}" ${extra}>${esc(s)}</text>`;
const rect=(x,y,w,h,r=24,fill='#151922',extra='')=>`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${fill}" ${extra}/>`;
const circle=(x,y,r,color,w=3,extra='')=>`<circle cx="${x}" cy="${y}" r="${r}" fill="none" stroke="${color}" stroke-width="${w}" ${extra}/>`;
export const SHAPES={quiet:[195,58,18],compact:[480,58,18],alert:[545,102,28],expanded:[820,260,40]};
// Every boundary closes to the same quiet contour; the next chapter opens from identical values.
export function notchGeometry(frame){const c=chapterAt(frame),l=clamp(frame-c.start,0,c.duration-1),target=SHAPES[c.shape];const t=frozenLocal(c,l);const tail=c.duration-heldLocal(c,l);const open=spring(t,12,.40,.92);const shut=tail<=1?0:1-spring(Math.max(0,48-tail),0,.34,1);const p=Math.min(clamp(open),shut);return SHAPES.quiet.map((v,i)=>lerp(v,target[i],p));}
export function notchSVG(frame){const c=chapterAt(frame),[w,h,r]=notchGeometry(frame),f=frozenLocal(c,frame-c.start);let inside='';
 if(c.id===0&&f>190){let a=clamp((f-190)/110),b=clamp((f-330)/90);inside=circle(905,185,25,c.color,3,`opacity="${a}"`)+circle(1015,185,25,b>.99?'#5FD38A':'#687078',3)+`<path d="M 941 185 L 980 185" stroke="#687078" stroke-width="2"/>`;}
 else if(c.id===5){const p=ease((f-50)/110);inside=`<path d="M 905 162 L 951 205 L 1020 139" pathLength="1" stroke-dasharray="1" stroke-dashoffset="${1-p}" stroke="${c.color}" stroke-width="4" fill="none" stroke-linecap="round"/>`;}
 else if(c.id===7){inside=circle(960,145,18,c.color,3);}
 else if(c.id!==8){inside=circle(960,145,6,c.color,2);}
 return `<g id="shared-notch">${rect(960-w/2,108,w,h,r,'#000',`stroke="#3B3D42" stroke-width=".8"`)}<g opacity="${ease((w-195)/100)}">${inside}</g></g>`;
}
const panel=(x,y,w,h,title)=>rect(x,y,w,h,26,'#171C24','stroke="#383F49" stroke-width="1.5"')+text('真机画面待录',x+w/2,y+h/2-18,Math.min(38,w/12),'#B9C1CD')+text(title,x+w/2,y+h/2+43,Math.min(32,w/14),'#7D8797');
export function footageSlots(frame){const c=chapterAt(frame),l=heldLocal(c,frame-c.start);
 const one=(id,label)=>[{id,label,x:330,y:330,w:1260,h:490}];
 if(c.id===1)return one(l<360?'N1-music.mov':l<660?'N2-airpods.mov':'N3-mouse-battery.mov',l<360?'音乐':l<660?'AirPods':'妙控外设电量');
 if(c.id===2){if(l<660){const ids=['A1-flick-into-notch.mov','A2-hover-row.mov','A3-glance.mov','A4-put-back.mov'];const labels=['甩进刘海','那一排','看一眼','放回'];const i=Math.min(3,Math.floor(l/165));return one(ids[i],labels[i]);}return ['W1-slide-over.mov','W2-split-handle.mov','W3-pip.mov','W4-magic-tile.mov'].map((id,i)=>({id,label:['侧拉','分屏','画中画','魔法平铺'][i],x:350+(i%2)*620,y:335+Math.floor(i/2)*245,w:600,h:225}));}
 if(c.id===3)return one(l<330?'L1-launchpad.png':l<630?'L2-search-wwxb.png':'L3-drag-to-slide-over.mov',l<330?'启动台':l<630?'搜索 wwxb':'拖到侧拉');
 if(c.id===5&&l>=660&&l<1170)return ['T1-claude.mov','T2-codex.mov','T3-claude-push.mov'].map((id,i)=>({id,label:['Claude Code','Codex','审批后回执'][i],x:210+i*510,y:385+(i===1?-40:40),w:480,h:320}));
 return [];
}
function device(i,x,y,p){const color=i===5?'#E98BB2':'#D6DBE4';let body='';
 if(i===0)body=rect(-78,-47,156,94,12,'none',`stroke="${color}" stroke-width="3"`);
 else if(i===1||i===2)body=rect(-36,-59,72,118,34,'none',`stroke="${color}" stroke-width="3"`)+`<path d="M0 -58 V-9" stroke="${color}" stroke-width="3"/>`;
 else if(i===3)body=rect(-26,-85,52,170,22,'none',`stroke="${color}" stroke-width="3"`)+circle(0,-40,16,color,2)+circle(0,22,5,color,2);
 else if(i===4)body=`<path d="M-90 20 Q-85-65-42-38 L42-38 Q85-65 90 20 Q91 65 59 52 L32 18 H-32 L-59 52 Q-91 65-90 20Z" fill="none" stroke="${color}" stroke-width="3"/>`+circle(-35,-8,10,color,2)+circle(35,-8,10,color,2);
 else body=rect(-40,-80,80,160,17,'none',`stroke="${color}" stroke-width="3"`)+`<path d="M-13 65 H13" stroke="${color}" stroke-width="3"/>`;
 return `<g transform="translate(${x} ${y}) scale(${.93+.07*p})" opacity="${clamp(p)}">${body}</g>`;}
function unlock(f){const open=ease((f-60)/120);let s=`<g transform="translate(960 740) scale(1 ${Math.max(.015,open)}) translate(-960 -740)">${rect(260,300,1400,490,28,'none','stroke="#4D515A" stroke-width="1"')}</g>`;
 const glow=clamp((f-180)/45)*(1-clamp((f-435)/70));s+=`<g opacity="${glow}">${rect(275,311,1370,465,28,'none','stroke="#FFF4E0" stroke-width="4" filter="url(#bloom)"')}${rect(275,311,1370,465,28,'none','stroke="#FFF4E0" stroke-width="1.5"')}</g>`;
 const p=ease((f-260)/120);s+=`<g opacity="${p}">${circle(890,525,56,'#CFD3DD',3)}<path d="M810 675 Q810 593 890 593 Q970 593 970 675" fill="none" stroke="#CFD3DD" stroke-width="3"/>${device(5,1110,570,p)}</g>`;
 const done=ease((f-440)/90);s+=`<g opacity="${done}">${circle(960,548,138,'#5FD38A',2)}<path d="M918 547 L949 578 L1011 509" fill="none" stroke="#5FD38A" stroke-width="4"/></g>`;return s;}
function inputs(f){let s='';for(let i=0;i<6;i++){const p=clamp(spring(f,i*24+20,.42,.88));s+=device(i,390+i*228,530+65*(1-p),p);s+=circle(390+i*228,710,5,i===Math.min(5,Math.floor(f/42))?'#5FD38A':'#444D5A',2);}return s;}
function conduct(f,l){let s='';if(l<660){const p=ease((f-35)/110);s+=`<path d="M 630 440 L 895 680 L 1285 365" fill="none" stroke="#E98BB2" stroke-width="7" stroke-linecap="round" pathLength="1" stroke-dasharray="1" stroke-dashoffset="${1-p}"/>`;
 const beats=[270,300,330,375,405];for(let i=0;i<5;i++)s+=circle(810+i*75,785,9,f>=beats[i]?'#E98BB2':'#424650',4);
 if(f>425)s+=`<path d="${Array.from({length:40},(_,i)=>`${i?'L':'M'} ${595+i*18} ${557+Math.sin(i*1.2+f*.08)*Math.sin(i*.18)*40}`).join(' ')}" stroke="#E98BB2" stroke-width="2" fill="none"/>`;
 }else if(l>=1170){const p=ease((f-785)/65);s+=circle(960,560,150,'#FFB35C',2)+`<path d="M 905 560 L 949 604 L 1030 506" pathLength="1" stroke-dasharray="1" stroke-dashoffset="${1-p}" fill="none" stroke="#5FD38A" stroke-width="5"/>`;}
 return s;}
function road(f){const p=ease((f-45)/130)*(1-ease((f-380)/100));let s='';
 // CircleMatchIris origin is locked to the notch, radius 22→2100; cubic timing retained at 60fps.
 s+=`<g clip-path="url(#road-mask)">${rect(0,0,1920,1080,0,'#080D17')}`;
 for(let i=0;i<5;i++){const x=560+i*200;const dx=(i-2)*180;const path=`M ${x} 895 C ${x+dx} 690, ${960+dx*.35} 385, 960 295`;s+=`<path d="${path}" stroke="#4AA3FF" stroke-width="${i===2?4:1.2}" opacity="${i===2?.9:.35}" fill="none"/>`;}
 s+=circle(960,297,8,'#4AA3FF',3);s+='</g>';return `<defs><clipPath id="road-mask"><circle cx="960" cy="138" r="${lerp(22,2100,p)}"/></clipPath></defs>${s}`;}
function focus(f){let s='';const p=clamp(f/190);s+=circle(820,548,122,f<130?'#FF6B5E':'#5FD38A',3);s+=`<circle cx="820" cy="548" r="122" fill="none" stroke="#FF6B5E" stroke-width="9" pathLength="1" stroke-dasharray="1" stroke-dashoffset="${p}" transform="rotate(-90 820 548)"/>`;s+=device(5,1100+180*ease((f-125)/100),560,1);return s;}
function outro(f){let s='';const p=clamp(spring(f,12,.42,.88)),collapse=ease((f-110)/100);for(let i=0;i<8;i++){const a=i*Math.PI/4;const r=lerp(500,310,p)*(1-collapse);const x=960+Math.cos(a)*r,y=520+Math.sin(a)*r*.65;s+=circle(x,y,18,'#8D96A5',2,`opacity="${1-collapse}"`);}const word=clamp(spring(f,135,.38,1));s+=text('WindowShade 2',960,555+30*(1-word),104,'#F5F6FA',`font-weight="600" opacity="${word}"`);s+=text('一个入口，一套动作，任何输入',960,643,43,'#ABB3C0',`opacity="${word}"`);return s;}
export function camera(frame){const c=chapterAt(frame),l=frame-c.start,t=frozenLocal(c,l);const active=c.duration-c.holds.reduce((s,[a,b])=>s+b-a,0);const tail=ease((c.duration-1-heldLocal(c,l))/72);return 1+.025*ease(t/Math.max(1,active))*tail;}
export function sceneSVG(frame,{portrait=false,placeholders=true,notch=true,onlyNotch=false}={}){frame=clamp(Math.floor(frame),0,TOTAL-1);const c=chapterAt(frame),l=frame-c.start,f=frozenLocal(c,l);const width=portrait?1080:1920,height=portrait?1920:1080;
 const finalFade=c.id===8?1-clamp((l-420)/60):1;const viewLocal=heldLocal(c,l);const cover=Math.min(ease(viewLocal/54),ease((c.duration-1-viewLocal)/60));let scene='';
 if(c.id===0)scene=unlock(f);if(c.id===4)scene=inputs(f);if(c.id===5)scene=conduct(f,l);if(c.id===6)scene=road(f);if(c.id===7)scene=focus(f);if(c.id===8)scene=outro(f);
 if(placeholders)for(const q of footageSlots(frame))scene+=panel(q.x,q.y,q.w,q.h,q.label);
 const cam=camera(frame);const chapterTitle=c.id===8?'':text(c.title,960,940,60,'#F2F3F7','font-weight="500"');
 // Portrait has a dedicated title area: never shrink horizontal 56px text to 31.5px.
 const transform=portrait?'translate(-132 235) scale(.7)':`translate(960 110) scale(${cam}) translate(-960 -110)`;
 const inner=onlyNotch?notchSVG(frame):`<g transform="translate(960 140) scale(${cover}) translate(-960 -140)">${scene}${portrait?'':chapterTitle}</g>${notch?notchSVG(frame):''}`;
 return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" style="display:block;background:${onlyNotch?'transparent':'#0B0D12'};font-family:-apple-system,PingFang SC,Noto Sans CJK SC,sans-serif"><defs><filter id="bloom"><feGaussianBlur stdDeviation="11"/></filter></defs><g opacity="${finalFade}">${onlyNotch?'':rect(portrait?36:160,portrait?300:108,portrait?1008:1600,portrait?700:760,18,'none','stroke="#34383F" stroke-width="1"')}<g transform="${transform}">${inner}</g>${!onlyNotch&&portrait&&c.id!==8?text(c.title,540,1300,c.id===8?70:64,'#F2F3F7',`opacity="${cover}"`):''}${onlyNotch?'':text('概念演示 · 真机素材待录',width/2,portrait?1740:1040,portrait?34:26,'#7F8896')}</g></svg>`;
}
