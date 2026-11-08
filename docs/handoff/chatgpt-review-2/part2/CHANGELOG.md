# 第2份变更

新增InteractionCoordinator的可编译实现；补足part1只有规范的租约部分，但不声称已经替换Notch宿主。Contracts.swift沿用原件。

新增CodexWire、RemoteSessionGate、PresenceReadDeadline及22场景测试。D5旧Rust施工方向作废；门控仍不替代真实Swift协议实现。蓝牙超时以pending read为基准，不用最后读回年龄误判。

S1新增53处字符串形式副标题的原文/短句表、Info气泡、精确单方法补丁。T2新增一次性唤醒host及共享card，日期映射与窗口副作用仍由宿主注入。没有声称M1/T4等其余App包已经完成。

新增5个独立探针。它们只提供所写边界的证据，不能把MT符号存在、LAContext成功、BLE读回或锁态字段当完整产品验收。

film补上九章Series、共享Stage/Notch/Footage/Camera/Spring、独立竖版标题、真素材准入、九章逐帧文件和两条可播放126秒动态样片。没有伪造真机UI；无音轨。首次Remotion依赖安装未完成，保留限制。

第一轮小抄中与上述新代码相同领域的骨架以本包源码为审查对象；未覆盖领域仍不是已经施工完成的成果。详细缺口见REMAINING.md。
