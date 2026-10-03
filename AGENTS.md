> 最终交接入口：先读 [docs/handoff/FINAL-HANDOFF.md](docs/handoff/FINAL-HANDOFF.md)。第十份保留原蓝图全部目标，覆盖旧派工顺序；不覆盖用户在实际工作区的新改动。不要再从第一份顺次套补丁，也不要默认直接在 main 上修改。
>
> 第九、十份并入后的实际状态、本机证据与复核议程见 [docs/handoff/round2-part10/REVIEW-HANDOFF.md](docs/handoff/round2-part10/REVIEW-HANDOFF.md)：**W00 的编译门槛已达成：`main` 上 `prototype/build.sh --check` 退出 0，构建参数没撤；但新二进制没签名、没在真机上跑过，主线程隔离的执行期检查是否会在真机触发仍未知**（详见该文件开头一节）。

# 项目约定

**接手前先读 [`docs/blueprint.md`](docs/blueprint.md)**：WindowShade 的总图、刘海仲裁顺序、做的顺序和十二条硬要求。
交给 DeepSeek 时，从 [`docs/handoff/START-HERE-deepseek.md`](docs/handoff/START-HERE-deepseek.md) 开始。

## 文案（产品与官网共用）

面向用户的每一句文案都按 [`docs/copy-guide.md`](docs/copy-guide.md) 写：说用户遇到的事、不说实现，
一个东西只有一个名字，一句话一件事，术语先用日常说法，能删就删。改动界面文案或官网文案时，
先读那份规则；新增用户可见字符串时用它自检，不要等用户来提醒。

固定词汇表也在那份文件里（收起/展开、卷帘条、置顶、窗口浏览……），菜单、设置、面板、官网必须一致。

## 其它

- 面向开发者的构建、签名、发布流程见 [`DEVELOPMENT.md`](DEVELOPMENT.md)。
- 面向用户的说明见 [`README_CN.md`](README_CN.md) / [`README.md`](README.md)。
