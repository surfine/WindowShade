import {Series,useCurrentFrame,useVideoConfig} from 'remotion';
import {Stage} from './scenes/Stage';
import {Notch} from './scenes/Notch';
import {Footage} from './scenes/Footage';
import {CHAPTERS,chapterAt,sceneSVG,footageSlots,camera,ease,heldLocal,frozenLocal} from './picture.mjs';
export const FILM_FRAMES=7560;
function clipStart(id:string,chapterStart:number,frame:number){
  // Derive slot entry from the same deterministic registry used by the picture renderer.
  let start=frame;
  while(start>chapterStart && footageSlots(start-1).some(q=>q.id===id))start--;
  return start;
}
function Chapter({start}:{start:number}){
  const local=useCurrentFrame(),frame=start+local;
  const{width,height}=useVideoConfig();const portrait=height>width,c=chapterAt(frame);
  const held=heldLocal(c,local),cover=Math.min(ease(held/54),ease((c.duration-1-held)/60));
  const outer=portrait?'translate(-132px,235px) scale(.7)':`translate(960px,110px) scale(${camera(frame)}) translate(-960px,-110px)`;
  return <><div style={{position:'absolute',inset:0}} dangerouslySetInnerHTML={{__html:sceneSVG(frame,{portrait,notch:false})}}/>
    <div style={{position:'absolute',width:1920,height:1080,left:0,top:0,transform:outer,transformOrigin:'0 0'}}>
      <div style={{position:'absolute',inset:0,transform:`translate(960px,140px) scale(${cover}) translate(-960px,-140px)`,transformOrigin:'0 0'}}>
        {footageSlots(frame).map(q=><Footage key={q.id} {...q} frame={Math.max(0,frozenLocal(c,local)-frozenLocal(c,clipStart(q.id,start,frame)-start))}/>)}</div></div></>;
}
export const Film=()=><Stage><Series>{CHAPTERS.map(c=><Series.Sequence key={c.id} durationInFrames={c.duration}><Chapter start={c.start}/></Series.Sequence>)}</Series><Notch/></Stage>;
