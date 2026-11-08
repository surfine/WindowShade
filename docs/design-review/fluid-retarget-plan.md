# 第26批实现边界

25基线的反向初速度符号错误已由实际配置确认，Cocoa API归一化单位已由100/200距离实测确认。实现决策在 `.statem/task.txt`，本文件保存接续细节。

用各个固定layer的各个scalar keyPath缓存解析轨迹：开始的统一CACurrentMediaTime、x0(呈现减目标)、物理v0、实际CASpring mass/stiffness/damping、duration。CASpring设明确layer.convertTime(now,from:nil) beginTime；由实际系数转换FlickSpring response=2π√(mass/stiffness)、dampingRatio=damping/(2√(mass·stiffness))。该类默认allowsOverdamping=false，ζ≥1需按实际critical语义，不引入不匹配的过阻尼轨迹。旧key存在且未到duration才取其有符号v(t)；无旧活跃动画时用调用者的initialVelocity，不再覆盖甩动初速度。

新delta非零时 normalized=-physicalVelocity/delta。拆 position.x/y、bounds.size.width/height、cornerRadius，保证中点、宽高、圆角独立交接。stripMorph仍移除所有morph前缀。近零delta但v非零不能简单清零；以同一物理解生成有限kick keyframes，明确小行程阈值/终态与时长。物理宽高与圆角不允许变负；若要削减仅削减会越界的速度，保方向，用独立数值轨迹检验，不新增空闲Timer/DisplayLink。

pendingExitMorph不再储存旧presented，performMorph在真正开始时取当前island/clip/keyLine呈现层；保持contentExitGeneration等取消逻辑。补富内容先退文字期间旧形状仍动的实际Canvas阶段。基础空内容30记录不能代替这个测试。

25隐私图只有focus-preferences的关键词图标使列多38点；依据原“WindowShade 读到的”纯文字登记表移除PrivacyRowView偶发图标分支，其他设置图标不改。这也避免把翻译后的显示名称用作这张登记表的图标身份。

优化构建新跑，原生可生成一个输入将两个已有QA enum移除@main并由新@main自有NSApp.run顺序调度，输出files互不覆盖（page frames.json+PNG、motion retarget.json）。产物身份绑定生成前原QA与生成入口，不改wrapper/构建flags/生产源码集合。组合仅减少重复编译，仍全生产源Swift6；不作已编译库捷径。

肩与companion还使用自己的动画路径，不能因Canvas改善宣称全轮廓或真机已丝滑；后续需同步路径和真机画面/时序。英语已纳入整体目标，206键运行0不等于App可选English；稳定语义身份/静态let/偏好读取边界见english-support-acceptance.md。
