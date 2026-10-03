# 第七份变更

精确 v6 基线 1145 文件，v7 候选 1157 文件。本轮 9 个既有文件修改，新增 12 个文件，无删除。新增中包括 8 份 Swift、C 源码/头文件/module map 三份、隐私登记一份；既有修改含 8 份 Swift 与构建脚本。全表见 manifest.json，不用累计文件数当功能完成度。

## 已经有实际调用者的部分

本地只读助手：补充设置入口 → AppRuntime → 既有 Island → OwnedSessionView → OwnedLaunchController → 本地项目/程序预检 → 同一 OwnedCodexSession/Wire → AgentSessions → 页面。登录、实际模型/effort、新建/关联恢复、一次发送、流式文本、停止本轮/断开、锁态撤销均已连接。

进程：用自有 posix_spawn + waitid/waitpid 取代这条通道的 Foundation.Process；新增有界直属退出观察、自有进程组停止升级和回收。原 PROC04 在同一探针下通过。新增正常 App 退出与原更新器终止门槛的联合协调。

协议：原始 JSON 在进入字典前拒绝重复键/非法编码/预算超限；拒绝 result/error 等歧义 envelope。增加固定版本的账号/配置请求；对真实测试出站消息做 schema 校验并修正 logout 空 params。

配置与隐私：本地明确同意才运行版本检查；独立 HOME/CODEX_HOME、有限环境、原文件改动不覆盖、项目/配置身份复核；实际账号/模型状态、诊断 opt-in、纯文本有界显示。独立 CLI 磁盘凭据和历史的保留边界有明确说明。

## 没有伪装完成的部分

新的本地入口拒绝提升权限，不是全功能自动编程。旧原生认证允许适配器保留但不作为默认工厂。Mac SDK、实际 CLI/账号、原生 UI、系统终止与能耗尚未运行。没有新 OPACK/Listener/配对互操作、设备桥、窗口 AX 执行或影片。没有修改用户真实 home、启动真实网络助手、签名或发布。

## 对历史材料的替代

part6 中“还要实现 LaunchController”和“进程必须换监督端口”的源码缺口已由本轮候选推进，不能继续照旧从零编写。part6 的 Linux PROC04 失败保留历史，当前候选以本轮原样回归为准。前六份其余范围、原蓝图与身份/设备/窗口/影片门槛继续有效。旧版测试脚本若不带 Native 模块和 StrictJSON 会漏新依赖，改用本轮 regressions.py 编译原测试。
