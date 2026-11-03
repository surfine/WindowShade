# 未入库的设计底稿（lost notes）

三份被代码注释与文档反复引用的设计底稿从未随仓库提交（git 历史里从未存在），
原始文件已不可恢复。引用它们的场合统一改指本页。

| 底稿 | 被谁引用 | 幸存内容在哪 |
|---|---|---|
| `docs/direction.md`（产品方向） | GestureCoach、ElsewhereWindows、DockClickGuard、NotchThumbnailPolicy、HabitRules、NotchGlancePlan、ThumbnailLayout、SwitcherOrigin 等 18 处代码注释；design-system、design-grammar、gestures、notch、welcome、update、lid-effect | 各自的结论已沉淀在引用处与 docs/design-grammar.md、docs/README.md 的原则条目里 |
| `docs/stuck-habits.md`（卡住时的旧习惯提示） | HabitRules、HabitKeys、HabitContext、Notch+Habit、GestureCoach 等 | 规则表与误报条件在 `Core/HabitRules.swift` 的注释里；第一部分 §4.1–4.6 的分工在 `App/HabitKeys.swift`、`App/HabitContext.swift` 文件头 |
| `docs/motion-direction.md`（动效方向） | design-grammar、lid-effect | 动效令牌与原则在 `Core/FlickMotion.swift` 与 docs/design-grammar.md |

约定：新代码注释不要再引用这三个路径，指向本页或指向沉淀了结论的具体文件。
