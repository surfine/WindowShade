export const FPS:number;export const TOTAL:number;
export const CHAPTERS:{id:number;start:number;duration:number;title:string;holds:number[][];shape:string;color:string;kind:string}[];
export function camera(frame:number):number;
export function sceneSVG(frame:number,options?:{portrait?:boolean;placeholders?:boolean;notch?:boolean;onlyNotch?:boolean}):string;
export function footageSlots(frame:number):{id:string;label:string;x:number;y:number;w:number;h:number}[];
export function chapterAt(frame:number):typeof CHAPTERS[number];
export function heldLocal(c:typeof CHAPTERS[number],local:number):number;
export function ease(value:number):number;
export function frozenLocal(c:typeof CHAPTERS[number],local:number):number;
