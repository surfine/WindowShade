import {Freeze,Img,OffthreadVideo,staticFile} from 'remotion';
import registry from '../../public/footage/capture-registry.json';
import manifest from '../../public/footage/manifest.json';
type Entry={approved:boolean;kind:string;sourceInFrames:number;sourceFrames:number;license:string;sha256:string|null;containsSecrets:boolean|null;reviewer:string|null};
export function Footage({id,frame,x,y,w,h}:{id:string;frame:number;x:number;y:number;w:number;h:number}){
  const row=(registry as Record<string,Entry>)[id];
  const ready=(manifest as Record<string,boolean>)[id]===true && row?.approved===true && row.containsSecrets===false && !!row.reviewer && !!row.sha256 && row.sourceFrames>0 && row.sourceInFrames>=0;
  if(!ready)return null;
  const style={width:w,height:h,objectFit:'contain' as const,background:'#0B0D12'};
  const videoFrame=Math.max(0,Math.min(frame,row.sourceFrames-1));
  return <div style={{position:'absolute',left:x,top:y,width:w,height:h,overflow:'hidden',borderRadius:26}}>{row.kind==='image'?<Img src={staticFile('footage/'+id)} style={style}/>:<Freeze frame={videoFrame}><OffthreadVideo muted src={staticFile('footage/'+id)} trimBefore={row.sourceInFrames} style={style}/></Freeze>}</div>;
}
