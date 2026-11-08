import {useCurrentFrame} from 'remotion';
import {sceneSVG} from '../picture.mjs';
export const Ch5Conduct=()=>{const frame=useCurrentFrame()+4440;return <div dangerouslySetInnerHTML={{__html:sceneSVG(frame,{notch:false})}}/>;};
