(() => {
 const en = document.documentElement.lang === 'en';
 const pixelSurfaces=[...document.querySelectorAll('.titlebar-archive,.retro-panel,.gesture-window,.platinum-window')];
 function alignEraPixels() {
  for (const surface of pixelSurfaces) {
   surface.style.setProperty('--era-pixel-offset','0px');
   const y=surface.getBoundingClientRect().top+window.scrollY;
   surface.style.setProperty('--era-pixel-offset', `${Math.round(y)-y}px`);
  }
 }
 document.fonts.ready.then(alignEraPixels);
 window.addEventListener('resize',alignEraPixels);
 const pixelResize=new ResizeObserver(alignEraPixels);
 pixelSurfaces.forEach(surface=>pixelResize.observe(surface));
 const t = (zh, eng) => en ? eng : zh;
 const $ = id => document.getElementById(id);
 const pressed = (selector, active) => document.querySelectorAll(selector).forEach(b => b.setAttribute('aria-pressed', String(b === active)));
 const spaceText = {
  open:t('让参考资料让开，看看草稿。','Move the reference aside to see the draft.'),
  shade:t('内容让开了，标题与位置还在。点标题栏，原地回来。','The contents step aside. The title and place remain. Click the bar to return.'),
  minimize:t('入口到了底部。要回来，得把目光也移过去。','The return point moves to the bottom. Your attention has to follow it there.'),
  overview:t('两扇窗口一起出现；布局暂时改变，便于挑选。点参考标题栏结束总览。','Both windows become visible in a temporary arrangement. Click the reference bar to leave overview.')
 };
 function arrange(mode) {
  $('space-desk').dataset.mode = mode;
  document.querySelectorAll('[data-arrange]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.arrange === mode)));
  $('space-content').setAttribute('aria-hidden', String(mode === 'shade' || mode === 'minimize'));
  $('space-bar').setAttribute('aria-expanded', String(mode !== 'shade' && mode !== 'minimize'));
  $('space-window').inert = mode === 'minimize';
  $('dock-target').hidden = mode !== 'minimize';
  $('space-result').textContent = spaceText[mode];
 }
 document.querySelectorAll('[data-arrange]').forEach(b => b.addEventListener('click', () => arrange(b.dataset.arrange)));
 $('space-reset').addEventListener('click', () => arrange('open'));
 $('space-bar').addEventListener('click', () => arrange($('space-desk').dataset.mode === 'open' ? 'shade' : 'open'));
 $('dock-target').addEventListener('click', () => { arrange('open'); $('space-bar').focus({preventScroll:true}); });
 let audioContext;
 function sound(folded) {
  if (!$('history-sound').checked) return;
  try {
   audioContext ||= new (window.AudioContext || window.webkitAudioContext)();
   audioContext.resume().catch(()=>{});
   const oscillator=audioContext.createOscillator(), gain=audioContext.createGain(), time=audioContext.currentTime;
   oscillator.type='triangle'; oscillator.frequency.setValueAtTime(folded?440:220,time); oscillator.frequency.exponentialRampToValueAtTime(folded?220:440,time+.12);
   gain.gain.setValueAtTime(.0001,time);gain.gain.exponentialRampToValueAtTime(.05,time+.015);gain.gain.exponentialRampToValueAtTime(.0001,time+.15);
   oscillator.connect(gain);gain.connect(audioContext.destination);oscillator.start();oscillator.stop(time+.16);
  } catch {}
 }
 const form = $('preference-form');
 let clickCount=0, clickTimer, gestureFolded=false;
 const getPreference = () => ({ count:Number(new FormData(form).get('clicks')), modifiers:new FormData(form).getAll('modifier') });
 function preferenceMessage() {
  const {count, modifiers}=getPreference();
  const names={meta:'⌘',alt:'Option',ctrl:'Control'};
  return count===0?t('已关闭。点击标题栏不会折叠。','Off. Title-bar clicks will not collapse the window.'):
   t(`当前：${modifiers.length ? '按住 '+modifiers.map(k=>names[k]).join(' + ')+'，':''}连续点击 ${count} 次。`,`Current: ${modifiers.length ? 'hold '+modifiers.map(k=>names[k]).join(' + ')+' and ':''}click ${count} times in succession.`);
 }
 function toggleGesture() {
  gestureFolded=!gestureFolded;
  $('gesture-window').classList.toggle('folded',gestureFolded);
  $('gesture-bar').setAttribute('aria-expanded',String(!gestureFolded));
  $('gesture-content').setAttribute('aria-hidden',String(gestureFolded));
  $('gesture-status').textContent=t(gestureFolded?'收起了。再用同样的节奏展开。':'展开了，还是原来的位置。',gestureFolded?'Rolled up. Repeat the rhythm to expand.':'Expanded, in the same place.');
  sound(gestureFolded);
 }
 form.addEventListener('submit',e=>e.preventDefault());
 form.addEventListener('change',()=>{clearTimeout(clickTimer);clickCount=0;$('gesture-status').textContent=preferenceMessage();});
 $('gesture-bar').addEventListener('click',e=>{
  const {count,modifiers}=getPreference();
  if(!count){$('gesture-status').textContent=preferenceMessage();return;}
  // Keyboard activation is one semantic action, not a timed mouse click.
  if(e.detail===0){toggleGesture();return;}
  if(!modifiers.every(m=>e[`${m}Key`])){clickCount=0;$('gesture-status').textContent=preferenceMessage();return;}
  clearTimeout(clickTimer);clickCount++;
  if(clickCount>=count){clickCount=0;toggleGesture();return;}
  $('gesture-status').textContent=t(`已点 ${clickCount} / ${count} 次……`,`${clickCount} / ${count} clicks…`);
  clickTimer=setTimeout(()=>{clickCount=0;$('gesture-status').textContent=t('这次还没触发。','Not triggered this time. ')+preferenceMessage();},650);
 });
 $('gesture-simulate').addEventListener('click',()=>{clearTimeout(clickTimer);clickCount=0;if(getPreference().count)toggleGesture();else $('gesture-status').textContent=preferenceMessage();});
 const platinumDesk=$('platinum-desk'),platinumWindow=$('platinum-window'),platinumBar=$('platinum-bar');
 let platinumFolded=false,drag=null,dragMoved=false;
 const platinumSay=text=>{$('platinum-result').textContent=text;};
 const movedText=()=>t(platinumFolded?'标题栏到了新位置。双击标题栏（或点方框）展开，看内容出现在哪里。':'窗口跟着标题栏一起移动。',platinumFolded?'The title bar is somewhere new. Double-click it (or click the box) and see where the contents appear.':'The window moves with its title bar.');
 let platinumX=null,platinumY=null;
 function platinumOffset(){
  if(platinumX===null){
   const desk=platinumDesk.getBoundingClientRect(),win=platinumWindow.getBoundingClientRect();
   platinumX=win.left-desk.left;platinumY=win.top-desk.top;
  }
  return {x:platinumX,y:platinumY};
 }
 // The bar may travel past the lower edge, as a collapsed window could.
 function placePlatinum(x,y){
  const desk=platinumDesk.getBoundingClientRect(),win=platinumWindow.getBoundingClientRect();
  const limit=(value,max)=>Math.min(Math.max(value,0),Math.max(0,max));
  platinumX=limit(x,desk.width-win.width);platinumY=limit(y,desk.height-platinumBar.offsetHeight);
  platinumWindow.style.setProperty('--drag-x',`${Math.round(platinumX)}px`);
  platinumWindow.style.setProperty('--drag-y',`${Math.round(platinumY)}px`);
 }
 function togglePlatinum(){
  platinumFolded=!platinumFolded;platinumWindow.classList.toggle('folded',platinumFolded);
  $('platinum-collapse').setAttribute('aria-expanded',String(!platinumFolded));
  $('platinum-content').setAttribute('aria-hidden',String(platinumFolded));
  platinumSay(t(platinumFolded?'只剩标题栏。把它拖到别处，再双击一次（或点方框）展开。':'内容在标题栏现在的位置展开。',platinumFolded?'Only the title bar is left. Drag it somewhere else, then double-click it (or click the box) to expand.':'The contents open where the title bar now is.'));
 }
 $('platinum-collapse').addEventListener('click',togglePlatinum);
 // 1997 年的手势本身就是双击标题栏；拖动过的这一次不算双击。
 platinumBar.addEventListener('dblclick',()=>{if(!dragMoved)togglePlatinum();});
 platinumBar.addEventListener('pointerdown',e=>{
  if(e.target.closest('button'))return;
  const at=platinumOffset();
  drag={id:e.pointerId,x:e.clientX-at.x,y:e.clientY-at.y,sx:e.clientX,sy:e.clientY};dragMoved=false;
  platinumBar.setPointerCapture(e.pointerId);platinumWindow.classList.add('dragging');e.preventDefault();
 });
 platinumBar.addEventListener('pointermove',e=>{if(!drag||e.pointerId!==drag.id)return;if(Math.abs(e.clientX-drag.sx)>4||Math.abs(e.clientY-drag.sy)>4)dragMoved=true;placePlatinum(e.clientX-drag.x,e.clientY-drag.y);});
 for(const end of ['pointerup','pointercancel'])platinumBar.addEventListener(end,e=>{
  if(!drag||e.pointerId!==drag.id)return;
  drag=null;platinumWindow.classList.remove('dragging');if(dragMoved)platinumSay(movedText());
 });
 platinumBar.addEventListener('keydown',e=>{
  if(e.key==='Enter'||e.key===' '){e.preventDefault();togglePlatinum();return;}
  const step={ArrowLeft:[-12,0],ArrowRight:[12,0],ArrowUp:[0,-12],ArrowDown:[0,12]}[e.key];
  if(!step)return;
  e.preventDefault();
  const at=platinumOffset();placePlatinum(at.x+step[0],at.y+step[1]);platinumSay(movedText());
 });
 let stickyFolded=false;
 function toggleSticky(){stickyFolded=!stickyFolded;$('sticky-note').classList.toggle('folded',stickyFolded);$('sticky-bar').setAttribute('aria-expanded',String(!stickyFolded));$('sticky-content').setAttribute('aria-hidden',String(stickyFolded));$('sticky-toggle').textContent=t(stickyFolded?'展开这张便笺 ↕':'试着收起这张便笺 ↕',stickyFolded?'Expand this note ↕':'Collapse this note ↕');}
 $('sticky-toggle').addEventListener('click',toggleSticky);
 $('sticky-bar').addEventListener('dblclick',toggleSticky);
 $('sticky-bar').addEventListener('click',e=>{if(e.detail===0)toggleSticky();});
 const machineSize = new ResizeObserver(() => {
  const screen=$('machine-screen');
  screen.style.setProperty('--machine-scale', String(Math.min(screen.clientWidth/640,screen.clientHeight/480)));
 });
 machineSize.observe($('machine-screen'));
 const machines=[
  {name:'System 7.5',year:1994,tasks:[t('打开 Apple 菜单 → Control Panels → WindowShade。','Open Apple menu → Control Panels → WindowShade.'),t('选择 2 次点击，然后双击另一个窗口的标题栏。','Choose two clicks, then double-click another window’s title bar.'),t('改为 3 次点击，感受同一个动作的不同节奏。','Switch to three clicks and feel the change of rhythm.')]},
  {name:'Mac OS 8.0',year:1997,tasks:[t('打开磁盘上的文件夹，看看标题栏最右边的按钮。','Open a folder on the disk and inspect the rightmost title-bar button.'),t('点 collapse box，把窗口收起。','Click the collapse box to roll the window up.'),t('拖动留下的标题栏，再点按钮展开，检查新位置。','Drag the remaining title bar, then expand and check its new location.')]},
  {name:'Mac OS X 10.1',year:2001,tasks:[t('等待 OS X 启动，打开一个 Finder 窗口。','Let OS X boot, then open a Finder window.'),t('点标题栏的黄色按钮，观察窗口去了哪里。','Click the yellow title-bar button and watch where the window goes.'),t('从 Dock 恢复窗口。与前面两台系统比较。','Restore the window from the Dock. Compare it with the other systems.')]}
 ];
 let current=0, iframe=null, loadTimer, loaded=false;
 const done=new Set();
 function stopMachine(notify=true){
  clearTimeout(loadTimer);iframe?.remove();iframe=null;loaded=false;
  $('machine-placeholder').hidden=false;$('machine-stop').hidden=true;$('power-light').classList.remove('on');
  if(notify)$('machine-status').textContent=t('模拟器已关闭，运行资源已释放。可以重新启动。','Emulator closed and its running resources released. You can start again.');
 }
 document.querySelectorAll('[data-machine]').forEach(b=>b.addEventListener('click',()=>{
  const next=Number(b.dataset.machine);if(next===current)return;
  stopMachine(false);current=next;pressed('[data-machine]',b);
  const m=machines[current];$('machine-title').textContent=m.name;
  $('machine-external').href=`https://infinitemac.org/${m.year}/${encodeURIComponent(m.name)}`;
  $('machine-tasks').replaceChildren(...m.tasks.map(text=>{const li=document.createElement('li');li.textContent=text;return li;}));
  $('machine-done').checked=done.has(current);
  $('machine-status').textContent=t('已选择 '+m.name+'。点击启动才会加载系统。',m.name+' selected. It loads only when you press Start.');
 }));
 $('machine-done').addEventListener('change',e=>{if(e.target.checked)done.add(current);else done.delete(current);});
 $('machine-start').addEventListener('click',()=>{
  if(iframe)return;
  const m=machines[current],url=new URL('https://infinitemac.org/embed');
  url.searchParams.set('disk',m.name);url.searchParams.set('auto_pause','true');url.searchParams.set('library','false');url.searchParams.set('screenSize','640x480');
  iframe=document.createElement('iframe');iframe.src=url.href;iframe.title=t(`可交互的 ${m.name} 旧系统`, `Interactive ${m.name} system`);iframe.allow='cross-origin-isolated';
  $('machine-screen').append(iframe);$('machine-placeholder').hidden=true;$('machine-stop').hidden=false;$('power-light').classList.add('on');
  $('machine-status').textContent=t('正在加载系统数据。旧 Mac 的启动需要一些时间；也可在独立页面打开。','Loading system data. An old Mac takes a little time to boot; you can also open it separately.');
  loadTimer=setTimeout(()=>{$('machine-status').textContent=t(loaded?'系统已开始运行；如果尚未进入桌面，请继续等待，或在独立页面打开。':'尚未收到模拟器启动信号。可关闭后重试，或在独立页面打开。',loaded?'The machine has begun running. If the desktop is not ready, give it more time or open it separately.':'No startup signal received yet. Close and retry, or open the system separately.');},45000);
 });
 $('machine-stop').addEventListener('click',()=>{stopMachine();$('machine-start').focus({preventScroll:true});});
 window.addEventListener('message',e=>{
  if(e.origin!=='https://infinitemac.org'||e.source!==iframe?.contentWindow||e.data?.type!=='emulator_loaded')return;
  loaded=true;$('machine-status').textContent=t('系统数据已载入，机器开始运行。进入桌面后，就可以按旁边的线索探索。','System data loaded; the machine has begun running. Follow the tasks once the desktop appears.');
 });
 // The provider's auto_pause handles both viewport and page visibility, including resume.
 window.addEventListener('pagehide',()=>{stopMachine(false);audioContext?.close().catch(()=>{});});
})();
