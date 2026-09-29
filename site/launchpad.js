// 启动台小样的交互。只绑定 .lp-demo，文案全部取自 data 属性（无中文硬编码）。
const demo = document.querySelector('.lp-demo');
if (demo) {
  const $ = (sel) => demo.querySelector(sel);
  const overlay = $('[data-lp-overlay]');
  const overlayTitle = $('.lp-overlay-title');
  const overlayBody = $('.lp-overlay-body');
  const closeBtn = $('[data-lp-close]');
  const tabs = [...demo.querySelectorAll('[data-lp-tab]')];
  const panes = [...demo.querySelectorAll('[data-lp-pane]')];
  const data = demo.dataset;
  let opener = null;
  let open = false;

  const isOpen = () => open;
  function hide(restore = true) {
    if (!open) return;
    open = false;
    overlay.hidden = true;
    const back = opener;
    opener = null;
    if (restore && back && back.isConnected) back.focus();
  }
  function show(title, body, trigger) {
    if (!open) opener = trigger || null;
    overlayTitle.textContent = title;
    overlayBody.textContent = body;
    if (title === data.folder) overlayBody.replaceChildren(demo.querySelector("[data-lp-folder-template]").content.cloneNode(true));
    overlay.hidden = false;
    open = true;
    closeBtn.focus();
  }
  function toTab(name) {
    hide(false);
    for (const tab of tabs) {
      const on = tab.dataset.lpTab === name;
      tab.setAttribute('aria-pressed', String(on));
    }
    for (const pane of panes) pane.hidden = pane.dataset.lpPane !== name;
  }

  for (const tab of tabs) tab.addEventListener('click', () => toTab(tab.dataset.lpTab));
  closeBtn.addEventListener('click', () => hide());
  demo.addEventListener('click', (event) => {
    const groupBtn = event.target.closest('[data-lp-group]');
    if (groupBtn && demo.contains(groupBtn)) {
      const label = groupBtn.querySelector('.lp-group-label');
      show(groupBtn.querySelector('.lp-group-head').textContent, (label ? label.textContent : '') || data.folderItems, groupBtn);
      return;
    }
    const appBtn = event.target.closest('[data-lp-app]');
    if (!appBtn || !demo.contains(appBtn)) return;
    const name = appBtn.querySelector('.lp-name').textContent;
    if (appBtn.dataset.lpApp === 'tools') show(data.folder, data.folderItems, appBtn);
    else show(name, data.window, appBtn);
  });
  demo.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && isOpen()) {
      event.preventDefault();
      hide();
    }
  });
}
