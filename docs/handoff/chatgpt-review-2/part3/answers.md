# 本轮事实核对与剩余事项

已由上传记录回答：Mac测试机系统/SDK/Swift版本；CLI为Codex0.153.0、Claude2.1.283；DualSense触发器的setModeWeapon和setModeOff签名；MT的14个符号可见；当时没有hook配置。它们是2026-10-03采集记录，未在此Linux环境重新测量。

固定schema实际304份JSON；thread/resume使用threadId。本份新增测试保存一条resume请求并对该固定schema校验。结果只证明该载荷符合schema，不证明真实CLI会话可用。

第3份新增源码实测范围见VALIDATION.md。真实系统锁/解锁、BLE身份绑定、MT原始触点布局、遥控器音频/二维坐标、GameController设备行为、D5私有协议互操作、A4允许应答、能耗仍无本次实测；其中多项生产桥也未写完，详见integration/MAC-ACCEPTANCE.md。不能把“无需进一步猜测”写成“已经有正确实现”。

本机工作区连接曾尝试但失败；本轮没有连接Aaron的Mac，没有暗中启动应用或CLI，没有改home。
