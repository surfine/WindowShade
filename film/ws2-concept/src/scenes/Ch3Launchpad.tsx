import {useCurrentFrame} from 'remotion';
import {sceneSVG} from '../picture.mjs';
export const Ch3Launchpad=()=>{const frame=useCurrentFrame()+2880;return <div dangerouslySetInnerHTML={{__html:sceneSVG(frame,{notch:false})}}/>;};
