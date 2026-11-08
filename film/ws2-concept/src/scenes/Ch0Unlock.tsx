import {useCurrentFrame} from 'remotion';
import {sceneSVG} from '../picture.mjs';
export const Ch0Unlock=()=>{const frame=useCurrentFrame()+0;return <div dangerouslySetInnerHTML={{__html:sceneSVG(frame,{notch:false})}}/>;};
