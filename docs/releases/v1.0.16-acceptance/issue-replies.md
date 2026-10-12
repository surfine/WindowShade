# GitHub issue 回复草稿（1.0.16；由用户审阅后自行发布——我未推送任何外发内容）

## #39 enhancement: 双击很容易误操作（whdichrn）

**中文**

谢谢报告，1.0.16 会带上你提的方案：

- **按住 Option 双击标题栏不再收起**，这一下让给系统——临时不想让它收，按住 Option 就行，不用先去设置里关开关。（设置 → 卷帘 → 「双击标题栏收起窗口」的说明里也写了。）
- 标题栏上的按钮、输入框、标签页本来就不会被双击收起抢走，这次又核了一遍。

关于三击：系统把"双击标题栏"设成缩放/最小化时，三击的缩放/最小化由系统执行，1.0.16 里会跟着系统的动作走；但**如果鼠标（尤其部分蓝牙鼠标）不向系统报告连续点击次数，系统本身就不认为那是三击**，这种情况下三击收不到，属于设备侧差异，我没法在 App 里替它修。方便的话回一下鼠标型号，我看能否按设备特征兜底。

**English**

Thanks for the report — 1.0.16 ships the workaround you suggested:

- **Hold Option and double-click a title bar to skip rolling up.** That click goes to the system, so you can keep a window in place without turning the feature off in Settings. The Settings → Shade → “Double-click a title bar to roll up” row says so too.
- Buttons, text fields and tabs on a title bar were already protected from the fold; re-checked.

On the triple-click: when the system’s double-click action is Zoom or Minimize, 1.0.16 lets the system perform the triple-click zoom/minimize. But if the mouse (some Bluetooth mice especially) doesn’t report click counts, the system itself doesn’t see a triple-click — a device-side difference I can’t fix from inside the app. If you can share the mouse model, I’ll see whether a device-specific fallback is possible.

## #40 Request: English Translation（maxoakland）

**English**

Sorry about that — the app is Chinese-first today. 1.0.16 adds an interface-language switch:

- **Settings → Advanced → Interface language: Follow the system / 简体中文 / English.** It applies immediately, no restart. If your Mac’s first language isn’t Chinese, the app now comes up in English by default.
- What’s covered in this version: **the whole Settings interface** (window shell, Shade page, Advanced page) and the **silent-action sentences** shown in the notch. Menus, the window browser, privacy pages and the rest are still Chinese and are being translated batch by batch — I’d rather ship what’s verified than a half-translated mix.

If you hit a specific screen that’s still Chinese and blocking you, tell me which one and I’ll prioritize it.

**中文**

抱歉，目前以中文为先。1.0.16 起有界面语言开关：设置 → 高级 → 界面语言（跟随系统 / 简体中文 / English），立即生效、免重启；系统首选语言不是中文时默认就是英文。这一版覆盖**设置界面全部**（外壳、卷帘页、高级页）与**刘海上的静音短句**；菜单、窗口浏览、隐私等其余界面仍在逐批迁移。若某个界面还挡着你，告诉我具体是哪一块，我优先排它。
