import {useCurrentFrame,useVideoConfig} from 'remotion';
import {sceneSVG} from '../picture.mjs';
export const Notch=()=>{const frame=useCurrentFrame();const {width,height}=useVideoConfig();return <div style={{position:'absolute',inset:0,pointerEvents:'none'}} dangerouslySetInnerHTML={{__html:sceneSVG(frame,{portrait:height>width,onlyNotch:true})}}/>;};
