"""Render the shared pure picture.mjs with Chromium, not the Remotion runtime.
The result is a muted, placeholder animatic. This does not validate Remotion APIs.
"""
from pathlib import Path
import argparse, subprocess, json, time, re
from playwright.sync_api import sync_playwright
p=argparse.ArgumentParser();p.add_argument('--portrait',action='store_true');p.add_argument('--still',type=int);p.add_argument('--fps',type=int,default=24);p.add_argument('--out',required=True);p.add_argument('--scale',type=float,default=.5);a=p.parse_args()
root=Path(__file__).resolve().parents[1];out=Path(a.out);out.parent.mkdir(parents=True,exist_ok=True)
w,h=(1080,1920)if a.portrait else(1920,1080);w,h=int(w*a.scale),int(h*a.scale)
js=(root/'src/picture.mjs').read_text().replace('export ','')
js+='\nwindow.draw=(f)=>{document.body.innerHTML=sceneSVG(f,{portrait:'+str(a.portrait).lower()+'});};'
with sync_playwright() as pw:
 browser=pw.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox','--disable-dev-shm-usage'])
 page=browser.new_page(viewport={'width':w,'height':h},device_scale_factor=1)
 page.set_content('<style>html,body{margin:0;overflow:hidden;background:#0b0d12}svg{width:100%;height:100%}</style>')
 page.add_script_tag(content=js)
 def frame(f):
  page.evaluate('(f)=>window.draw(f)',f)
  return page.screenshot(type='png',animations='disabled')
 if a.still is not None:out.write_bytes(frame(a.still));print('STILL',a.still,out)
 else:
  cmd=['ffmpeg','-y','-hide_banner','-loglevel','error','-f','image2pipe','-vcodec','png','-r',str(a.fps),'-i','pipe:0','-an','-c:v','libx264','-preset','veryfast','-crf','22','-pix_fmt','yuv420p','-movflags','+faststart',str(out)]
  proc=subprocess.Popen(cmd,stdin=subprocess.PIPE)
  count=126*a.fps
  for i in range(count):
   proc.stdin.write(frame(i*60/a.fps))
   if i%a.fps==0:print(json.dumps({'second':i//a.fps,'frames':i,'total':count}),flush=True)
  proc.stdin.close();code=proc.wait();assert code==0,code
  print('PASS OFFLINE ANIMATIC',out,'frames',count,flush=True)
 browser.close()
