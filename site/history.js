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
 // Touch browsers do not reliably send dblclick (iOS Safari least of all): count two quick taps
 // in the same spot ourselves. Mouse users keep the native dblclick.
 const onDoubleTap = (el, fn, ignore = () => false) => {
  let last = { t: 0, x: 0, y: 0 };
  el.addEventListener('pointerup', e => {
   if (e.pointerType === 'mouse' || ignore()) return;
   const now = performance.now();
   if (now - last.t < 350 && Math.hypot(e.clientX - last.x, e.clientY - last.y) < 24) { last.t = 0; fn(); return; }
   last = { t: now, x: e.clientX, y: e.clientY };
  });
 };
 const pressed = (selector, active) => document.querySelectorAll(selector).forEach(b => b.setAttribute('aria-pressed', String(b === active)));
 const spaceText = {
  open:t('选一种办法，把参考资料挪开。','Pick a way to move the reference aside.'),
  shade:t('内容收上去了，标题栏还在原处。点一下标题栏，窗口回来。','The contents rolled up; the title bar stayed put. Click it to bring the window back.'),
  minimize:t('窗口去了底部。要回来，得先去那里找。','The window went to the bottom. To get it back, you have to look there.'),
  overview:t('两扇窗口都摆出来了，位置也变了。点参考资料的标题栏，恢复原样。','Both windows are laid out, in new places. Click the reference’s title bar to put things back.')
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
  return count===0?t('已关闭。点击标题栏不会收起。','Off. Title-bar clicks will not collapse the window.'):
   t(`当前：${modifiers.length ? '按住 '+modifiers.map(k=>names[k]).join(' + ')+'，':''}连续点击 ${count} 次。`,`Current: ${modifiers.length ? 'hold '+modifiers.map(k=>names[k]).join(' + ')+' and ':''}click ${count} times in succession.`);
 }
 function toggleGesture() {
  gestureFolded=!gestureFolded;
  $('gesture-window').classList.toggle('folded',gestureFolded);
  $('gesture-bar').setAttribute('aria-expanded',String(!gestureFolded));
  $('gesture-content').setAttribute('aria-hidden',String(gestureFolded));
  $('gesture-status').textContent=t(gestureFolded?'收起了。用同样的次数再点一遍，就能展开。':'展开了，还在原来的位置。',gestureFolded?'Rolled up. Click the same number of times to unroll.':'Unrolled, in the same place.');
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
  clickTimer=setTimeout(()=>{clickCount=0;$('gesture-status').textContent=t('次数不对，没收起。','Wrong count, so nothing happened. ')+preferenceMessage();},650);
 });
 $('gesture-simulate').addEventListener('click',()=>{clearTimeout(clickTimer);clickCount=0;if(getPreference().count)toggleGesture();else $('gesture-status').textContent=preferenceMessage();});
 const platinumDesk=$('platinum-desk'),platinumWindow=$('platinum-window'),platinumBar=$('platinum-bar');
 let platinumFolded=false,drag=null,dragMoved=false;
 const platinumSay=text=>{$('platinum-result').textContent=text;};
 const movedText=()=>t(platinumFolded?'挪好了。双击标题栏或点方框展开，看窗口在哪儿打开。':'窗口跟着标题栏一起移动。',platinumFolded?'Moved. Double-click the title bar or click the box, and see where the window opens.':'The window moves with its title bar.');
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
  platinumSay(t(platinumFolded?'只剩标题栏了。拖到别处，再双击或点方框展开。':'窗口在标题栏现在的位置展开了。',platinumFolded?'Only the title bar is left. Drag it somewhere else, then double-click it or click the box.':'The contents open where the title bar now is.'));
 }
 $('platinum-collapse').addEventListener('click',togglePlatinum);
 // 1997 年的手势本身就是双击标题栏；拖动过的这一次不算双击。
 platinumBar.addEventListener('dblclick',()=>{if(!dragMoved)togglePlatinum();});
 onDoubleTap(platinumBar,togglePlatinum,()=>dragMoved);
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
 onDoubleTap($('sticky-bar'),toggleSticky);
 $('sticky-bar').addEventListener('click',e=>{if(e.detail===0)toggleSticky();});
 const machineSize = new ResizeObserver(() => {
  const screen=$('machine-screen');
  screen.style.setProperty('--machine-scale', String(Math.min(screen.clientWidth/640,screen.clientHeight/480)));
 });
 machineSize.observe($('machine-screen'));
 const machines=[
  {name:'System 7.5',year:1994,tasks:[t('打开 Apple 菜单 → Control Panels → WindowShade。','Open Apple menu → Control Panels → WindowShade.'),t('选择 2 次点击，然后双击另一个窗口的标题栏。','Choose two clicks, then double-click another window’s title bar.'),t('改成 3 次点击，再双击试试。','Switch to three clicks and double-click again.')]},
  {name:'Mac OS 8.0',year:1997,tasks:[t('打开磁盘上的文件夹，看看标题栏最右边的按钮。','Open a folder on the disk and inspect the rightmost title-bar button.'),t('点 collapse box，把窗口收起。','Click the collapse box to roll the window up.'),t('拖动标题栏，再点按钮展开，看窗口在哪儿打开。','Drag the title bar, click the box again, and see where the window opens.')]},
  {name:'Mac OS X 10.1',year:2001,tasks:[t('等待 OS X 启动，打开一个 Finder 窗口。','Let OS X boot, then open a Finder window.'),t('点黄色按钮，看窗口去了哪里。','Click the yellow button and watch where the window goes.'),t('再从 Dock 把它点回来，和前两台比一比。','Bring it back from the Dock, and compare with the other two.')]}
 ];
 let current=0, iframe=null, loadTimer, loaded=false;
 const done=new Set();
 function stopMachine(notify=true){
  clearTimeout(loadTimer);iframe?.remove();iframe=null;loaded=false;
  $('machine-placeholder').hidden=false;$('machine-stop').hidden=true;$('power-light').classList.remove('on');
  if(notify)$('machine-status').textContent=t('已关机，可以重新开机。','Shut down. You can boot it again.');
 }
 document.querySelectorAll('[data-machine]').forEach(b=>b.addEventListener('click',()=>{
  const next=Number(b.dataset.machine);if(next===current)return;
  stopMachine(false);current=next;pressed('[data-machine]',b);
  const m=machines[current];$('machine-title').textContent=m.name;
  $('machine-external').href=`https://infinitemac.org/${m.year}/${encodeURIComponent(m.name)}`;
  $('machine-tasks').replaceChildren(...m.tasks.map(text=>{const li=document.createElement('li');li.textContent=text;return li;}));
  $('machine-done').checked=done.has(current);
  $('machine-status').textContent=t('选了 '+m.name+'。点“开机”才会加载。',m.name+' selected. Nothing loads until you boot it.');
 }));
 $('machine-done').addEventListener('change',e=>{if(e.target.checked)done.add(current);else done.delete(current);});
 $('machine-start').addEventListener('click',()=>{
  if(iframe)return;
  const m=machines[current],url=new URL('https://infinitemac.org/embed');
  url.searchParams.set('disk',m.name);url.searchParams.set('auto_pause','true');url.searchParams.set('library','false');url.searchParams.set('screenSize','640x480');
  iframe=document.createElement('iframe');iframe.src=url.href;iframe.title=t(`可交互的 ${m.name} 旧系统`, `Interactive ${m.name} system`);iframe.allow='cross-origin-isolated';
  $('machine-screen').append(iframe);$('machine-placeholder').hidden=true;$('machine-stop').hidden=false;$('power-light').classList.add('on');
  $('machine-status').textContent=t('正在加载，旧 Mac 开机要一会儿。等不及可以在独立页面打开。','Loading. An old Mac takes a moment to boot; you can also open it on its own page.');
  loadTimer=setTimeout(()=>{$('machine-status').textContent=t(loaded?'已经在跑了。还没看到桌面的话再等等，或者在独立页面打开。':'旧系统还没反应。可以关机重试，或者在独立页面打开。',loaded?'The machine has begun running. If the desktop is not ready, give it more time or open it separately.':'No startup signal received yet. Close and retry, or open the system separately.');},45000);
 });
 $('machine-stop').addEventListener('click',()=>{stopMachine();$('machine-start').focus({preventScroll:true});});
 window.addEventListener('message',e=>{
  if(e.origin!=='https://infinitemac.org'||e.source!==iframe?.contentWindow||e.data?.type!=='emulator_loaded')return;
  loaded=true;$('machine-status').textContent=t('开机了。看到桌面后，照着右边的步骤试试。','It’s running. Once the desktop appears, follow the steps alongside.');
 });
 // The provider's auto_pause handles both viewport and page visibility, including resume.
 window.addEventListener('pagehide',()=>{stopMachine(false);audioContext?.close().catch(()=>{});});
})();

// Reading progress: how far through the essay (not the sources) the reader is.
(() => {
 const bar = document.querySelector('.read-progress');
 const article = document.querySelector('main article');
 if (!bar || !article) return;
 let frame = 0;
 function update() {
  frame = 0;
  const r = article.getBoundingClientRect();
  const total = r.height - innerHeight;
  const read = total > 0 ? Math.min(1, Math.max(0, -r.top / total)) : 0;
  bar.style.setProperty('--read', read.toFixed(4));
 }
 const schedule = () => { if (!frame) frame = requestAnimationFrame(update); };
 addEventListener('scroll', schedule, { passive: true });
 addEventListener('resize', schedule);
 update();
})();
