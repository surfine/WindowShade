import React from 'react';
import {AbsoluteFill} from 'remotion';
export const Stage:React.FC<React.PropsWithChildren> = ({children})=><AbsoluteFill style={{background:'#0B0D12',overflow:'hidden',fontFamily:'-apple-system,"PingFang SC",sans-serif'}}>{children}</AbsoluteFill>;
