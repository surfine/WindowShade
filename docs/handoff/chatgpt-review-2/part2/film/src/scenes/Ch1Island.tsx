import {useCurrentFrame} from 'remotion';
import {sceneSVG} from '../picture.mjs';
export const Ch1Island=()=>{const frame=useCurrentFrame()+840;return <div dangerouslySetInnerHTML={{__html:sceneSVG(frame,{notch:false})}}/>;};
