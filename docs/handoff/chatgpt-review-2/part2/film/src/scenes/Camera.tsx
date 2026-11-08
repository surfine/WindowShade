import React from 'react';
import {camera} from '../picture.mjs';
export const Camera:React.FC<React.PropsWithChildren<{frame:number}>>=({frame,children})=><div style={{position:'absolute',inset:0,scale:camera(frame),transformOrigin:'50% 10.2%'}}>{children}</div>;
