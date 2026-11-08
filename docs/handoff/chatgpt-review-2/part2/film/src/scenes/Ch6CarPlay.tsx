import {useCurrentFrame} from 'remotion';
import {sceneSVG} from '../picture.mjs';
export const Ch6CarPlay=()=>{const frame=useCurrentFrame()+5880;return <div dangerouslySetInnerHTML={{__html:sceneSVG(frame,{notch:false})}}/>;};
