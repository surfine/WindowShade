# 钥匙串可用性探针（ID-14）

问题：刷脸模板用的 `kSecUseDataProtectionKeychain` 在三种构建下能不能读写？每一步返回什么 OSStatus？

探针直接编译真实的 `prototype/App/FaceTemplateKeychainStore.swift`、`prototype/Core/FaceTemplateSet.swift` 及其依赖，
只用一次性服务名 `WindowShade.KeychainProbe.<UUID>`，结束时清理，不读写生产模板。读写不弹窗（`interactionNotAllowed`）。

运行：

    bash tools/probes/keychain-availability/run.sh            # 三种都跑
    bash tools/probes/keychain-availability/run.sh adhoc      # 只跑一种：unsigned | adhoc | developer

第三种默认用本机第一个 Apple Development 证书，也可用 `WINDOWSHADE_CODESIGN_IDENTITY` 指定；没有证书就记 `not_run`。
本探针不改 `prototype/build.sh`，只做本地探针构建。

## 实测（2026-10-09，本机 macOS 27 beta，arm64）

| 构建 | 签名状态 | save | load | 清理 | 结论 |
|---|---|---|---|---|---|
| unsigned | 去掉签名后 `code object is not signed at all` | 未到达 | 未到达 | 未到达 | 进程在第一次钥匙串调用前被系统 SIGKILL（exit 137），没有 OSStatus。这是“不能运行”，不是钥匙串结论。 |
| adhoc | `codesign --sign -` | `-34018` errSecMissingEntitlement | 原始查询 `-25300` errSecItemNotFound，store 返回空 | `-34018` | 数据保护钥匙串需要 entitlement，ad-hoc 不给。 |
| developer | Apple Development（G3TN2MBQ2Q，Team FVGLY6W6S4），无 entitlements | `-34018` errSecMissingEntitlement | 同上，返回空 | `-34018` | 只签名不够：没有 keychain-access-groups 和描述文件，同样存不了。 |

逐行原始输出可由 `run.sh` 重现；`#` 开头的行是模式与服务名。

## 对产品的含义

- 三种构建下，`FaceTemplateKeychainStore` 的 save 和 delete 都返回 `errSecMissingEntitlement`。`Failure.isUnavailable` 把它归为“这台 Mac 现在存不了”（文案 `FaceTemplateKeychainStore.unavailableMessage`），不清空、不退回文件。
- 要让刷脸模板真正能存，需要的是 entitlement（钥匙串访问组）与对应描述文件，不是只换签名。当前 `build.sh` 没有这些，本包不改它。
- **已知缺口：** `load` 在不可用时返回空，因为 `errSecItemNotFound` 和“钥匙串拒绝”在这里无法区分。`FaceScanExperiment` 会把它当成“没有模板”，之后录入时才在 save 处看到“存不了”。这个语义没在本包改（会牵动调用方）。要不要让 load 也报不可用，留给集成者决定。
- 界面文案还没接：`FaceScanExperiment` 目前只写日志 `keychain unavailable`，没有把 `unavailableMessage` 显示出来，那是 AppKit 侧的事，不在本包。

## 没证明的事

- 没有在真机、正式 App 的签名与 entitlements 下测过。上面三种都是探针自己的 bundle，不是 WindowShade 本体。
- 没测锁屏状态下的 `errSecInteractionNotAllowed` 行为。
- 只测了 arm64、macOS 27 beta。
